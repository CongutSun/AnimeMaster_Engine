import { createServer } from 'node:http';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';
import { handleMobileAuth } from '../bangumi_auth_worker/mobile_auth.mjs';
import { openMobileAuthStore } from './store.mjs';

const env = process.env;
for (const key of ['BANGUMI_CLIENT_ID', 'BANGUMI_CLIENT_SECRET', 'BANGUMI_CALLBACK_URL']) {
  if (!env[key]) throw new Error(`Missing required env: ${key}`);
}
const directory = fileURLToPath(new URL('./data/', import.meta.url));
const { store, close } = openMobileAuthStore(directory);
const origins = new Set((env.AUTH_ALLOWED_ORIGINS || '').split(',').map(value => value.trim()).filter(Boolean));
const cleanup = setInterval(() => store.purgeExpired(), 10 * 60_000);
cleanup.unref();

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    if (origins.has(req.headers.origin)) {
      res.setHeader('access-control-allow-origin', req.headers.origin);
      res.setHeader('access-control-allow-methods', 'GET,POST,OPTIONS');
      res.setHeader('access-control-allow-headers', 'Content-Type');
      res.setHeader('vary', 'Origin');
    }
    if (req.method === 'OPTIONS') {
      res.writeHead(204).end();
      return;
    }
    const request = new Request(url, {
      method: req.method, headers: req.headers,
      ...(req.method === 'POST' ? { body: Readable.toWeb(req), duplex: 'half' } : {}),
    });
    const response = req.method === 'GET' && url.pathname === '/health'
      ? Response.json({ ok: true }, { headers: { 'cache-control': 'no-store' } })
      : await handleMobileAuth(request, env, store);
    res.writeHead(response.status, Object.fromEntries(response.headers));
    res.end(await response.text());
  } catch {
    res.writeHead(500, { 'content-type': 'application/json', 'cache-control': 'no-store' });
    res.end(JSON.stringify({ error: 'Unable to complete authorization.' }));
  }
});
server.on('close', () => { clearInterval(cleanup); close(); });
server.listen(Number(env.PORT || 8787), () => {
  console.log(`Bangumi auth gateway listening on port ${server.address().port}`);
});
