import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { DandanplayGateway, signatureHeaders, routeFor } from './dandanplay.mjs';

class Storage {
  values = new Map(); alarm = null; queue = Promise.resolve();
  async get(key) { return structuredClone(this.values.get(key)); }
  async put(key, value) {
    assert.ok(Buffer.byteLength(JSON.stringify(value)) < 128 * 1024);
    this.values.set(key, structuredClone(value));
  }
  async delete(key) { this.values.delete(key); }
  async list({ prefix = '' } = {}) { return new Map([...this.values].filter(([k]) => k.startsWith(prefix))); }
  async getAlarm() { return this.alarm; }
  async setAlarm(value) { this.alarm = value; }
  transaction(fn) {
    const task = this.queue.then(() => fn(this));
    this.queue = task.catch(() => {});
    return task;
  }
}
function setup(t, handler) {
  const original = globalThis.fetch;
  globalThis.fetch = handler ?? (async () => Response.json({ success: true, comments: [] }));
  t.after(() => { globalThis.fetch = original; });
  const storage = new Storage();
  return { storage, gateway: new DandanplayGateway({ storage }, { DANDANPLAY_APP_ID: 'test-app', DANDANPLAY_APP_SECRET: 'test-only-secret' }) };
}
function req(path, body, id = 'a'.repeat(32)) {
  return new Request(`https://example.com/dandanplay${path}`, {
    method: body ? 'POST' : 'GET',
    headers: { 'CF-Connecting-IP': '192.0.2.1', ...(body ? { 'content-type': 'application/json', 'X-Request-Id': id, 'X-Installation-Id': 'b'.repeat(32) } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
}
const sendPath = '/api/v2/comment/690001/app';
const comment = { comment: '测试', time: 12, mode: 5, color: 1 };

test('signature signs only path, using SHA256 and base64', async () => {
  const headers = await signatureHeaders('app', 'secret', '/api/v2/match', 123);
  assert.equal(headers['X-Signature'], createHash('sha256').update('app123/api/v2/matchsecret').digest('base64'));
  assert.equal(headers['X-Timestamp'], '123');
  assert.equal(headers['X-AppSecret'], undefined);
});
test('route whitelist excludes login, arbitrary proxies, and unsupported writes', () => {
  for (const path of ['/api/v2/login', '/api/v2/user/me', '/api/v2/comment/1/app', '//evil.example']) assert.equal(routeFor('GET', path), null);
  assert.equal(routeFor('DELETE', sendPath), null);
  assert.equal(routeFor('GET', '/api/v2/trending/all/rising/week').category, 'details');
});
test('concurrent read misses coalesce and cache across requests', async t => {
  let calls = 0;
  const { gateway, storage } = setup(t, async (url, options) => {
    calls++; assert.equal(url.searchParams.get('withRelated'), 'true');
    assert.equal(options.headers['X-AppId'], 'test-app');
    await new Promise(resolve => setTimeout(resolve, 15));
    return Response.json({ comments: [] });
  });
  const replies = await Promise.all(Array.from({ length: 12 }, () => gateway.fetch(req('/api/v2/comment/690001'))));
  assert.ok(replies.every(r => r.status === 200)); assert.equal(calls, 1);
  const alarm = storage.alarm;
  assert.equal((await gateway.fetch(req('/api/v2/comment/690001'))).headers.get('x-animemaster-cache'), 'HIT');
  assert.equal(storage.alarm, alarm);
  assert.equal((await gateway.quota('comments')).dailyRemaining, 4999);
});
test('invalid queries and payloads never reach upstream', async t => {
  let calls = 0; const { gateway } = setup(t, async () => { calls++; return Response.json({}); });
  for (const request of [req('/api/v2/search/episodes?anime=x'), req('/api/v2/search/episodes?anime=valid&url=https://evil.example'), req(sendPath, { ...comment, comment: 'x'.repeat(101) }), req('/api/v2/match', { fileName: '../secret', fileHash: '', fileSize: 1 })]) {
    assert.equal((await gateway.fetch(request)).status, 400);
  }
  assert.equal(calls, 0);
});
test('search enables v2 and quota uses canonical requests', async t => {
  const { gateway } = setup(t, async url => {
    assert.equal(url.searchParams.get('v2'), 'true'); return Response.json({ animes: [] });
  });
  assert.equal((await gateway.fetch(req('/api/v2/search/episodes?anime=Example&episode=1'))).status, 200);
});
test('allowlisted CDN redirects never receive application credentials', async t => {
  let calls = 0;
  const { gateway } = setup(t, async (url, options) => {
    if (++calls === 1) return new Response(null, { status: 302, headers: { location: 'https://cdn.dandanplay.net/comments.json' } });
    assert.deepEqual(options.headers, { accept: 'application/json' });
    return Response.json({ comments: [] });
  });
  assert.equal((await gateway.fetch(req('/api/v2/comment/1'))).status, 200); assert.equal(calls, 2);
});
test('untrusted redirects are refused without following', async t => {
  let calls = 0; const { gateway } = setup(t, async () => {
    calls++; return new Response(null, { status: 302, headers: { location: 'https://dandanplay.net.evil.example/' } });
  });
  assert.equal((await gateway.fetch(req('/api/v2/comment/1'))).status, 502); assert.equal(calls, 1);
});
test('HTTP 200 business errors are not cached as successful data', async t => {
  const { gateway, storage } = setup(t, async () => Response.json({ success: false, errorCode: 7, errorMessage: 'private diagnostics' }));
  const result = await gateway.fetch(req('/api/v2/bangumi/1'));
  assert.equal(result.status, 404); assert.ok(!(await result.text()).includes('private diagnostics'));
  assert.equal((await storage.list({ prefix: 'cache:' })).size, 0);
});
test('concurrent sends cannot exceed global daily allowance', async t => {
  let calls = 0;
  const { gateway } = setup(t, async (_, options) => {
    const body = JSON.parse(options.body);
    assert.equal(body.mode, 1); assert.equal(body.color, 0xffffff);
    assert.match(body.userName, /^AnimeMaster-[a-f0-9]{8}$/);
    calls++; return Response.json({ success: true });
  });
  const responses = await Promise.all(Array.from({ length: 11 }, (_, i) => gateway.fetch(req(sendPath, comment, i.toString(16).padStart(32, '0')))));
  assert.equal(responses.filter(r => r.status === 200).length, 10);
  assert.equal(responses.filter(r => r.status === 429).length, 1); assert.equal(calls, 10);
  const caps = await (await gateway.fetch(req('/capabilities'))).json();
  assert.equal(caps.quota.dailyRemaining, 0); assert.equal(caps.quota.monthlyRemaining, 230); assert.equal(caps.account, false);
});
test('idempotent replay spends no extra quota; changed content conflicts', async t => {
  let calls = 0; const { gateway } = setup(t, async () => { calls++; return Response.json({ success: true }); });
  assert.equal((await gateway.fetch(req(sendPath, comment))).status, 200);
  assert.equal((await gateway.fetch(req(sendPath, comment))).status, 200);
  assert.equal((await gateway.fetch(req(sendPath, { ...comment, comment: 'changed' }))).status, 409);
  assert.equal(calls, 1);
});
test('unknown send outcomes are reserved and cannot be submitted twice', async t => {
  let calls = 0; const { gateway } = setup(t, async () => { calls++; throw new Error('timeout'); });
  assert.equal((await gateway.fetch(req(sendPath, comment))).status, 504);
  const retry = await gateway.fetch(req(sendPath, comment));
  assert.equal(retry.status, 409); assert.equal((await retry.json()).errorCode, 'send_pending'); assert.equal(calls, 1);
});
test('monthly exhaustion and per-client limits are enforced', async t => {
  const { gateway, storage } = setup(t);
  const month = new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 7);
  await storage.put(`quota:send:month:${month}`, 240);
  assert.equal((await gateway.fetch(req(sendPath, comment))).status, 429);
  for (let i = 0; i < 89; i++) assert.equal((await gateway.fetch(req('/capabilities'))).status, 200);
  assert.equal((await gateway.fetch(req('/capabilities'))).status, 429);
});
test('cache storage stays bounded and expired records are cleaned', async t => {
  const { gateway, storage } = setup(t);
  for (let i = 0; i < 256; i++) await storage.put(`cache:${i}`, { until: Date.now() + i + 10000, data: {} });
  await gateway.fetch(req('/api/v2/comment/1'));
  assert.equal((await storage.list({ prefix: 'cache:' })).size, 256);
  await storage.put('client:expired', { until: 1 });
  await storage.put('send:expired', { until: 1 });
  await gateway.alarm();
  assert.equal(await storage.get('client:expired'), undefined); assert.equal(await storage.get('send:expired'), undefined);
});
test('successful sends invalidate comment cache', async t => {
  const { gateway, storage } = setup(t);
  await gateway.fetch(req('/api/v2/comment/690001'));
  assert.equal((await storage.list({ prefix: 'cache:' })).size, 1);
  await gateway.fetch(req(sendPath, comment));
  assert.equal((await storage.list({ prefix: 'cache:' })).size, 0);
});
test('large comment pools use compressed bounded cache records', async t => {
  let calls = 0;
  const data = { comments: Array.from({ length: 4000 }, (_, i) => ({ cid: i, p: '10,1,16777215,user', m: '这是一条用于测试压缩缓存的弹幕' })) };
  const { gateway, storage } = setup(t, async () => { calls++; return Response.json(data); });
  assert.equal((await gateway.fetch(req('/api/v2/comment/1'))).status, 200);
  const entries = await storage.list({ prefix: 'cache:' });
  assert.ok([...entries.values()][0].gzip);
  const cached = await gateway.fetch(req('/api/v2/comment/1'));
  assert.equal(cached.headers.get('x-animemaster-cache'), 'HIT');
  assert.deepEqual(await cached.json(), data); assert.equal(calls, 1);
});
