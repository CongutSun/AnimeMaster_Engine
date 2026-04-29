import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const dataDir = path.join(__dirname, 'data');
const storeFile = path.join(dataDir, 'store.json');

const PORT = Number.parseInt(process.env.PORT ?? '8787', 10);
const CLIENT_ID = process.env.BANGUMI_CLIENT_ID ?? '';
const CLIENT_SECRET = process.env.BANGUMI_CLIENT_SECRET ?? '';
const CALLBACK_URL = process.env.BANGUMI_CALLBACK_URL ?? '';
const DEFAULT_CALLBACK_SCHEME =
  process.env.APP_CALLBACK_SCHEME ?? 'animemasteroauth';
const ALLOWED_BROWSER_ORIGINS = new Set(
  (process.env.AUTH_ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean),
);
const BANGUMI_API_USER_AGENT =
  process.env.BANGUMI_API_USER_AGENT ??
  'animemaster-19277/AnimeMaster/1.0.0 (Node.js Gateway)';

if (!CLIENT_ID || !CLIENT_SECRET || !CALLBACK_URL) {
  throw new Error(
    'Missing env. Required: BANGUMI_CLIENT_ID, BANGUMI_CLIENT_SECRET, BANGUMI_CALLBACK_URL',
  );
}

await mkdir(dataDir, { recursive: true });

async function loadStore() {
  try {
    const raw = await readFile(storeFile, 'utf8');
    const parsed = JSON.parse(raw);
    return {
      pending: parsed.pending ?? {},
      exchanges: parsed.exchanges ?? {},
      sessions: parsed.sessions ?? {},
    };
  } catch {
    return { pending: {}, exchanges: {}, sessions: {} };
  }
}

async function saveStore(store) {
  await writeFile(storeFile, JSON.stringify(store, null, 2), 'utf8');
}

function applyCors(headers, req) {
  const origin = req?.headers?.origin ?? '';
  if (!ALLOWED_BROWSER_ORIGINS.has(origin)) {
    return headers;
  }
  return {
    ...headers,
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    Vary: 'Origin',
  };
}

function json(res, status, body, req) {
  res.writeHead(status, applyCors({
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  }, req));
  res.end(JSON.stringify(body));
}

function redirect(res, location) {
  res.writeHead(302, {
    Location: location,
    'Cache-Control': 'no-store',
  });
  res.end();
}

async function readJsonBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  if (chunks.length === 0) {
    return {};
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function randomId(size = 24) {
  return randomBytes(size).toString('hex');
}

function sanitizeCallbackScheme(value) {
  const trimmed = (value ?? '').trim();
  if (!trimmed) {
    return DEFAULT_CALLBACK_SCHEME;
  }
  if (!/^[a-zA-Z][a-zA-Z0-9+.-]*$/.test(trimmed)) {
    throw new Error('Invalid callback scheme.');
  }
  return trimmed;
}

function buildBangumiAuthorizeUrl(state) {
  const url = new URL('https://bgm.tv/oauth/authorize');
  url.searchParams.set('client_id', CLIENT_ID);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('redirect_uri', CALLBACK_URL);
  url.searchParams.set('state', state);
  return url.toString();
}

async function exchangeCode(code) {
  const response = await fetch('https://bgm.tv/oauth/access_token', {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': BANGUMI_API_USER_AGENT,
    },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      code,
      redirect_uri: CALLBACK_URL,
    }),
  });
  if (!response.ok) {
    throw new Error(`Bangumi token exchange failed: ${response.status}`);
  }
  return response.json();
}

async function refreshToken(refreshTokenValue) {
  const response = await fetch('https://bgm.tv/oauth/access_token', {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': BANGUMI_API_USER_AGENT,
    },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      refresh_token: refreshTokenValue,
      redirect_uri: CALLBACK_URL,
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
      Accept: 'application/json',
      Authorization: `Bearer ${accessToken}`,
      'User-Agent': BANGUMI_API_USER_AGENT,
    },
  });
  if (!response.ok) {
    throw new Error(`Bangumi profile fetch failed: ${response.status}`);
  }
  return response.json();
}

function buildSessionPayload(sessionId, session) {
  return {
    session_id: sessionId,
    access_token: session.accessToken,
    expires_at: session.expiresAt,
    profile: session.profile,
  };
}

async function createDurableSession(store, session) {
  const sessionId = randomId(20);
  store.sessions[sessionId] = session;
  return sessionId;
}

function pruneStore(store) {
  const now = Date.now();
  for (const [requestId, value] of Object.entries(store.pending)) {
    if (!value?.createdAt || now - Date.parse(value.createdAt) > 10 * 60_000) {
      delete store.pending[requestId];
    }
  }
  for (const [exchangeId, value] of Object.entries(store.exchanges ?? {})) {
    if (!value?.createdAt || now - Date.parse(value.createdAt) > 10 * 60_000) {
      delete store.exchanges[exchangeId];
    }
  }
  return store;
}

const server = createServer(async (req, res) => {
  try {
    if (req.method === 'OPTIONS') {
      res.writeHead(204, applyCors({}, req));
      res.end();
      return;
    }

    const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
    const pathname = url.pathname;
    let store = pruneStore(await loadStore());

    if (req.method === 'GET' && pathname === '/health') {
      json(res, 200, { ok: true }, req);
      return;
    }

    if (req.method === 'GET' && pathname === '/auth/bangumi/mobile/start') {
      const callbackScheme = sanitizeCallbackScheme(
        url.searchParams.get('callback_scheme'),
      );
      const requestId = randomId(12);
      const state = randomId(16);
      store.pending[requestId] = {
        state,
        callbackScheme,
        createdAt: new Date().toISOString(),
      };
      await saveStore(store);
      json(res, 200, {
        request_id: requestId,
        authorization_url: buildBangumiAuthorizeUrl(state),
      }, req);
      return;
    }

    if (req.method === 'GET' && pathname === '/auth/bangumi/callback') {
      const code = url.searchParams.get('code') ?? '';
      const state = url.searchParams.get('state') ?? '';
      if (!code || !state) {
        json(res, 400, { error: 'Missing code or state.' }, req);
        return;
      }

      const pendingEntry = Object.entries(store.pending).find(
        ([, value]) => value?.state === state,
      );
      if (!pendingEntry) {
        json(res, 400, { error: 'Invalid or expired state.' }, req);
        return;
      }

      const [requestId, pending] = pendingEntry;
      const token = await exchangeCode(code);
      const profile = await fetchProfile(token.access_token);
      const exchangeId = randomId(20);
      const now = new Date();
      const expiresAt = new Date(
        now.getTime() + (Number(token.expires_in ?? 0) || 0) * 1000,
      ).toISOString();

      store.exchanges[exchangeId] = {
        accessToken: token.access_token,
        refreshToken: token.refresh_token ?? '',
        expiresAt,
        profile,
        createdAt: now.toISOString(),
        updatedAt: now.toISOString(),
      };
      delete store.pending[requestId];
      await saveStore(store);

      redirect(
        res,
        `${pending.callbackScheme}://callback?session_id=${encodeURIComponent(exchangeId)}&request_id=${encodeURIComponent(requestId)}`,
      );
      return;
    }

    if (req.method === 'GET' && pathname === '/auth/bangumi/mobile/session') {
      const sessionId = url.searchParams.get('session_id') ?? '';
      const session = store.exchanges?.[sessionId];
      if (!session) {
        json(res, 404, { error: 'Session exchange not found.' }, req);
        return;
      }
      delete store.exchanges[sessionId];
      const durableSessionId = await createDurableSession(store, session);
      await saveStore(store);
      json(res, 200, buildSessionPayload(durableSessionId, session), req);
      return;
    }

    if (req.method === 'POST' && pathname === '/auth/bangumi/mobile/refresh') {
      const body = await readJsonBody(req);
      const sessionId = body.session_id?.toString().trim() ?? '';
      const session = store.sessions[sessionId];
      if (!session) {
        json(res, 404, { error: 'Session not found.' }, req);
        return;
      }
      if (!session.refreshToken) {
        json(res, 400, { error: 'Session has no refresh token.' }, req);
        return;
      }

      const refreshed = await refreshToken(session.refreshToken);
      const profile = await fetchProfile(refreshed.access_token);
      const now = new Date();
      store.sessions[sessionId] = {
        accessToken: refreshed.access_token,
        refreshToken: refreshed.refresh_token ?? session.refreshToken,
        expiresAt: new Date(
          now.getTime() + (Number(refreshed.expires_in ?? 0) || 0) * 1000,
        ).toISOString(),
        profile,
        createdAt: session.createdAt,
        updatedAt: now.toISOString(),
      };
      await saveStore(store);
      json(res, 200, buildSessionPayload(sessionId, store.sessions[sessionId]), req);
      return;
    }

    if (req.method === 'POST' && pathname === '/auth/bangumi/mobile/logout') {
      const body = await readJsonBody(req);
      const sessionId = body.session_id?.toString().trim() ?? '';
      if (sessionId) {
        delete store.sessions[sessionId];
        await saveStore(store);
      }
      json(res, 200, { ok: true }, req);
      return;
    }

    json(res, 404, { error: 'Not found.' }, req);
  } catch (error) {
    json(res, 500, {
      error: error instanceof Error ? error.message : 'Unknown server error.',
    }, req);
  }
});

server.listen(PORT, () => {
  console.log(`Bangumi auth gateway listening on http://0.0.0.0:${PORT}`);
});
