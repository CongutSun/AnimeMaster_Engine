import assert from 'node:assert/strict';
import test from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import { createHash, randomBytes } from 'node:crypto';
import { BangumiMobileAuth } from './mobile_auth.mjs';

const verifier = randomBytes(32).toString('base64url');
const challenge = createHash('sha256').update(verifier).digest('base64url');
const startPath = '/auth/bangumi/mobile/start?callback_scheme=animemasteroauth&code_challenge_method=S256&code_challenge=' + challenge;

import worker, { isSafeSourceEntry } from './worker.js';

class MemoryKv {
  constructor() {
    this.values = new Map();
  }

  async get(key, type) {
    const value = this.values.get(key) ?? null;
    return type === 'json' && value ? JSON.parse(value) : value;
  }

  async put(key, value) {
    this.values.set(key, value);
  }

  async delete(key) {
    this.values.delete(key);
  }
}

function testEnvironment() {
  const db = new DatabaseSync(':memory:');
  const storage = {
    sql: { exec: (sql, ...params) => ({ toArray: () => db.prepare(sql).all(...params) }) },
    getAlarm: async () => 1,
  };
  const env = {
    BANGUMI_MOBILE_AUTH: { idFromName: name => name, get: () => object },
    BANGUMI_AUTH_KV: new MemoryKv(),
    BANGUMI_CLIENT_ID: 'test-client',
    BANGUMI_CLIENT_SECRET: 'test-secret',
    BANGUMI_CALLBACK_URL:
      'https://auth.congutsun.com/auth/bangumi/callback',
  };
  const object = new BangumiMobileAuth({ storage }, env);
  return { ...env, db };
}

test('accepts only the AnimeMaster callback scheme', async () => {
  const env = testEnvironment();
  const response = await worker.fetch(
    new Request(
      'https://auth.congutsun.com' + startPath,
      { headers: { 'cf-connecting-ip': '203.0.113.8' } },
    ),
    env,
  );

  assert.equal(response.status, 200);
  const pending = env.db.prepare("SELECT * FROM mobile_auth WHERE phase='pending'").get();
  assert.equal(JSON.parse(pending.payload).callbackScheme, 'animemasteroauth');
  assert.equal(pending.challenge, challenge);
});

test('rejects an attacker-controlled callback scheme', async () => {
  const env = testEnvironment();
  const response = await worker.fetch(
    new Request(
      'https://auth.congutsun.com/auth/bangumi/mobile/start?callback_scheme=attackerapp',
      { headers: { 'cf-connecting-ip': '203.0.113.9' } },
    ),
    env,
  );

  assert.equal(response.status, 400);
  assert.match((await response.json()).error, /unsupported callback scheme/i);
  assert.equal(env.db.prepare('SELECT COUNT(*) AS n FROM mobile_auth').get().n, 0);
});

test('rate limits repeated authorization starts', async () => {
  const env = testEnvironment();
  let response;
  for (let index = 0; index <= 20; index += 1) {
    response = await worker.fetch(
      new Request(
        'https://auth.congutsun.com' + startPath,
        { headers: { 'cf-connecting-ip': '203.0.113.10' } },
      ),
      env,
    );
  }

  assert.equal(response.status, 429);
  assert.equal(response.headers.get('retry-after'), '600');
});

test('accepts only public HTTPS source entries', () => {
  assert.equal(
    isSafeSourceEntry({
      name: 'Public source',
      baseUrl: 'https://media.example.com/api.php/provide/vod/',
    }),
    true,
  );

  for (const baseUrl of [
    'http://media.example.com',
    'https://localhost/source',
    'https://127.0.0.1/source',
    'https://10.0.0.8/source',
    'https://192.168.1.8/source',
    'https://[::1]/source',
    'https://[fd00::1]/source',
  ]) {
    assert.equal(
      isSafeSourceEntry({ name: 'Blocked source', baseUrl }),
      false,
      baseUrl,
    );
  }
});

function call(env, path, body) {
  return worker.fetch(new Request(new URL(path, 'https://gateway.example'), body === undefined ? {} : {
    method: 'POST', body: JSON.stringify(body), headers: { 'content-type': 'application/json' },
  }), env);
}

async function authorize(env, t) {
  const start = await (await call(env, startPath)).json();
  const state = new URL(start.authorization_url).searchParams.get('state');
  const callback = '/auth/bangumi/callback?state=' + state + '&code=fixture';
  t.mock.method(globalThis, 'fetch', async url => Response.json(
    url.endsWith('/v0/me') ? { username: 'reader' } :
      { access_token: 'access', refresh_token: 'refresh', expires_in: 3600 },
  ));
  const response = await call(env, callback);
  assert.equal(response.status, 302);
  assert.equal((await call(env, callback)).status, 400);
  const location = new URL(response.headers.get('location'));
  assert.equal(location.searchParams.get('request_id'), start.request_id);
  assert.equal(location.searchParams.has('code_verifier'), false);
  return location.searchParams.get('session_id');
}

test('one S256 authorization issues one usable session across concurrent confirmations', async t => {
  const env = testEnvironment();
  t.after(() => env.db.close());
  const id = await authorize(env, t);
  const path = '/auth/bangumi/mobile/session';
  assert.equal((await call(env, path + '?session_id=' + id)).status, 404);
  assert.equal((await call(env, path, { session_id: id })).status, 400);
  assert.equal((await call(env, path, { session_id: id, code_verifier: 'x'.repeat(43) })).status, 404);
  const body = { session_id: id, code_verifier: verifier };
  const responses = await Promise.all([call(env, path, body), call(env, path, body)]);
  assert.deepEqual(responses.map(r => r.status).sort(), [200, 404]);
  const session = await responses.find(r => r.ok).json();
  assert.equal(session.access_token, 'access');
  assert.ok(session.session_id.startsWith('v2.'));
  assert.equal(env.db.prepare("SELECT COUNT(*) AS n FROM mobile_auth WHERE phase='session'").get().n, 1);
  assert.equal((await call(env, path, body)).status, 404);
  const durable = { session_id: session.session_id };
  assert.equal((await call(env, '/auth/bangumi/mobile/refresh', durable)).status, 200);
  assert.equal((await call(env, '/auth/bangumi/mobile/logout', durable)).status, 200);
  assert.equal((await call(env, '/auth/bangumi/mobile/refresh', durable)).status, 404);
});

test('only valid S256 starts are accepted and expired exchange records cannot promote', async t => {
  const env = testEnvironment();
  t.after(() => env.db.close());
  for (const suffix of ['', '?code_challenge=x&code_challenge_method=S256',
    '?code_challenge_method=plain&code_challenge=' + challenge]) {
    assert.equal((await call(env, '/auth/bangumi/mobile/start' + suffix)).status, 400);
  }
  const id = await authorize(env, t);
  env.db.prepare('UPDATE mobile_auth SET deadline=0 WHERE id=?').run(id);
  assert.equal((await call(env, '/auth/bangumi/mobile/session', {
    session_id: id, code_verifier: verifier,
  })).status, 404);
  assert.equal(env.db.prepare("SELECT COUNT(*) AS n FROM mobile_auth WHERE phase='session'").get().n, 0);
});

test('existing KV sessions can still refresh and log out', async t => {
  const env = testEnvironment();
  t.after(() => env.db.close());
  await env.BANGUMI_AUTH_KV.put('session:existing', JSON.stringify({ refreshToken: 'refresh' }));
  t.mock.method(globalThis, 'fetch', async url => Response.json(
    url.endsWith('/v0/me') ? { username: 'reader' } : { access_token: 'renewed', expires_in: 3600 },
  ));
  const body = { session_id: 'existing' };
  const result = await (await call(env, '/auth/bangumi/mobile/refresh', body)).json();
  assert.equal(result.access_token, 'renewed');
  await call(env, '/auth/bangumi/mobile/logout', body);
  assert.equal(await env.BANGUMI_AUTH_KV.get('session:existing'), null);
});
