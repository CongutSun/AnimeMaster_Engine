const DEFAULT_CALLBACK_SCHEME = 'animemasteroauth';
const PENDING_TTL_SECONDS = 600;
const SESSION_EXCHANGE_TTL_SECONDS = 600;
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 60;
const BANGUMI_API_USER_AGENT =
  'animemaster-19277/AnimeMaster/1.0.0 (Cloudflare Workers; https://animemaster-bangumi-auth.animemaster-19277.workers.dev)';
const RESOURCE_PROXY_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const RESOURCE_PROXY_ALLOWED_HOSTS = new Set([
  'mikanani.me',
  'mikanime.tv',
  'share.dmhy.org',
]);
const ALLOWED_BROWSER_ORIGINS = new Set(['https://auth.congutsun.com']);
const APP_UPDATE_MANIFEST = {
  version: '2.3.3',
  build: 33,
  apkUrl: 'https://auth.congutsun.com/download/apk/universal',
  apkUrls: {
    'android-arm64': 'https://auth.congutsun.com/download/apk/android-arm64',
    'android-arm': 'https://auth.congutsun.com/download/apk/android-arm',
    'android-x64': 'https://auth.congutsun.com/download/apk/android-x64',
    universal: 'https://auth.congutsun.com/download/apk/universal',
  },
  sha256: {
    'android-arm64': 'ed5bd84d70b95e2b27dbc0e8fd0dba860df43d5ce7a5ec36c323f84d5ac706d6',
    'android-arm': '523d369f73185db1b82d4d2170a6951d1f4f75f898d4156ea55344efeec1f26a',
    'android-x64': '760d61b2e8666b7eac09e9ad344806f7846cf574844fa7a1f71b6724106f37a5',
    universal: '29850f8233ce1c59c210ec75ea5e7abf3835170381253dc49def6b744119305d',
  },
  notes: [
    '2.3.3：修复暂停视频后弹幕继续飘动的问题。',
    '2.3.3：修复用户自定义更新源地址被忽略的 bug。',
    '2.3.3：修复滚轮监听缺少 hasClients 守卫导致的潜在 crash。',
    '2.3.3：在线源错误区分超时/连接失败/其他，各有提示。',
    '2.3.3：Dodo 动漫 HTTP → HTTPS，弹幕性能优化。',
    '2.3.3：在线源远程热更新，Worker 每 6 小时自动探活。',
    '2.3.2：GitHub Actions CI 流水线，12 条新 lint 规则。',
    '2.3.2：在线源适配器重构，60+ 站点 JSON 数据驱动。',
    '2.3.2：DI 容器引入，API 泛型缓存 helper，类型化异常体系。',
    '2.3.2：亮色主题适配，骨架屏断点对齐，ErrorStateWidget 组件。',
    '2.3.2：测试覆盖 24 → 73+，APK SHA256 校验支持。',
  ],
  publishedAt: '2026-05-04T08:00:00+08:00',
  forceUpdate: false,
};
const APK_DOWNLOAD_URLS = {
  'android-arm64':
    'https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.3.3/app-arm64-v8a-release.apk',
  'android-arm':
    'https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.3.3/app-armeabi-v7a-release.apk',
  'android-x64':
    'https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.3.3/app-x86_64-release.apk',
  universal:
    'https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.3.3/app-release.apk',
};

function applyCors(headers, request, methods = 'GET,POST,OPTIONS') {
  const origin = request?.headers?.get('origin') || '';
  if (!ALLOWED_BROWSER_ORIGINS.has(origin)) {
    return headers;
  }
  headers.set('access-control-allow-origin', origin);
  headers.set('access-control-allow-methods', methods);
  headers.set('access-control-allow-headers', 'content-type');
  headers.set('vary', 'Origin');
  return headers;
}

function json(body, status = 200, request = null) {
  const headers = applyCors(
    new Headers({
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    }),
    request,
  );
  return new Response(JSON.stringify(body), {
    status,
    headers,
  });
}

function redirect(location) {
  return new Response(null, {
    status: 302,
    headers: {
      location,
      'cache-control': 'no-store',
    },
  });
}

function proxyResponseHeaders(response, mode, request) {
  const headers = new Headers();
  headers.set(
    'content-type',
    response.headers.get('content-type') ||
      (mode === 'torrent'
        ? 'application/x-bittorrent'
        : 'application/rss+xml; charset=utf-8'),
  );
  headers.set(
    'cache-control',
    mode === 'torrent' ? 'public, max-age=86400' : 'public, max-age=300',
  );
  return applyCors(headers, request, 'GET,OPTIONS');
}

function validateProxyTarget(rawTarget, mode) {
  if (!rawTarget) {
    throw new Error('Missing proxy target url.');
  }

  const target = new URL(rawTarget);
  const host = target.hostname.toLowerCase();
  if (target.protocol !== 'https:' || !RESOURCE_PROXY_ALLOWED_HOSTS.has(host)) {
    throw new Error('Proxy target is not allowed.');
  }

  const pathname = target.pathname.toLowerCase();
  if (
    mode === 'rss' &&
    !(
      pathname.includes('/rss/') ||
      pathname.includes('/topics/rss/') ||
      pathname.endsWith('/rss.xml')
    )
  ) {
    throw new Error('Proxy target is not an RSS endpoint.');
  }

  if (
    mode === 'torrent' &&
    !(pathname.includes('/download/') || pathname.endsWith('.torrent'))
  ) {
    throw new Error('Proxy target is not a torrent endpoint.');
  }

  return target;
}

async function handleResourceProxy(request, mode) {
  const url = new URL(request.url);
  const target = validateProxyTarget(url.searchParams.get('url') || '', mode);
  const response = await fetch(target.toString(), {
    headers: {
      accept:
        mode === 'torrent'
          ? 'application/x-bittorrent,application/octet-stream,*/*'
          : 'application/rss+xml,application/xml,text/xml,*/*',
      'user-agent': RESOURCE_PROXY_USER_AGENT,
    },
  });

  if (!response.ok) {
    return json(
      {
        error: `Resource proxy fetch failed: ${response.status}`,
      },
      502,
    );
  }

  return new Response(response.body, {
    status: 200,
    headers: proxyResponseHeaders(response, mode, request),
  });
}

async function handleApkDownload(request) {
  const url = new URL(request.url);
  const abi = url.pathname.split('/').filter(Boolean).pop() || 'universal';
  const upstreamUrl = APK_DOWNLOAD_URLS[abi] || APK_DOWNLOAD_URLS.universal;
  const upstream = await fetch(upstreamUrl, {
    method: request.method === 'HEAD' ? 'HEAD' : 'GET',
    headers: {
      accept: 'application/vnd.android.package-archive,*/*',
      'user-agent': RESOURCE_PROXY_USER_AGENT,
    },
  });

  if (!upstream.ok && upstream.status !== 302) {
    return json({ error: `APK upstream fetch failed: ${upstream.status}` }, 502);
  }

  const headers = new Headers();
  headers.set(
    'content-type',
    upstream.headers.get('content-type') ||
      'application/vnd.android.package-archive',
  );
  headers.set('cache-control', 'public, max-age=300');
  applyCors(headers, request, 'GET,HEAD,OPTIONS');
  const contentLength = upstream.headers.get('content-length');
  if (contentLength) {
    headers.set('content-length', contentLength);
  }
  const fileName = upstreamUrl.split('/').pop() || 'app-release.apk';
  headers.set('content-disposition', `attachment; filename="${fileName}"`);

  return new Response(request.method === 'HEAD' ? null : upstream.body, {
    status: upstream.status,
    headers,
  });
}

function requireEnv(env, key) {
  const value = env[key];
  if (!value || `${value}`.trim().length === 0) {
    throw new Error(`Missing required env: ${key}`);
  }
  return `${value}`.trim();
}

function randomId(bytes = 16) {
  const data = new Uint8Array(bytes);
  crypto.getRandomValues(data);
  return [...data].map((value) => value.toString(16).padStart(2, '0')).join('');
}

function sanitizeCallbackScheme(value) {
  const scheme = (value || DEFAULT_CALLBACK_SCHEME).trim();
  if (!/^[a-zA-Z][a-zA-Z0-9+.-]*$/.test(scheme)) {
    throw new Error('Invalid callback scheme.');
  }
  return scheme;
}

function buildAuthorizeUrl(env, state) {
  const clientId = requireEnv(env, 'BANGUMI_CLIENT_ID');
  const callbackUrl = requireEnv(env, 'BANGUMI_CALLBACK_URL');
  const url = new URL('https://bgm.tv/oauth/authorize');
  url.searchParams.set('client_id', clientId);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('redirect_uri', callbackUrl);
  url.searchParams.set('state', state);
  return url.toString();
}

async function exchangeCode(env, code) {
  const response = await fetch('https://bgm.tv/oauth/access_token', {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/x-www-form-urlencoded',
      'user-agent': BANGUMI_API_USER_AGENT,
    },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: requireEnv(env, 'BANGUMI_CLIENT_ID'),
      client_secret: requireEnv(env, 'BANGUMI_CLIENT_SECRET'),
      code,
      redirect_uri: requireEnv(env, 'BANGUMI_CALLBACK_URL'),
    }),
  });
  if (!response.ok) {
    throw new Error(`Bangumi token exchange failed: ${response.status}`);
  }
  return response.json();
}

async function refreshToken(env, refreshTokenValue) {
  const response = await fetch('https://bgm.tv/oauth/access_token', {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/x-www-form-urlencoded',
      'user-agent': BANGUMI_API_USER_AGENT,
    },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: requireEnv(env, 'BANGUMI_CLIENT_ID'),
      client_secret: requireEnv(env, 'BANGUMI_CLIENT_SECRET'),
      refresh_token: refreshTokenValue,
      redirect_uri: requireEnv(env, 'BANGUMI_CALLBACK_URL'),
    }),
  });
  if (!response.ok) {
    throw new Error(`Bangumi token refresh failed: ${response.status}`);
  }
  return response.json();
}

async function fetchProfile(accessToken) {
  const response = await fetch('https://api.bgm.tv/v0/me', {
    headers: {
      accept: 'application/json',
      authorization: `Bearer ${accessToken}`,
      'user-agent': BANGUMI_API_USER_AGENT,
    },
  });
  if (!response.ok) {
    throw new Error(`Bangumi profile fetch failed: ${response.status}`);
  }
  return response.json();
}

function expiresAtFromNow(expiresInSeconds) {
  const seconds = Number(expiresInSeconds || 0);
  return new Date(Date.now() + Math.max(seconds, 0) * 1000).toISOString();
}

function sessionPayload(sessionId, session) {
  return {
    session_id: sessionId,
    access_token: session.accessToken,
    expires_at: session.expiresAt,
    profile: session.profile,
  };
}

async function createDurableSession(env, session) {
  const durableSessionId = randomId(20);
  await env.BANGUMI_AUTH_KV.put(
    `session:${durableSessionId}`,
    JSON.stringify(session),
    { expirationTtl: SESSION_TTL_SECONDS },
  );
  return durableSessionId;
}

async function readJson(request) {
  const text = await request.text();
  if (!text.trim()) {
    return {};
  }
  return JSON.parse(text);
}

async function handleStart(request, env) {
  const url = new URL(request.url);
  const callbackScheme = sanitizeCallbackScheme(
    url.searchParams.get('callback_scheme'),
  );
  const requestId = randomId(12);
  const state = randomId(16);
  await env.BANGUMI_AUTH_KV.put(
    `pending:${state}`,
    JSON.stringify({
      requestId,
      callbackScheme,
      createdAt: new Date().toISOString(),
    }),
    { expirationTtl: PENDING_TTL_SECONDS },
  );

  return json({
    request_id: requestId,
    authorization_url: buildAuthorizeUrl(env, state),
  });
}

async function handleCallback(request, env) {
  const url = new URL(request.url);
  const code = url.searchParams.get('code') || '';
  const state = url.searchParams.get('state') || '';
  if (!code || !state) {
    return json({ error: 'Missing code or state.' }, 400);
  }

  const pendingRaw = await env.BANGUMI_AUTH_KV.get(`pending:${state}`);
  if (!pendingRaw) {
    return json({ error: 'Invalid or expired state.' }, 400);
  }
  const pending = JSON.parse(pendingRaw);
  await env.BANGUMI_AUTH_KV.delete(`pending:${state}`);

  const token = await exchangeCode(env, code);
  const profile = await fetchProfile(token.access_token);
  const exchangeId = randomId(20);
  const session = {
    accessToken: token.access_token,
    refreshToken: token.refresh_token || '',
    expiresAt: expiresAtFromNow(token.expires_in),
    profile,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };

  await env.BANGUMI_AUTH_KV.put(
    `session_exchange:${exchangeId}`,
    JSON.stringify(session),
    { expirationTtl: SESSION_EXCHANGE_TTL_SECONDS },
  );

  const callbackScheme = sanitizeCallbackScheme(pending.callbackScheme);
  return redirect(
    `${callbackScheme}://callback?session_id=${encodeURIComponent(exchangeId)}&request_id=${encodeURIComponent(pending.requestId || '')}`,
  );
}

async function handleSession(request, env) {
  const url = new URL(request.url);
  const sessionId = url.searchParams.get('session_id') || '';
  if (!sessionId) {
    return json({ error: 'Missing session_id.' }, 400);
  }

  const exchangeKey = `session_exchange:${sessionId}`;
  const exchangeRaw = await env.BANGUMI_AUTH_KV.get(exchangeKey);
  if (!exchangeRaw) {
    return json({ error: 'Session exchange not found.' }, 404);
  }
  await env.BANGUMI_AUTH_KV.delete(exchangeKey);

  const session = JSON.parse(exchangeRaw);
  const durableSessionId = await createDurableSession(env, session);
  return json(sessionPayload(durableSessionId, session));
}

async function handleRefresh(request, env) {
  const body = await readJson(request);
  const sessionId = `${body.session_id || ''}`.trim();
  if (!sessionId) {
    return json({ error: 'Missing session_id.' }, 400);
  }

  const sessionRaw = await env.BANGUMI_AUTH_KV.get(`session:${sessionId}`);
  if (!sessionRaw) {
    return json({ error: 'Session not found.' }, 404);
  }

  const session = JSON.parse(sessionRaw);
  if (!session.refreshToken) {
    return json({ error: 'Session has no refresh token.' }, 400);
  }

  const refreshed = await refreshToken(env, session.refreshToken);
  const profile = await fetchProfile(refreshed.access_token);
  const nextSession = {
    accessToken: refreshed.access_token,
    refreshToken: refreshed.refresh_token || session.refreshToken,
    expiresAt: expiresAtFromNow(refreshed.expires_in),
    profile,
    createdAt: session.createdAt,
    updatedAt: new Date().toISOString(),
  };

  await env.BANGUMI_AUTH_KV.put(
    `session:${sessionId}`,
    JSON.stringify(nextSession),
    { expirationTtl: SESSION_TTL_SECONDS },
  );

  return json(sessionPayload(sessionId, nextSession));
}

async function handleLogout(request, env) {
  const body = await readJson(request);
  const sessionId = `${body.session_id || ''}`.trim();
  if (sessionId) {
    await env.BANGUMI_AUTH_KV.delete(`session:${sessionId}`);
  }
  return json({ ok: true });
}

// ── Online source probing ────────────────────────────────────────────────

const SOURCES_KV_KEY = 'online_sources';
const HEALTH_KV_KEY = 'online_sources_health';
const SOURCE_PROBE_TIMEOUT_MS = 5000;
const SOURCE_DEAD_THRESHOLD = 3;

// Default macCms-style sources bundled with the worker (synced from assets/online_sources.json).
const DEFAULT_SOURCES = [
  { name: '稀饭动漫', baseUrl: 'https://dm.xifanacg.com' },
  { name: '去看吧', baseUrl: 'https://www.qkan8.com' },
  { name: '異世界動畫', baseUrl: 'https://www.dmmiku.com' },
  { name: 'NT 动漫', baseUrl: 'https://www.ntdm9.com' },
  { name: '嗷呜动漫', baseUrl: 'https://www.aowu.tv' },
  { name: 'E-ACG', baseUrl: 'https://www.eacg.net' },
  { name: '七色番', baseUrl: 'https://www.7sefun.top' },
  { name: '5弹幕', baseUrl: 'https://www.5dm.link' },
  { name: 'Mutefun', baseUrl: 'https://www.91mute.com' },
  { name: '动漫妖', baseUrl: 'https://www.dmyao.com' },
  { name: '樱之空', baseUrl: 'https://www.maigo.cc' },
  { name: '风铃动漫', baseUrl: 'https://www.aafun.cc' },
  { name: '柒番', baseUrl: 'https://www.qifun.cc' },
  { name: '新番组', baseUrl: 'https://bangumi.online' },
  { name: 'Animeo', baseUrl: 'https://animoe.org' },
  { name: 'E站弹幕网', baseUrl: 'https://www.ezdmw.site' },
  { name: '西瓜卡通', baseUrl: 'https://cn.xgcartoon.com' },
  { name: '萌番', baseUrl: 'https://bilfun.cc' },
  { name: '动漫蛋', baseUrl: 'https://www.dmdm0.com' },
  { name: 'mx动漫', baseUrl: 'https://www.mxdm.xyz' },
  { name: '花子动漫', baseUrl: 'https://www.huazidm.com' },
  { name: '嘶哩嘶哩', baseUrl: 'https://www.silisilifun.com' },
  { name: 'XDM动漫', baseUrl: 'https://xuandm.com' },
  { name: '蜜桃动漫', baseUrl: 'https://www.mitaodm.com' },
  { name: '怡萱动漫', baseUrl: 'https://www.iyxdm.cn' },
  { name: '小小漫迷', baseUrl: 'https://www.xxmanmi.com' },
  { name: 'akianime', baseUrl: 'https://www.akianime.cc' },
  { name: '番薯动漫', baseUrl: 'https://www.fsdm02.com' },
  { name: 'myself动漫', baseUrl: 'https://myself-bbs.com' },
  { name: 'girlgirl爱动漫', baseUrl: 'https://bgm.girigirilove.com' },
  { name: '囧次元', baseUrl: 'https://www.jcydm1.com' },
  { name: '4K动漫', baseUrl: 'https://cn.agekkkk.com' },
  { name: '动漫巴士', baseUrl: 'https://dm84.tv' },
  { name: '奇米奇米', baseUrl: 'https://www.qimiqimi.net' },
  { name: 'clicli', baseUrl: 'https://www.clicli.cc' },
  { name: '哈哩哈哩', baseUrl: 'https://halihali1.com' },
  { name: '动漫看看', baseUrl: 'https://www.dongmankk.com' },
  { name: '樱花动漫备用', baseUrl: 'https://yinghuacd.com' },
  { name: '路漫漫', baseUrl: 'https://www.lmm52.com' },
  { name: '久久动漫', baseUrl: 'https://www.995dm.com' },
  { name: '次元方舟', baseUrl: 'https://cyfz.vip' },
  { name: '樱花动漫网', baseUrl: 'https://www.vdm8.com' },
  { name: '金阿尼动画', baseUrl: 'https://kimani22.com' },
  { name: 'AGE 备用', baseUrl: 'https://agefans.top' },
  { name: '修罗动漫', baseUrl: 'https://www.xiuluodm.com' },
  { name: '樱花动漫 74fan', baseUrl: 'https://74fan.com' },
  { name: '樱花动漫 qdtsdp', baseUrl: 'https://www.qdtsdp.com' },
  { name: '咚漫', baseUrl: 'https://www.dmps.cc' },
  { name: 'yhdm', baseUrl: 'https://www.yhdmp.cc' },
  { name: 'zyk', baseUrl: 'https://www.zykx8.com' },
  { name: 'sdmj', baseUrl: 'https://www.sdmjhq.com' },
  { name: 'D站', baseUrl: 'https://www.dilidili.wang' },
  { name: 'Zzzfun', baseUrl: 'https://www.zzzfun.com' },
  { name: 'Biminime', baseUrl: 'https://www.bimiacg10.com' },
  { name: 'AnFuns', baseUrl: 'https://www.anfuns102.net' },
  { name: 'girigirilove', baseUrl: 'https://www.girigirilove.com' },
  { name: 'omofun', baseUrl: 'https://www.omofun.com' },
];

async function handleSources(env) {
  let sources = await env.BANGUMI_AUTH_KV.get(SOURCES_KV_KEY, 'json');
  if (!sources || !Array.isArray(sources) || sources.length === 0) {
    sources = DEFAULT_SOURCES;
  }
  const healthRaw = await env.BANGUMI_AUTH_KV.get(HEALTH_KV_KEY, 'json');
  const health = healthRaw || {};
  const result = {
    version: sources.length,
    updatedAt: health._updatedAt || null,
    sources: sources.map((s) => ({
      ...s,
      available: health[s.baseUrl] === true,
    })),
  };
  return json(result);
}

async function handleScheduled(env) {
  let sources = await env.BANGUMI_AUTH_KV.get(SOURCES_KV_KEY, 'json');
  if (!sources || !Array.isArray(sources) || sources.length === 0) {
    sources = DEFAULT_SOURCES;
    await env.BANGUMI_AUTH_KV.put(SOURCES_KV_KEY, JSON.stringify(sources));
  }

  const healthRaw = await env.BANGUMI_AUTH_KV.get(HEALTH_KV_KEY, 'json');
  const health = healthRaw || {};
  const fails = health._fails || {};

  for (const src of sources) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), SOURCE_PROBE_TIMEOUT_MS);
      const resp = await fetch(src.baseUrl, {
        method: 'HEAD',
        signal: controller.signal,
        headers: { 'User-Agent': RESOURCE_PROXY_USER_AGENT },
      });
      clearTimeout(timer);
      if (resp.ok || resp.status < 500) {
        health[src.baseUrl] = true;
        fails[src.baseUrl] = 0;
      } else {
        fails[src.baseUrl] = (fails[src.baseUrl] || 0) + 1;
        if (fails[src.baseUrl] >= SOURCE_DEAD_THRESHOLD) {
          health[src.baseUrl] = false;
        }
      }
    } catch {
      fails[src.baseUrl] = (fails[src.baseUrl] || 0) + 1;
      if (fails[src.baseUrl] >= SOURCE_DEAD_THRESHOLD) {
        health[src.baseUrl] = false;
      }
    }
  }

  health._updatedAt = new Date().toISOString();
  health._fails = fails;
  await env.BANGUMI_AUTH_KV.put(HEALTH_KV_KEY, JSON.stringify(health));
  console.log(`[scheduled] Probed ${sources.length} sources, updated health map.`);
}

// ── Main export ──────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    try {
      if (request.method === 'OPTIONS') {
        return new Response(null, {
          status: 204,
          headers: applyCors(new Headers(), request),
        });
      }

      const url = new URL(request.url);
      if (request.method === 'GET' && url.pathname === '/health') {
        return json({ ok: true });
      }
      if (request.method === 'GET' && url.pathname === '/app_update.json') {
        return json(APP_UPDATE_MANIFEST);
      }
      if (request.method === 'GET' && url.pathname === '/sources.json') {
        return await handleSources(env);
      }
      if (
        (request.method === 'GET' || request.method === 'HEAD') &&
        url.pathname.startsWith('/download/apk/')
      ) {
        return await handleApkDownload(request);
      }
      if (request.method === 'GET' && url.pathname === '/proxy/rss') {
        return await handleResourceProxy(request, 'rss');
      }
      if (request.method === 'GET' && url.pathname === '/proxy/torrent') {
        return await handleResourceProxy(request, 'torrent');
      }
      if (
        request.method === 'GET' &&
        url.pathname === '/auth/bangumi/mobile/start'
      ) {
        return await handleStart(request, env);
      }
      if (
        request.method === 'GET' &&
        url.pathname === '/auth/bangumi/callback'
      ) {
        return await handleCallback(request, env);
      }
      if (
        request.method === 'GET' &&
        url.pathname === '/auth/bangumi/mobile/session'
      ) {
        return await handleSession(request, env);
      }
      if (
        request.method === 'POST' &&
        url.pathname === '/auth/bangumi/mobile/refresh'
      ) {
        return await handleRefresh(request, env);
      }
      if (
        request.method === 'POST' &&
        url.pathname === '/auth/bangumi/mobile/logout'
      ) {
        return await handleLogout(request, env);
      }
      return json({ error: 'Not found.' }, 404);
    } catch (error) {
      console.error(error);
      return json(
        {
          error:
            error instanceof Error ? error.message : 'Unknown gateway error.',
        },
        500,
      );
    }
  },
  async scheduled(event, env) {
    await handleScheduled(env);
  },
};
