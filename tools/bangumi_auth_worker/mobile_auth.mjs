const DEFAULT_CALLBACK_SCHEME = 'animemasteroauth';
const BANGUMI_API_USER_AGENT = 'CongutSun/AnimeMaster_Engine (Bangumi OAuth gateway)';
const grantTtl = 10 * 60_000;
export const sessionTtl = 60 * 24 * 60 * 60_000;
class AuthInputError extends Error {}

function json(body, status = 200) {
  return Response.json(body, { status, headers: {
    'cache-control': 'no-store', 'referrer-policy': 'no-referrer',
    'x-content-type-options': 'nosniff',
  } });
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

function sanitizeCallbackScheme(value, expected = DEFAULT_CALLBACK_SCHEME) {
  const scheme = (value || expected).trim().toLowerCase();
  if (scheme !== expected.toLowerCase()) {
    throw new AuthInputError('Unsupported callback scheme.');
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
      'user-agent': env.BANGUMI_API_USER_AGENT || BANGUMI_API_USER_AGENT,
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

export async function refreshToken(env, refreshTokenValue) {
  const response = await fetch('https://bgm.tv/oauth/access_token', {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/x-www-form-urlencoded',
      'user-agent': env.BANGUMI_API_USER_AGENT || BANGUMI_API_USER_AGENT,
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

export async function fetchProfile(env, accessToken) {
  const response = await fetch('https://api.bgm.tv/v0/me', {
    headers: {
      accept: 'application/json',
      authorization: `Bearer ${accessToken}`,
      'user-agent': env.BANGUMI_API_USER_AGENT || BANGUMI_API_USER_AGENT,
    },
  });
  if (!response.ok) {
    throw new Error(`Bangumi profile fetch failed: ${response.status}`);
  }
  return response.json();
}

export function expiresAtFromNow(expiresInSeconds) {
  const seconds = Number(expiresInSeconds || 0);
  return new Date(Date.now() + Math.max(seconds, 0) * 1000).toISOString();
}

export function sessionPayload(sessionId, session) {
  return {
    session_id: sessionId,
    access_token: session.accessToken,
    expires_at: session.expiresAt,
    profile: session.profile,
  };
}


export class MobileAuthStore {
  constructor(query) {
    this.query = query;
    query(`CREATE TABLE IF NOT EXISTS mobile_auth (
      id TEXT PRIMARY KEY, phase TEXT NOT NULL, challenge TEXT,
      payload TEXT NOT NULL, deadline INTEGER NOT NULL
    )`);
    query('CREATE INDEX IF NOT EXISTS mobile_auth_expiry ON mobile_auth(deadline)');
  }

  put(id, phase, challenge, payload, ttl) {
    this.query('INSERT INTO mobile_auth VALUES (?, ?, ?, ?, ?)',
      id, phase, challenge, JSON.stringify(payload), Date.now() + ttl);
  }

  takePending(state) {
    return this.query(`DELETE FROM mobile_auth WHERE id=? AND phase='pending'
      AND deadline>? RETURNING challenge, payload`, state, Date.now())[0];
  }

  redeem(exchangeId, challenge, sessionId) {
    // Rotate the key and promote the grant in the same SQLite statement.
    return this.query(`UPDATE mobile_auth SET id=?, phase='session', challenge=NULL, deadline=?
      WHERE id=? AND phase='exchange' AND challenge=? AND deadline>? RETURNING payload`,
      sessionId, Date.now() + sessionTtl, exchangeId, challenge, Date.now())[0];
  }

  purgeExpired() {
    this.query('DELETE FROM mobile_auth WHERE deadline<=?', Date.now());
  }
}

async function verifierChallenge(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9._~-]{43,128}$/.test(value)) {
    throw new AuthInputError('Invalid code verifier.');
  }
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

async function readBody(request) {
  try {
    const value = await request.json();
    if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  } catch {}
  throw new AuthInputError('Invalid JSON body.');
}

export async function handleMobileAuth(request, env, store) {
  try {
    const url = new URL(request.url);
    const route = request.method + ' ' + url.pathname;
    if (route === 'GET /auth/bangumi/mobile/start') {
      const callbackScheme = sanitizeCallbackScheme(url.searchParams.get('callback_scheme'), env.APP_CALLBACK_SCHEME);
      const challenge = url.searchParams.get('code_challenge') || '';
      if (url.searchParams.get('code_challenge_method') !== 'S256' ||
          !/^[A-Za-z0-9_-]{43}$/.test(challenge)) {
        throw new AuthInputError('An S256 code challenge is required.');
      }
      const requestId = randomId(12);
      const state = randomId();
      const authorizationUrl = buildAuthorizeUrl(env, state);
      store.put(state, 'pending', challenge, { callbackScheme, requestId }, grantTtl);
      return json({ request_id: requestId, authorization_url: authorizationUrl, code_challenge_method: 'S256' });
    }

    if (route === 'GET /auth/bangumi/callback') {
      const code = url.searchParams.get('code');
      const state = url.searchParams.get('state');
      if (!code || !state) throw new AuthInputError('Missing code or state.');
      const pending = store.takePending(state);
      if (!pending) throw new AuthInputError('Invalid or expired state.');
      const { requestId, callbackScheme } = JSON.parse(pending.payload);
      const token = await exchangeCode(env, code);
      const profile = await fetchProfile(env, token.access_token);
      const now = new Date().toISOString();
      const exchangeId = randomId(20);
      store.put(exchangeId, 'exchange', pending.challenge, {
        accessToken: token.access_token, refreshToken: token.refresh_token || '',
        expiresAt: expiresAtFromNow(token.expires_in), profile, createdAt: now, updatedAt: now,
      }, grantTtl);
      return new Response(null, { status: 302, headers: {
        location: `${callbackScheme}://callback?session_id=${exchangeId}&request_id=${requestId}`,
        'cache-control': 'no-store', 'referrer-policy': 'no-referrer',
      } });
    }

    if (route === 'POST /auth/bangumi/mobile/session') {
      const { session_id: exchangeId, code_verifier: verifier } = await readBody(request);
      if (typeof exchangeId !== 'string' || !exchangeId) throw new AuthInputError('Missing session_id.');
      const challenge = await verifierChallenge(verifier);
      const sessionId = 'v2.' + randomId(20);
      const row = store.redeem(exchangeId, challenge, sessionId);
      return row ? json(sessionPayload(sessionId, JSON.parse(row.payload))) :
        json({ error: 'Invalid or expired session exchange.' }, 404);
    }

    if (route === 'POST /auth/bangumi/mobile/refresh' || route === 'POST /auth/bangumi/mobile/logout') {
      const { session_id: id } = await readBody(request);
      if (typeof id !== 'string' || !id) throw new AuthInputError('Missing session_id.');
      if (url.pathname.endsWith('/logout')) {
        store.query("DELETE FROM mobile_auth WHERE id=? AND phase='session'", id);
        return json({ ok: true });
      }
      const row = store.query("SELECT payload FROM mobile_auth WHERE id=? AND phase='session' AND deadline>?",
        id, Date.now())[0];
      if (!row) return json({ error: 'Session not found.' }, 404);
      const session = JSON.parse(row.payload);
      if (!session.refreshToken) throw new AuthInputError('Session has no refresh token.');
      const refreshed = await refreshToken(env, session.refreshToken);
      const next = { ...session, accessToken: refreshed.access_token,
        refreshToken: refreshed.refresh_token || session.refreshToken,
        expiresAt: expiresAtFromNow(refreshed.expires_in),
        profile: await fetchProfile(env, refreshed.access_token), updatedAt: new Date().toISOString() };
      const changed = store.query(`UPDATE mobile_auth SET payload=?, deadline=?
        WHERE id=? AND phase='session' AND payload=? AND deadline>? RETURNING id`,
        JSON.stringify(next), Date.now() + sessionTtl, id, row.payload, Date.now());
      if (!changed.length) return json({ error: 'Session changed or expired.' }, 409);
      return json(sessionPayload(id, next));
    }
    return json({ error: 'Not found.' }, 404);
  } catch (error) {
    if (error instanceof AuthInputError) return json({ error: error.message }, 400);
    throw error;
  }
}

export class BangumiMobileAuth {
  constructor(state, env) {
    this.storage = state.storage;
    this.env = env;
    this.store = new MobileAuthStore((sql, ...params) => this.storage.sql.exec(sql, ...params).toArray());
  }

  async fetch(request) {
    if (await this.storage.getAlarm() === null) await this.storage.setAlarm(Date.now() + grantTtl);
    return handleMobileAuth(request, this.env, this.store);
  }

  async alarm() {
    this.store.purgeExpired();
    if (this.store.query('SELECT 1 FROM mobile_auth LIMIT 1').length) {
      await this.storage.setAlarm(Date.now() + grantTtl);
    }
  }
}
