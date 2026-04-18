const DEFAULT_CALLBACK_SCHEME = 'animemasteroauth';
const PENDING_TTL_SECONDS = 600;
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 60;
const BANGUMI_API_USER_AGENT =
  'animemaster-19277/AnimeMaster/1.0.0 (Cloudflare Workers; https://animemaster-bangumi-auth.animemaster-19277.workers.dev)';
const APP_UPDATE_MANIFEST = {
  version: '2.1.6',
  build: 8,
  apkUrl:
    'https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.1.6/app-release.apk',
  apkUrls: {
    'android-arm64':
      'https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.1.6/app-arm64-v8a-release.apk',
    'android-arm':
      'https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.1.6/app-armeabi-v7a-release.apk',
    'android-x64':
      'https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.1.6/app-x86_64-release.apk',
    universal:
      'https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.1.6/app-release.apk',
  },
  notes: [
    '优化边下边播本地代理读取策略，减少未缓存片段导致的播放器重试和进度条跳动。',
    '下载和做种期间启用 Android 前台服务与唤醒锁，降低切到后台后任务停止的概率。',
    '下载完成后不再自动停止任务，默认进入做种状态，并在缓存中心显示上传速度。',
  ],
  publishedAt: '2026-04-18T13:01:53+08:00',
  forceUpdate: false,
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET,POST,OPTIONS',
      'access-control-allow-headers': 'content-type',
    },
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
  const sessionId = randomId(20);
  const session = {
    accessToken: token.access_token,
    refreshToken: token.refresh_token || '',
    expiresAt: expiresAtFromNow(token.expires_in),
    profile,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };

  await env.BANGUMI_AUTH_KV.put(
    `session:${sessionId}`,
    JSON.stringify(session),
    { expirationTtl: SESSION_TTL_SECONDS },
  );

  const callbackScheme = sanitizeCallbackScheme(pending.callbackScheme);
  return redirect(
    `${callbackScheme}://callback?session_id=${encodeURIComponent(sessionId)}&request_id=${encodeURIComponent(pending.requestId || '')}`,
  );
}

async function handleSession(request, env) {
  const url = new URL(request.url);
  const sessionId = url.searchParams.get('session_id') || '';
  if (!sessionId) {
    return json({ error: 'Missing session_id.' }, 400);
  }

  const sessionRaw = await env.BANGUMI_AUTH_KV.get(`session:${sessionId}`);
  if (!sessionRaw) {
    return json({ error: 'Session not found.' }, 404);
  }
  return json(sessionPayload(sessionId, JSON.parse(sessionRaw)));
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

export default {
  async fetch(request, env) {
    try {
      if (request.method === 'OPTIONS') {
        return json({}, 204);
      }

      const url = new URL(request.url);
      if (request.method === 'GET' && url.pathname === '/health') {
        return json({ ok: true });
      }
      if (request.method === 'GET' && url.pathname === '/app_update.json') {
        return json(APP_UPDATE_MANIFEST);
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
};
