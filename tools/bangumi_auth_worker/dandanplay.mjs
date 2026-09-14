const BASE = 'https://api.dandanplay.net';
const PREFIX = '/dandanplay';
const encoder = new TextEncoder();
const LIMITS = { search: [5000, 120000], details: [5000, 120000], comments: [5000, 120000], match: [5000, 120000], send: [10, 240] };

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), { status, headers: {
    'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store',
    'x-content-type-options': 'nosniff', ...headers,
  } });
}
function fail(message, status = 400, code = 'invalid_request') {
  return json({ success: false, errorCode: code, errorMessage: message }, status);
}
export async function signatureHeaders(appId, secret, path, timestamp = Math.floor(Date.now() / 1000)) {
  const bytes = await crypto.subtle.digest('SHA-256', encoder.encode(`${appId}${timestamp}${path}${secret}`));
  return { 'X-AppId': appId, 'X-Timestamp': String(timestamp), 'X-Signature': btoa(String.fromCharCode(...new Uint8Array(bytes))), accept: 'application/json' };
}
export function routeFor(method, path) {
  if (method === 'GET') {
    if (/^\/api\/v2\/search\/(episodes|anime)$/.test(path)) return { category: 'search', ttl: 1800, params: ['anime', 'keyword', 'episode', 'v2'] };
    if (/^\/api\/v2\/bangumi\/bgmtv\/\d{1,10}$/.test(path)) return { category: 'details', ttl: 21600, params: [] };
    if (/^\/api\/v2\/bangumi\/\d{1,12}$/.test(path)) return { category: 'details', ttl: 21600, params: [] };
    if (path === '/api/v2/bangumi/shin') return { category: 'details', ttl: 21600, params: ['filterAdultContent'] };
    if (/^\/api\/v2\/trending\/(all\/(hot|rising)\/(week|month|quarter)|new-anime\/hot\/(current-season|previous-season))$/.test(path)) return { category: 'details', ttl: 3600, params: ['limit', 'filterAdultContent'] };
    if (/^\/api\/v2\/comment\/\d{1,16}$/.test(path)) return { category: 'comments', ttl: 300, params: ['withRelated', 'chConvert'] };
  }
  if (method === 'POST' && path === '/api/v2/match') return { category: 'match', ttl: 86400, params: [] };
  if (method === 'POST' && /^\/api\/v2\/comment\/\d{1,16}\/app$/.test(path)) return { category: 'send', ttl: 0, params: [] };
  return null;
}
function quotaKeys(category, now) {
  const date = new Date(now + 8 * 3600000).toISOString();
  return [`quota:${category}:day:${date.slice(0, 10)}`, `quota:${category}:month:${date.slice(0, 7)}`];
}
async function digest(value) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value)))].map(b => b.toString(16).padStart(2, '0')).join('');
}
async function cachePayload(text) {
  if (encoder.encode(text).length <= 96 * 1024) return { data: JSON.parse(text) };
  const stream = new Blob([text]).stream().pipeThrough(new CompressionStream('gzip'));
  const bytes = new Uint8Array(await new Response(stream).arrayBuffer());
  if (bytes.length > 70 * 1024) return null;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return { gzip: btoa(binary) };
}
async function cacheData(cached) {
  if (!cached.gzip) return cached.data;
  const bytes = Uint8Array.from(atob(cached.gzip), c => c.charCodeAt(0));
  return JSON.parse(await readLimited(new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'))), 8 * 1024 * 1024));
}
async function readLimited(response, maximum) {
  if (Number(response.headers.get('content-length') || 0) > maximum) throw new Error('response_too_large');
  const reader = response.body?.getReader();
  if (!reader) return '';
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > maximum) throw new Error('response_too_large');
      chunks.push(value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return new TextDecoder().decode(bytes);
}
function validateBody(body, category) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('请求内容无效。');
  if (category === 'match') {
    const fileName = String(body.fileName || '').trim();
    const fileHash = String(body.fileHash || '').toLowerCase();
    if (!fileName || fileName.length > 300 || /[\/\\\x00-\x1f]/.test(fileName)) throw new Error('视频文件名无效。');
    if (fileHash && !/^[a-f0-9]{32}$/.test(fileHash)) throw new Error('视频指纹格式无效。');
    if (!Number.isSafeInteger(body.fileSize) || body.fileSize < 0) throw new Error('视频大小无效。');
    return { fileName, fileHash, fileSize: body.fileSize, videoDuration: Math.max(0, Math.min(86400, Math.floor(Number(body.videoDuration) || 0))), matchMode: fileHash ? 'hashAndFileName' : 'fileNameOnly' };
  }
  const comment = String(body.comment || '').trim();
  if (!comment || [...comment].length > 100 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(comment)) throw new Error('弹幕需为 1–100 个字符。');
  if (!Number.isFinite(body.time) || body.time < 0 || body.time > 86400) throw new Error('弹幕时间无效。');
  // Scrolling white comments avoid the conflicting fixed-position definitions in the upstream schema.
  return { comment, time: Math.round(body.time * 100) / 100, mode: 1, color: 0xffffff };
}

// One SQLite-backed object serializes quota reservations across every Worker region.
export class DandanplayGateway {
  constructor(state, env) { this.state = state; this.env = env; this.inflight = new Map(); }

  async quota(category, reserve = false) {
    const keys = quotaKeys(category, Date.now());
    const limits = LIMITS[category];
    return this.state.storage.transaction(async storage => {
      const values = await Promise.all(keys.map(k => storage.get(k)));
      const used = values.map(v => Number(v || 0));
      const available = used.every((n, i) => n < limits[i]);
      if (reserve && available) await Promise.all(keys.map((k, i) => storage.put(k, used[i] + 1)));
      return { available, dailyRemaining: Math.max(0, limits[0] - used[0] - (reserve && available ? 1 : 0)), monthlyRemaining: Math.max(0, limits[1] - used[1] - (reserve && available ? 1 : 0)), dailyLimit: limits[0], monthlyLimit: limits[1] };
    });
  }

  async allowClient(request) {
    const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
    const key = `client:${await digest(ip)}`;
    return this.state.storage.transaction(async storage => {
      const now = Date.now();
      const value = await storage.get(key);
      const next = !value || value.until <= now ? { count: 1, until: now + 60000 } : { ...value, count: value.count + 1 };
      if (next.count > 90) return false;
      await storage.put(key, next);
      return true;
    });
  }

  async fetch(request) {
    try {
      const url = new URL(request.url);
      if (!(await this.allowClient(request))) return fail('操作较频繁，请稍后再试。', 429, 'rate_limit');
      if (await this.state.storage.getAlarm() == null) await this.state.storage.setAlarm(Date.now() + 3600000);
      if (!this.env.DANDANPLAY_APP_ID || !this.env.DANDANPLAY_APP_SECRET) return fail('弹幕服务暂未配置，请稍后重试。', 503, 'unavailable');
      const path = url.pathname.slice(PREFIX.length);
      if (path === '/capabilities' && request.method === 'GET') return json({ success: true, gateway: true, send: true, account: false, quota: await this.quota('send'), source: '弹弹play开放弹幕网络' });
      const route = routeFor(request.method, path);
      if (!route) return fail('此接口未开放。', 404, 'unsupported');
      if (request.headers.has('authorization') || request.headers.has('x-appsecret')) return fail('此入口不接收账号令牌或应用密钥。');
      const target = new URL(path, BASE);
      for (const [key, value] of url.searchParams) {
        if (!route.params.includes(key) || value.length > 160 || target.searchParams.has(key)) return fail('查询参数无效。');
        target.searchParams.set(key, value.trim());
      }
      if (route.category === 'search') {
        const keyword = target.searchParams.get('anime') || target.searchParams.get('keyword') || '';
        if (keyword.length < 2 || keyword.length > 100) return fail('请输入 2–100 个字符的番名。');
        const episode = target.searchParams.get('episode');
        if (episode && !/^(?:\d{1,4}|[CSO]\d{1,4})$/i.test(episode)) return fail('集数格式无效。');
        target.searchParams.set('v2', 'true');
      }
      if (path.includes('/trending/')) {
        target.searchParams.set('limit', '30');
        target.searchParams.set('filterAdultContent', 'true');
      }
      if (path.endsWith('/shin')) target.searchParams.set('filterAdultContent', 'true');
      if (route.category === 'comments') {
        target.searchParams.set('withRelated', 'true');
        target.searchParams.set('chConvert', '1');
      }
      target.searchParams.sort();
      let body;
      if (request.method === 'POST') {
        if (!(request.headers.get('content-type') || '').startsWith('application/json')) return fail('需要 JSON 请求。', 415);
        try { body = validateBody(JSON.parse(await readLimited(request, 8192)), route.category); }
        catch { return fail('请求内容无效，请检查文件信息或弹幕内容。'); }
      }
      const key = await digest(`${this.env.DANDANPLAY_APP_ID}:${target}:${JSON.stringify(body || {})}`);
      if (route.category === 'send') return await this.send(request, target, body);
      const cacheKey = `cache:${key}`;
      const cached = await this.state.storage.get(cacheKey);
      if (cached?.until > Date.now()) return json(await cacheData(cached), 200, { 'x-animemaster-cache': 'HIT' });
      let task = this.inflight.get(key);
      if (!task) {
        task = this.load(target, route, body, cacheKey).finally(() => this.inflight.delete(key));
        this.inflight.set(key, task);
      }
      return (await task).clone();
    } catch { return fail('弹幕服务暂时不可用，请稍后重试。', 502, 'upstream_error'); }
  }

  async upstream(target, method, body) {
    const signal = AbortSignal.timeout(25000);
    const headers = await signatureHeaders(this.env.DANDANPLAY_APP_ID, this.env.DANDANPLAY_APP_SECRET, target.pathname);
    if (body) headers['content-type'] = 'application/json';
    let response = await fetch(target, { method, headers, body: body ? JSON.stringify(body) : undefined, redirect: 'manual', signal });
    for (let hop = 0; [301, 302, 303, 307, 308].includes(response.status) && hop < 3; hop++) {
      if (method !== 'GET') throw new Error('unexpected_redirect');
      const next = new URL(response.headers.get('location') || '', target);
      if (next.protocol !== 'https:' || !['dandanplay.net', 'dandanplay.com'].some(h => next.hostname === h || next.hostname.endsWith(`.${h}`)) || next.username || next.password) throw new Error('invalid_redirect');
      await response.body?.cancel();
      // CDN redirects receive no application credentials or user headers.
      target = next;
      response = await fetch(next, { headers: { accept: 'application/json' }, redirect: 'manual', signal });
    }
    if (response.status === 429) return fail('弹弹play当前额度或访问频率受限，请稍后再试。', 429, 'upstream_quota');
    if ([401, 403].includes(response.status)) return fail('弹弹play未授予此操作权限，或应用凭证暂不可用。', 403, 'permission_denied');
    if (!response.ok) return fail('弹弹play暂时无法响应，请稍后重试。', 502, 'upstream_error');
    const data = JSON.parse(await readLimited(response, 8 * 1024 * 1024));
    if (data.success === false || (data.errorCode != null && data.errorCode !== 0)) {
      // Upstream text may echo user input; do not return internal diagnostics.
      return fail(data.errorCode === 7 ? '未找到对应的作品或弹幕库。' : '弹弹play未能完成请求，请检查权限或稍后重试。', data.errorCode === 7 ? 404 : 422, 'upstream_rejected');
    }
    return json(data);
  }

  async load(target, route, body, cacheKey) {
    const cooldown = await this.state.storage.get(`cooldown:${route.category}`);
    if (cooldown > Date.now()) return fail('服务正在等待上游恢复，请一分钟后重试。', 429, 'upstream_quota');
    if (!(await this.quota(route.category, true)).available) return fail('本应用的接口共享额度已用完，请等待额度恢复。', 429, 'quota_exhausted');
    const response = await this.upstream(target, body ? 'POST' : 'GET', body);
    if (response.status === 429) await this.state.storage.put(`cooldown:${route.category}`, Date.now() + 60000);
    if (response.ok) {
      const text = await response.clone().text();
      const payload = await cachePayload(text);
      if (payload) {
        await this.state.storage.transaction(async storage => {
          const entries = await storage.list({ prefix: 'cache:' });
          if (entries.size >= 256 && !entries.has(cacheKey)) {
            const oldest = [...entries].sort((a, b) => a[1].until - b[1].until)[0];
            await storage.delete(oldest[0]);
          }
          await storage.put(cacheKey, { until: Date.now() + route.ttl * 1000, category: route.category, ...payload });
        });
      }
    }
    response.headers.set('x-animemaster-cache', 'MISS');
    return response;
  }

  async send(request, target, body) {
    const requestId = request.headers.get('x-request-id') || '';
    const installation = request.headers.get('x-installation-id') || '';
    if (!/^[a-f0-9-]{32,36}$/i.test(requestId) || !/^[a-f0-9-]{32,36}$/i.test(installation)) return fail('发送标识无效，请重试。');
    const identity = await digest(installation);
    body.userName = `AnimeMaster-${identity.slice(0, 8)}`;
    const key = `send:${identity}:${requestId}`;
    const fingerprint = await digest(`${target.pathname}:${JSON.stringify(body)}`);
    const previous = await this.state.storage.transaction(async storage => {
      const old = await storage.get(key);
      if (old) return old;
      await storage.put(key, { pending: true, fingerprint, until: Date.now() + 31 * 86400000 });
      return null;
    });
    if (previous) {
      if (previous.fingerprint !== fingerprint) return fail('请使用新的发送请求。', 409, 'request_conflict');
      return previous.pending ? fail('这条弹幕已提交，请稍后刷新确认，勿重复发送。', 409, 'send_pending') : json(previous.data, previous.status);
    }
    let response;
    try {
      const quota = await this.quota('send', true);
      response = quota.available ? await this.upstream(target, 'POST', body) : fail('发送弹幕的共享额度已用完，请等待额度恢复。', 429, 'quota_exhausted');
    } catch {
      // Leave the reservation pending: a timeout does not prove the write failed.
      return fail('发送结果暂未确认，请稍后刷新弹幕，勿重复发送。', 504, 'send_unknown');
    }
    const data = await response.clone().json();
    await this.state.storage.put(key, { data, status: response.status, fingerprint, until: Date.now() + 31 * 86400000 });
    if (response.ok) {
      const entries = await this.state.storage.list({ prefix: 'cache:' });
      // Comment caches can contain application comments; invalidate after writes.
      const episodeId = Number(target.pathname.split('/')[4]);
      for (const [cacheKey, value] of entries) if (value.category === 'comments' || value.data?.episodeId === episodeId || value.data?.comments) await this.state.storage.delete(cacheKey);
    }
    return response;
  }

  async alarm() {
    const entries = await this.state.storage.list();
    const now = Date.now();
    const date = new Date(now + 8 * 3600000).toISOString();
    for (const [key, value] of entries) {
      const staleQuota = key.startsWith('quota:') && !key.endsWith(date.slice(0, 10)) && !key.endsWith(date.slice(0, 7));
      if (staleQuota || (value?.until && value.until <= now) || (key.startsWith('cooldown:') && value <= now)) await this.state.storage.delete(key);
    }
    await this.state.storage.setAlarm(now + 3600000);
  }
}

export async function handleDandanplay(request, env) {
  if (!env.DANDANPLAY_GATEWAY) return fail('弹幕服务暂不可用。', 503, 'unavailable');
  return env.DANDANPLAY_GATEWAY.get(env.DANDANPLAY_GATEWAY.idFromName('shared-app-v1')).fetch(request);
}
