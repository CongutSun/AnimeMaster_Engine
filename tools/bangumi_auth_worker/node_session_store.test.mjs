import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, existsSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { openMobileAuthStore } from '../bangumi_auth_gateway/store.mjs';
import { handleMobileAuth } from './mobile_auth.mjs';

test('standalone gateway preserves existing sessions and grants survive restart exactly once', async t => {
  const directory = mkdtempSync(path.join(os.tmpdir(), 'animemaster-auth-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const profile = { username: 'reader' };
  const session = { accessToken: 'test', refreshToken: 'refresh', profile,
    updatedAt: new Date().toISOString() };
  const legacy = path.join(directory, 'store.json');
  writeFileSync(legacy, JSON.stringify({
    sessions: { existing: session }, exchanges: { obsolete: session }, pending: {},
  }));
  const verifier = 'c'.repeat(43);
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  const initial = openMobileAuthStore(directory);
  initial.store.put('grant', 'exchange', challenge, session, 60_000);
  initial.close();
  const first = openMobileAuthStore(directory), second = openMobileAuthStore(directory);
  try {
    assert.equal(existsSync(legacy), false);
    assert.equal(first.store.query("SELECT id FROM mobile_auth WHERE phase='session'")[0].id, 'existing');
    const redeem = (store, id) => handleMobileAuth(new Request('https://local.example/auth/bangumi/mobile/session', {
      method: 'POST', body: JSON.stringify({ session_id: id, code_verifier: verifier }),
    }), {}, store);
    assert.equal((await redeem(first.store, 'obsolete')).status, 404);
    const results = await Promise.all([redeem(first.store, 'grant'), redeem(second.store, 'grant')]);
    assert.deepEqual(results.map(r => r.status).sort(), [200, 404]);
    assert.equal((await results.find(r => r.ok).json()).profile.username, 'reader');
  } finally {
    first.close();
    second.close();
  }
});

test('unreadable legacy data is retained for recovery', t => {
  const directory = mkdtempSync(path.join(os.tmpdir(), 'animemaster-auth-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const legacy = path.join(directory, 'store.json');
  writeFileSync(legacy, '{');
  assert.throws(() => openMobileAuthStore(directory));
  assert.equal(existsSync(legacy), true);
});
