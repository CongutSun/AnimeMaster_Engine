import {
  buildYearRankingCacheKeyUrl,
  buildYearRankingSearchPayload,
  renderYearRankingHtml,
  selectYearRankingSubjects,
} from './year_ranking.mjs';

import { handleDandanplay } from './dandanplay.mjs';
export { DandanplayGateway } from './dandanplay.mjs';

import { refreshToken, fetchProfile, expiresAtFromNow, sessionPayload } from './mobile_auth.mjs';
export { BangumiMobileAuth } from './mobile_auth.mjs';

class RequestValidationError extends Error {}
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 60;
const BANGUMI_API_USER_AGENT =
  'CongutSun/AnimeMaster_Engine/2.4.9 (Cloudflare Workers; https://auth.congutsun.com)';
const RESOURCE_PROXY_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const RESOURCE_PROXY_ALLOWED_HOSTS = new Set([
  'mikanani.me',
  'mikanime.tv',
  'share.dmhy.org',
]);
const ALLOWED_BROWSER_ORIGINS = new Set(['https://auth.congutsun.com']);
const RATE_LIMITS = {
  authStart: { requests: 20, windowSeconds: 600 },
  authSession: { requests: 60, windowSeconds: 600 },
  bangumiProxy: { requests: 600, windowSeconds: 300 },
};
const BANGUMI_PROXY_TARGETS = {
  '/bangumi/api': 'https://api.bgm.tv',
  '/bangumi/web': 'https://bgm.tv',
  '/bangumi/chii': 'https://chii.in',
};
const BANGUMI_PROXY_METHODS = new Set([
  'GET',
  'HEAD',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
]);
const BANGUMI_PROXY_REQUEST_HEADERS = [
  'authorization',
  'content-type',
  'accept',
  'accept-language',
];
const APP_UPDATE_MANIFEST = {
  "version": "2.4.9",
  "build": 4054,
  "apkUrl": "https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.4.9/app-release.apk",
  "notes": [
    "番剧详情页新增一键续播，显示上次观看的集数、进度和可用缓存；B站视频可回到上次观看的分 P。",
    "分集页与全屏播放优先使用完整缓存，换源或缓存起播失败时再查找在线片源；分集评论在打开时加载。",
    "支持跨分页连续选集和播放下一集，合并重复的资源搜索入口；缓存文件缺失或大小异常时给出提示。",
    "修复 Bangumi 收藏超过 100 条后显示不全、RSS 漏匹配在看作品的问题。",
    "加固 Bangumi 登录会话的一次性兑换，限制片源探测实际读取的数据量。",
    "修复小屏大字号下键盘弹起时 B站搜索页溢出的问题。",
    "下载中心支持选择空闲时做种或完成后停止做种，系统通知区分下载和上传状态。"
  ],
  "publishedAt": "2026-11-23T21:40:35+08:00",
  "forceUpdate": false,
  "apkUrls": {
    "android-arm64": "https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.4.9/app-arm64-v8a-release.apk",
    "android-arm": "https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.4.9/app-armeabi-v7a-release.apk",
    "android-x64": "https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.4.9/app-x86_64-release.apk",
    "universal": "https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v2.4.9/app-release.apk"
  },
  "sha256": {
    "android-arm64": "7f2cbf4d36acbb2d75d2295f22a360d7ea1909b5a915b21750283bbc034f6d3b",
    "android-arm": "514f0ff3c87c82e3c95c05160629f281895accc0cb95ec331a878554321fc3b0",
    "android-x64": "54e8f7777838ab5a7277ab60ede5e40046b4f97e8748c38c9eb6903a94c87009",
    "universal": "6773b9000de42426534cf6900a60b780ad04a786e8588d3a3d758bb53250dd53"
  }
};
const APK_DOWNLOAD_URLS = APP_UPDATE_MANIFEST.apkUrls;

function applyCors(headers, request, methods = 'GET,POST,OPTIONS') {
  const origin = request?.headers?.get('origin') || '';
  if (!ALLOWED_BROWSER_ORIGINS.has(origin)) {
    return headers;
  }
  headers.set('access-control-allow-origin', origin);
  headers.set('access-control-allow-methods', methods);
  headers.set('access-control-allow-headers', 'authorization,content-type');
  headers.set('vary', 'Origin');
  return headers;
}

function json(body, status = 200, request = null) {
  const headers = applyCors(
    new Headers({
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
    }),
    request,
  );
  return new Response(JSON.stringify(body), {
    status,
    headers,
  });
}

function proxyResponseHeaders(response, mode, request) {
  const headers = new Headers();
  headers.set(
    'content-type',
    response.headers.get('content-type') ||
      (mode === 'torrent'
        ? 'application/x-bittorrent'
        : 'application/rss+xml; charset=utf-8'),
  );
  headers.set(
    'cache-control',
    mode === 'torrent' ? 'public, max-age=86400' : 'public, max-age=300',
  );
  return applyCors(headers, request, 'GET,OPTIONS');
}

function validateProxyTarget(rawTarget, mode) {
  if (!rawTarget) {
    throw new Error('Missing proxy target url.');
  }

  const target = new URL(rawTarget);
  const host = target.hostname.toLowerCase();
  if (target.protocol !== 'https:' || !RESOURCE_PROXY_ALLOWED_HOSTS.has(host)) {
    throw new Error('Proxy target is not allowed.');
  }

  const pathname = target.pathname.toLowerCase();
  if (
    mode === 'rss' &&
    !(
      pathname.includes('/rss/') ||
      pathname.includes('/topics/rss/') ||
      pathname.endsWith('/rss.xml')
    )
  ) {
    throw new Error('Proxy target is not an RSS endpoint.');
  }

  if (
    mode === 'torrent' &&
    !(pathname.includes('/download/') || pathname.endsWith('.torrent'))
  ) {
    throw new Error('Proxy target is not a torrent endpoint.');
  }

  return target;
}

async function handleResourceProxy(request, mode) {
  const url = new URL(request.url);
  const target = validateProxyTarget(url.searchParams.get('url') || '', mode);
  const response = await fetch(target.toString(), {
    headers: {
      accept:
        mode === 'torrent'
          ? 'application/x-bittorrent,application/octet-stream,*/*'
          : 'application/rss+xml,application/xml,text/xml,*/*',
      'user-agent': RESOURCE_PROXY_USER_AGENT,
    },
  });

  if (!response.ok) {
    return json(
      {
        error: `Resource proxy fetch failed: ${response.status}`,
      },
      502,
    );
  }

  return new Response(response.body, {
    status: 200,
    headers: proxyResponseHeaders(response, mode, request),
  });
}

async function handleApkDownload(request) {
  const url = new URL(request.url);
  const abi = url.pathname.split('/').filter(Boolean).pop() || 'universal';
  const upstreamUrl = APK_DOWNLOAD_URLS[abi] || APK_DOWNLOAD_URLS.universal;
  const upstream = await fetch(upstreamUrl, {
    method: request.method === 'HEAD' ? 'HEAD' : 'GET',
    headers: {
      accept: 'application/vnd.android.package-archive,*/*',
      'user-agent': RESOURCE_PROXY_USER_AGENT,
    },
  });

  if (!upstream.ok && upstream.status !== 302) {
    return json({ error: `APK upstream fetch failed: ${upstream.status}` }, 502);
  }

  const headers = new Headers();
  headers.set(
    'content-type',
    upstream.headers.get('content-type') ||
      'application/vnd.android.package-archive',
  );
  headers.set('cache-control', 'public, max-age=300');
  applyCors(headers, request, 'GET,HEAD,OPTIONS');
  const contentLength = upstream.headers.get('content-length');
  if (contentLength) {
    headers.set('content-length', contentLength);
  }
  const fileName = upstreamUrl.split('/').pop() || 'app-release.apk';
  headers.set('content-disposition', `attachment; filename="${fileName}"`);

  return new Response(request.method === 'HEAD' ? null : upstream.body, {
    status: upstream.status,
    headers,
  });
}

function findBangumiProxyPrefix(pathname) {
  for (const prefix of Object.keys(BANGUMI_PROXY_TARGETS)) {
    if (pathname === prefix || pathname.startsWith(`${prefix}/`)) {
      return prefix;
    }
  }
  return null;
}

function buildBangumiProxyTarget(requestUrl, prefix) {
  const source = new URL(requestUrl);
  let pathname = source.pathname.slice(prefix.length);
  if (!pathname) {
    pathname = '/';
  }
  if (!pathname.startsWith('/')) {
    pathname = `/${pathname}`;
  }
  const target = new URL(pathname, BANGUMI_PROXY_TARGETS[prefix]);
  target.search = source.search;
  return target;
}

function isBangumiImageHost(hostname) {
  const host = hostname.toLowerCase();
  return (
    host === 'bgm.tv' ||
    host === 'chii.in' ||
    host.endsWith('.bgm.tv') ||
    host.endsWith('.chii.in')
  );
}

function validateBangumiImageTarget(rawTarget) {
  if (!rawTarget) {
    throw new Error('Missing Bangumi image url.');
  }

  const normalized = rawTarget.startsWith('//') ? `https:${rawTarget}` : rawTarget;
  const target = new URL(normalized);
  if (target.protocol !== 'https:' || !isBangumiImageHost(target.hostname)) {
    throw new Error('Bangumi image target is not allowed.');
  }
  return target;
}

function bangumiProxyMode(prefix) {
  if (prefix === '/bangumi/api') return 'api';
  if (prefix === '/bangumi/chii') return 'html';
  return 'html';
}

function bangumiAcceptHeader(mode) {
  if (mode === 'api') {
    return 'application/json,*/*;q=0.8';
  }
  if (mode === 'image') {
    return 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8';
  }
  return 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
}

function buildBangumiRequestHeaders(request, target, mode) {
  const headers = new Headers();
  headers.set('user-agent', BANGUMI_API_USER_AGENT);
  headers.set('accept', bangumiAcceptHeader(mode));
  headers.set('referer', `${target.origin}/`);

  for (const name of BANGUMI_PROXY_REQUEST_HEADERS) {
    const value = request.headers.get(name);
    if (value) {
      headers.set(name, value);
    }
  }
  return headers;
}

function bangumiCacheTtlSeconds(target, mode) {
  // User state must bypass even cache entries created by earlier deployments.
  if (/^\/v0\/users(?:\/|$)/i.test(target.pathname)) {
    return 0;
  }
  if (mode === 'image') {
    return 60 * 60 * 24 * 7;
  }

  const pathname = target.pathname.toLowerCase();
  if (pathname === '/calendar') {
    return 60 * 60;
  }
  if (pathname.includes('/comments') || pathname.startsWith('/ep/')) {
    return 60 * 10;
  }
  if (
    pathname.startsWith('/v0/subjects') ||
    pathname.startsWith('/v0/characters') ||
    pathname.startsWith('/v0/persons') ||
    pathname.startsWith('/v0/episodes') ||
    pathname.startsWith('/anime/browser')
  ) {
    return 60 * 60 * 6;
  }
  return 60 * 60;
}

function bangumiResponseHeaders(upstream, request, cacheTtlSeconds) {
  const headers = new Headers();
  const contentType = upstream.headers.get('content-type');
  if (contentType) {
    headers.set('content-type', contentType);
  }
  const etag = upstream.headers.get('etag');
  if (etag) {
    headers.set('etag', etag);
  }
  const lastModified = upstream.headers.get('last-modified');
  if (lastModified) {
    headers.set('last-modified', lastModified);
  }
  const cacheableMethod = request.method === 'GET' || request.method === 'HEAD';
  const cacheableRequest =
    cacheableMethod &&
    upstream.ok &&
    !request.headers.has('authorization') &&
    !upstream.headers.has('set-cookie');
  headers.set(
    'cache-control',
    cacheableRequest && cacheTtlSeconds > 0
      ? `public, max-age=${cacheTtlSeconds}`
      : 'private, no-store',
  );
  return applyCors(headers, request, 'GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS');
}

function canCacheBangumiResponse(request, upstream, cacheTtlSeconds) {
  return (
    request.method === 'GET' &&
    cacheTtlSeconds > 0 &&
    upstream.ok &&
    !request.headers.has('authorization') &&
    !upstream.headers.has('set-cookie')
  );
}

function cachedBangumiResponse(response, request) {
  const headers = new Headers(response.headers);
  headers.set('x-animemaster-cache', 'HIT');
  applyCors(headers, request, 'GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS');
  return new Response(request.method === 'HEAD' ? null : response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

async function fetchBangumiTarget(request, target, mode) {
  const init = {
    method: request.method,
    headers: buildBangumiRequestHeaders(request, target, mode),
    redirect: 'follow',
  };
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    init.body = request.body;
  }
  return fetch(target.toString(), init);
}

function blockedYearRankingYear(request, target, mode, upstream) {
  // Both web proxies use HTML mode, so also pin this fallback to bgm.tv.
  const pathMatch = /^\/anime\/browser\/airtime\/(\d{4})\/?$/.exec(
    target.pathname,
  );
  if (
    mode !== 'html' ||
    target.origin !== BANGUMI_PROXY_TARGETS['/bangumi/web'] ||
    (request.method !== 'GET' && request.method !== 'HEAD') ||
    upstream.status !== 403 ||
    !pathMatch
  ) {
    return null;
  }

  return Number(pathMatch[1]);
}

async function fetchYearRankingApiFallback(year) {
  try {
    const searchUrl = new URL(
      '/v0/search/subjects',
      BANGUMI_PROXY_TARGETS['/bangumi/api'],
    );
    searchUrl.searchParams.set('limit', '50');
    searchUrl.searchParams.set('offset', '0');

    const apiResponse = await fetch(searchUrl.toString(), {
      method: 'POST',
      headers: {
        'user-agent': BANGUMI_API_USER_AGENT,
        accept: 'application/json',
        'content-type': 'application/json',
      },
      body: JSON.stringify(buildYearRankingSearchPayload(year)),
    });
    if (!apiResponse.ok) return null;

    const payload = await apiResponse.json();
    const subjects = selectYearRankingSubjects(payload?.data, year, 10);
    if (subjects.length === 0) return null;

    return new Response(renderYearRankingHtml(subjects), {
      status: 200,
      headers: { 'content-type': 'text/html; charset=utf-8' },
    });
  } catch (error) {
    console.error('Bangumi year-ranking API fallback failed.', error);
    return null;
  }
}

async function handleBangumiProxy(request, prefix) {
  if (!BANGUMI_PROXY_METHODS.has(request.method)) {
    return json({ error: 'Bangumi proxy method is not allowed.' }, 405, request);
  }

  const target = buildBangumiProxyTarget(request.url, prefix);
  const mode = bangumiProxyMode(prefix);
  const cacheTtl = request.headers.has('authorization')
    ? 0
    : bangumiCacheTtlSeconds(target, mode);
  const cacheKey =
    request.method === 'GET' && cacheTtl > 0
      ? new Request(buildYearRankingCacheKeyUrl(target).toString(), {
          method: 'GET',
          headers: { accept: bangumiAcceptHeader(mode) },
        })
      : null;

  if (cacheKey) {
    const cached = await caches.default.match(cacheKey);
    if (cached) {
      return cachedBangumiResponse(cached, request);
    }
  }

  let upstream = await fetchBangumiTarget(request, target, mode);
  let usedYearRankingFallback = false;
  const fallbackYear = blockedYearRankingYear(
    request,
    target,
    mode,
    upstream,
  );
  if (fallbackYear !== null) {
    const fallback = await fetchYearRankingApiFallback(fallbackYear);
    if (fallback) {
      upstream = fallback;
      usedYearRankingFallback = true;
    }
  }

  const headers = bangumiResponseHeaders(upstream, request, cacheTtl);
  headers.set('x-animemaster-cache', cacheKey ? 'MISS' : 'BYPASS');
  if (usedYearRankingFallback) {
    headers.set('x-animemaster-fallback', 'year-ranking-api');
  }
  const response = new Response(
    request.method === 'HEAD' ? null : upstream.body,
    {
      status: upstream.status,
      statusText: upstream.statusText,
      headers,
    },
  );

  if (cacheKey && canCacheBangumiResponse(request, upstream, cacheTtl)) {
    await caches.default.put(cacheKey, response.clone());
  }
  return response;
}

async function handleBangumiImageProxy(request) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return json({ error: 'Bangumi image method is not allowed.' }, 405, request);
  }

  const url = new URL(request.url);
  const target = validateBangumiImageTarget(url.searchParams.get('url') || '');
  const cacheTtl = bangumiCacheTtlSeconds(target, 'image');
  const cacheKey = new Request(target.toString(), {
    method: 'GET',
    headers: { accept: bangumiAcceptHeader('image') },
  });
  const cached = await caches.default.match(cacheKey);
  if (cached) {
    return cachedBangumiResponse(cached, request);
  }

  const upstream = await fetchBangumiTarget(request, target, 'image');
  const headers = bangumiResponseHeaders(upstream, request, cacheTtl);
  headers.set('x-animemaster-cache', 'MISS');
  const response = new Response(
    request.method === 'HEAD' ? null : upstream.body,
    {
      status: upstream.status,
      statusText: upstream.statusText,
      headers,
    },
  );
  if (upstream.ok && !upstream.headers.has('set-cookie')) {
    await caches.default.put(cacheKey, response.clone());
  }
  return response;
}

async function sha256Hex(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

async function enforceRateLimit(request, env, scope, config) {
  if (!env.BANGUMI_AUTH_KV) {
    return null;
  }
  const clientAddress =
    request.headers.get('cf-connecting-ip') ||
    request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ||
    'unknown';
  const windowId = Math.floor(Date.now() / (config.windowSeconds * 1000));
  const clientKey = await sha256Hex(clientAddress);
  const key = `rate:${scope}:${windowId}:${clientKey}`;
  const count = Number.parseInt((await env.BANGUMI_AUTH_KV.get(key)) || '0', 10);
  if (count >= config.requests) {
    const response = json({ error: 'Too many requests.' }, 429, request);
    response.headers.set('retry-after', `${config.windowSeconds}`);
    return response;
  }
  await env.BANGUMI_AUTH_KV.put(key, `${count + 1}`, {
    expirationTtl: config.windowSeconds + 60,
  });
  return null;
}

async function readJson(request) {
  try {
    const body = await request.json();
    if (body && typeof body === 'object' && !Array.isArray(body)) return body;
  } catch {}
  throw new RequestValidationError('Invalid JSON body.');
}

function mobileAuth(request, env) {
  const id = env.BANGUMI_MOBILE_AUTH.idFromName('mobile-sessions');
  return env.BANGUMI_MOBILE_AUTH.get(id).fetch(request);
}

async function usesNewSession(request) {
  const body = await readJson(request.clone());
  return typeof body.session_id === 'string' && body.session_id.startsWith('v2.');
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
  const profile = await fetchProfile(env, refreshed.access_token);
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

// ── Online source probing ────────────────────────────────────────────────

const SOURCES_KV_KEY = 'online_sources';
const HEALTH_KV_KEY = 'online_sources_health';
const SOURCE_PROBE_TIMEOUT_MS = 5000;
const SOURCE_DEAD_THRESHOLD = 3;

// Default macCms-style sources bundled with the worker (synced from assets/online_sources.json).
const DEFAULT_SOURCES = [
  { name: '稀饭动漫', baseUrl: 'https://dm.xifanacg.com' },
  { name: '去看吧', baseUrl: 'https://www.qkan8.com' },
  { name: '異世界動畫', baseUrl: 'https://www.dmmiku.com' },
  { name: 'NT 动漫', baseUrl: 'https://www.ntdm9.com' },
  { name: '嗷呜动漫', baseUrl: 'https://www.aowu.tv' },
  { name: 'E-ACG', baseUrl: 'https://www.eacg.net' },
  { name: '七色番', baseUrl: 'https://www.7sefun.top' },
  { name: '5弹幕', baseUrl: 'https://www.5dm.link' },
  { name: 'Mutefun', baseUrl: 'https://www.91mute.com' },
  { name: '动漫妖', baseUrl: 'https://www.dmyao.com' },
  { name: '樱之空', baseUrl: 'https://www.maigo.cc' },
  { name: '风铃动漫', baseUrl: 'https://www.aafun.cc' },
  { name: '柒番', baseUrl: 'https://www.qifun.cc' },
  { name: '新番组', baseUrl: 'https://bangumi.online' },
  { name: 'Animeo', baseUrl: 'https://animoe.org' },
  { name: 'E站弹幕网', baseUrl: 'https://www.ezdmw.site' },
  { name: '西瓜卡通', baseUrl: 'https://cn.xgcartoon.com' },
  { name: '萌番', baseUrl: 'https://bilfun.cc' },
  { name: '动漫蛋', baseUrl: 'https://www.dmdm0.com' },
  { name: 'mx动漫', baseUrl: 'https://www.mxdm.xyz' },
  { name: '花子动漫', baseUrl: 'https://www.huazidm.com' },
  { name: '嘶哩嘶哩', baseUrl: 'https://www.silisilifun.com' },
  { name: 'XDM动漫', baseUrl: 'https://xuandm.com' },
  { name: '蜜桃动漫', baseUrl: 'https://www.mitaodm.com' },
  { name: '怡萱动漫', baseUrl: 'https://www.iyxdm.cn' },
  { name: '小小漫迷', baseUrl: 'https://www.xxmanmi.com' },
  { name: 'akianime', baseUrl: 'https://www.akianime.cc' },
  { name: '番薯动漫', baseUrl: 'https://www.fsdm02.com' },
  { name: 'myself动漫', baseUrl: 'https://myself-bbs.com' },
  { name: 'girlgirl爱动漫', baseUrl: 'https://bgm.girigirilove.com' },
  { name: '囧次元', baseUrl: 'https://www.jcydm1.com' },
  { name: '4K动漫', baseUrl: 'https://cn.agekkkk.com' },
  { name: '动漫巴士', baseUrl: 'https://dm84.tv' },
  { name: '奇米奇米', baseUrl: 'https://www.qimiqimi.net' },
  { name: 'clicli', baseUrl: 'https://www.clicli.cc' },
  { name: '哈哩哈哩', baseUrl: 'https://halihali1.com' },
  { name: '动漫看看', baseUrl: 'https://www.dongmankk.com' },
  { name: '樱花动漫备用', baseUrl: 'https://yinghuacd.com' },
  { name: '路漫漫', baseUrl: 'https://www.lmm52.com' },
  { name: '久久动漫', baseUrl: 'https://www.995dm.com' },
  { name: '次元方舟', baseUrl: 'https://cyfz.vip' },
  { name: '樱花动漫网', baseUrl: 'https://www.vdm8.com' },
  { name: '金阿尼动画', baseUrl: 'https://kimani22.com' },
  { name: 'AGE 备用', baseUrl: 'https://agefans.top' },
  { name: '修罗动漫', baseUrl: 'https://www.xiuluodm.com' },
  { name: '樱花动漫 74fan', baseUrl: 'https://74fan.com' },
  { name: '樱花动漫 qdtsdp', baseUrl: 'https://www.qdtsdp.com' },
  { name: '咚漫', baseUrl: 'https://www.dmps.cc' },
  { name: 'yhdm', baseUrl: 'https://www.yhdmp.cc' },
  { name: 'zyk', baseUrl: 'https://www.zykx8.com' },
  { name: 'sdmj', baseUrl: 'https://www.sdmjhq.com' },
  { name: 'D站', baseUrl: 'https://www.dilidili.wang' },
  { name: 'Zzzfun', baseUrl: 'https://www.zzzfun.com' },
  { name: 'Biminime', baseUrl: 'https://www.bimiacg10.com' },
  { name: 'AnFuns', baseUrl: 'https://www.anfuns102.net' },
  { name: 'girigirilove', baseUrl: 'https://www.girigirilove.com' },
  { name: 'omofun', baseUrl: 'https://www.omofun.com' },
];

async function handleSources(env) {
  let sources = await env.BANGUMI_AUTH_KV.get(SOURCES_KV_KEY, 'json');
  if (!sources || !Array.isArray(sources) || sources.length === 0) {
    sources = DEFAULT_SOURCES;
  }
  sources = sources.filter(isSafeSourceEntry);
  const healthRaw = await env.BANGUMI_AUTH_KV.get(HEALTH_KV_KEY, 'json');
  const health = healthRaw || {};
  const result = {
    version: sources.length,
    updatedAt: health._updatedAt || null,
    sources: sources.map((s) => ({
      ...s,
      available: health[s.baseUrl] === true,
    })),
  };
  return json(result);
}

function isSafeSourceEntry(source) {
  if (!source || typeof source !== 'object') return false;
  if (`${source.name || ''}`.trim().length === 0) return false;
  try {
    const url = new URL(`${source.baseUrl || ''}`);
    const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, '');
    if (url.protocol !== 'https:' || !host) return false;
    if (
      host === 'localhost' ||
      host.endsWith('.localhost') ||
      host.includes(':')
    ) {
      return false;
    }
    const match = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
    if (!match) return true;
    const octets = match.slice(1).map(Number);
    if (octets.some((value) => value < 0 || value > 255)) return false;
    return !(
      octets[0] === 0 ||
      octets[0] === 10 ||
      octets[0] === 127 ||
      (octets[0] === 169 && octets[1] === 254) ||
      (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
      (octets[0] === 192 && octets[1] === 168) ||
      octets[0] >= 224
    );
  } catch {
    return false;
  }
}

async function handleScheduled(env) {
  let sources = await env.BANGUMI_AUTH_KV.get(SOURCES_KV_KEY, 'json');
  if (!sources || !Array.isArray(sources) || sources.length === 0) {
    sources = DEFAULT_SOURCES;
    await env.BANGUMI_AUTH_KV.put(SOURCES_KV_KEY, JSON.stringify(sources));
  }
  sources = sources.filter(isSafeSourceEntry);

  const healthRaw = await env.BANGUMI_AUTH_KV.get(HEALTH_KV_KEY, 'json');
  const health = healthRaw || {};
  const fails = health._fails || {};

  for (const src of sources) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), SOURCE_PROBE_TIMEOUT_MS);
      const resp = await fetch(src.baseUrl, {
        method: 'HEAD',
        signal: controller.signal,
        headers: { 'User-Agent': RESOURCE_PROXY_USER_AGENT },
      });
      clearTimeout(timer);
      if (resp.ok || resp.status < 500) {
        health[src.baseUrl] = true;
        fails[src.baseUrl] = 0;
      } else {
        fails[src.baseUrl] = (fails[src.baseUrl] || 0) + 1;
        if (fails[src.baseUrl] >= SOURCE_DEAD_THRESHOLD) {
          health[src.baseUrl] = false;
        }
      }
    } catch {
      fails[src.baseUrl] = (fails[src.baseUrl] || 0) + 1;
      if (fails[src.baseUrl] >= SOURCE_DEAD_THRESHOLD) {
        health[src.baseUrl] = false;
      }
    }
  }

  health._updatedAt = new Date().toISOString();
  health._fails = fails;
  await env.BANGUMI_AUTH_KV.put(HEALTH_KV_KEY, JSON.stringify(health));
  console.log(`[scheduled] Probed ${sources.length} sources, updated health map.`);
}

// ── Main export ──────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    try {
      if (request.method === 'OPTIONS') {
        return new Response(null, {
          status: 204,
          headers: applyCors(
            new Headers(),
            request,
            'GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS',
          ),
        });
      }

      const url = new URL(request.url);
      if (url.pathname.startsWith('/dandanplay/')) {
        return await handleDandanplay(request, env);
      }
      if (request.method === 'GET' && url.pathname === '/health') {
        return json({ ok: true });
      }
      if (request.method === 'GET' && url.pathname === '/app_update.json') {
        return json(APP_UPDATE_MANIFEST);
      }
      if (request.method === 'GET' && url.pathname === '/sources.json') {
        return await handleSources(env);
      }
      if (url.pathname === '/bangumi/image') {
        return await handleBangumiImageProxy(request);
      }
      const bangumiProxyPrefix = findBangumiProxyPrefix(url.pathname);
      if (bangumiProxyPrefix) {
        const limited = await enforceRateLimit(
          request,
          env,
          'bangumi-proxy',
          RATE_LIMITS.bangumiProxy,
        );
        if (limited) return limited;
        return await handleBangumiProxy(request, bangumiProxyPrefix);
      }
      if (
        (request.method === 'GET' || request.method === 'HEAD') &&
        url.pathname.startsWith('/download/apk/')
      ) {
        return await handleApkDownload(request);
      }
      if (request.method === 'GET' && url.pathname === '/proxy/rss') {
        return await handleResourceProxy(request, 'rss');
      }
      if (request.method === 'GET' && url.pathname === '/proxy/torrent') {
        return await handleResourceProxy(request, 'torrent');
      }
      if (
        request.method === 'GET' &&
        url.pathname === '/auth/bangumi/mobile/start'
      ) {
        const limited = await enforceRateLimit(
          request,
          env,
          'auth-start',
          RATE_LIMITS.authStart,
        );
        if (limited) return limited;
        return await mobileAuth(request, env);
      }
      if (
        request.method === 'GET' &&
        url.pathname === '/auth/bangumi/callback'
      ) {
        return await mobileAuth(request, env);
      }
      if (
        request.method === 'POST' &&
        url.pathname === '/auth/bangumi/mobile/session'
      ) {
        const limited = await enforceRateLimit(
          request,
          env,
          'auth-session',
          RATE_LIMITS.authSession,
        );
        if (limited) return limited;
        return await mobileAuth(request, env);
      }
      if (
        request.method === 'POST' &&
        url.pathname === '/auth/bangumi/mobile/refresh'
      ) {
        if (await usesNewSession(request)) return await mobileAuth(request, env);
        return await handleRefresh(request, env);
      }
      if (
        request.method === 'POST' &&
        url.pathname === '/auth/bangumi/mobile/logout'
      ) {
        if (await usesNewSession(request)) return await mobileAuth(request, env);
        return await handleLogout(request, env);
      }
      return json({ error: 'Not found.' }, 404);
    } catch (error) {
      if (!(error instanceof RequestValidationError)) {
        console.error(error);
      }
      return json(
        {
          error:
            error instanceof Error ? error.message : 'Unknown gateway error.',
        },
        error instanceof RequestValidationError ? 400 : 500,
      );
    }
  },
  async scheduled(event, env) {
    await handleScheduled(env);
  },
};

export { isSafeSourceEntry };
