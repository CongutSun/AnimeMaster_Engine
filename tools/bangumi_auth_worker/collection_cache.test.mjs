import assert from 'node:assert/strict';
import test from 'node:test';
import worker from './worker.js';

test('collection reads bypass old public cache before and after a progress write', async () => {
  const originalFetch = globalThis.fetch;
  const originalCaches = globalThis.caches;
  let progress = 5;
  let cacheReads = 0;
  globalThis.caches = { default: {
    async match() { cacheReads++; return Response.json({ data: [{ ep_status: 5 }] }); },
    async put() { throw new Error('User state must not enter public cache'); },
  } };
  globalThis.fetch = async (url, init) => {
    if (init.method === 'POST') { progress = 6; return Response.json({ ok: true }); }
    return Response.json({ data: [{ ep_status: progress }] });
  };
  const values = new Map();
  const env = { BANGUMI_AUTH_KV: {
    async get(key) { return values.get(key) ?? null; },
    async put(key, value) { values.set(key, value); },
  } };
  const base = 'https://auth.congutsun.com/bangumi/api';
  const read = () => worker.fetch(new Request(`${base}/v0/users/test/collections?type=3`), env);
  try {
    assert.equal((await (await read()).json()).data[0].ep_status, 5);
    const write = await worker.fetch(new Request(`${base}/subject/1/update/watched_eps`, {
      method: 'POST', headers: { authorization: 'Bearer test' }, body: 'watched_eps=6',
    }), env);
    assert.equal(write.status, 200);
    const response = await read();
    assert.equal((await response.json()).data[0].ep_status, 6);
    assert.equal(response.headers.get('x-animemaster-cache'), 'BYPASS');
    assert.equal(response.headers.get('cache-control'), 'private, no-store');
    assert.equal(cacheReads, 0);
  } finally { globalThis.fetch = originalFetch; globalThis.caches = originalCaches; }
});
