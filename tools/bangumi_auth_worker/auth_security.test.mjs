import assert from 'node:assert/strict';
import test from 'node:test';

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
  return {
    BANGUMI_AUTH_KV: new MemoryKv(),
    BANGUMI_CLIENT_ID: 'test-client',
    BANGUMI_CLIENT_SECRET: 'test-secret',
    BANGUMI_CALLBACK_URL:
      'https://auth.congutsun.com/auth/bangumi/callback',
  };
}

test('accepts only the AnimeMaster callback scheme', async () => {
  const env = testEnvironment();
  const response = await worker.fetch(
    new Request(
      'https://auth.congutsun.com/auth/bangumi/mobile/start?callback_scheme=animemasteroauth',
      { headers: { 'cf-connecting-ip': '203.0.113.8' } },
    ),
    env,
  );

  assert.equal(response.status, 200);
  const pendingEntry = [...env.BANGUMI_AUTH_KV.values.entries()].find(([key]) =>
    key.startsWith('pending:'),
  );
  assert.ok(pendingEntry);
  assert.equal(JSON.parse(pendingEntry[1]).callbackScheme, 'animemasteroauth');
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
  assert.equal(
    [...env.BANGUMI_AUTH_KV.values.keys()].some((key) => key.startsWith('pending:')),
    false,
  );
});

test('rate limits repeated authorization starts', async () => {
  const env = testEnvironment();
  let response;
  for (let index = 0; index <= 20; index += 1) {
    response = await worker.fetch(
      new Request(
        'https://auth.congutsun.com/auth/bangumi/mobile/start?callback_scheme=animemasteroauth',
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
