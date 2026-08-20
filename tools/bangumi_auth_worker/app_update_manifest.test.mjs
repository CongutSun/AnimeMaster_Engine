import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import worker from './worker.js';

test('Worker update endpoint matches the release manifest', async () => {
  const manifestUrl = new URL('../../release/app_update.json', import.meta.url);
  const expected = JSON.parse(await readFile(manifestUrl, 'utf8'));
  const response = await worker.fetch(
    new Request('https://auth.congutsun.com/app_update.json'),
    {},
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), expected);
});
