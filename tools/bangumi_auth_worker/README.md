# Bangumi Auth Worker

Cloudflare Workers + KV version of the AnimeMaster Bangumi OAuth gateway.

Required endpoints:

- `GET /health`
- `GET /auth/bangumi/mobile/start?callback_scheme=animemasteroauth`
- `GET /auth/bangumi/callback`
- `GET /auth/bangumi/mobile/session?session_id=...`
- `POST /auth/bangumi/mobile/refresh`
- `POST /auth/bangumi/mobile/logout`

Required secrets:

- `BANGUMI_CLIENT_ID`
- `BANGUMI_CLIENT_SECRET`
- `BANGUMI_CALLBACK_URL`

The callback URL must match the URL registered in the Bangumi developer console.

Only the fixed `animemasteroauth://callback` application callback is accepted.
Authorization-start, session-exchange, and Bangumi proxy routes are rate-limited
through the same KV namespace. Remote media-source entries are limited to public
HTTPS endpoints; localhost, private IPv4 ranges, and IPv6 literals are rejected.

Run `node --test *.test.mjs` before deployment. Deployments must keep the KV
binding and all three OAuth secrets configured; secrets must never be committed.

## Dandanplay gateway

Configure `DANDANPLAY_APP_ID` and `DANDANPLAY_APP_SECRET` as Worker secrets.
The `DANDANPLAY_GATEWAY` SQLite Durable Object binding and migration in
`wrangler.toml` are required. Keep the existing KV, OAuth secrets, routes and cron.
`GET /dandanplay/capabilities` reports send availability and shared quota.
The `/dandanplay/api/v2/` prefix exposes only explicitly allowed search, match,
Bangumi mapping/details, discovery, comment-read and app-comment-send routes.
It is not an arbitrary proxy and does not accept user tokens or application keys.

The shared object reserves quotas atomically before upstream requests (including
failed attempts), deduplicates cache misses, and limits each client IP to 90
requests/minute. Send requests require random `X-Request-Id` and
`X-Installation-Id`; identical retries return the recorded result. Unknown send
results remain reserved to avoid duplicate writes. Cache entries are bounded to
256 records of at most approximately 96 KiB each. Larger JSON responses are gzip
compressed when possible; responses still exceeding the record limit are forwarded
without server caching. Application credentials are stripped from allowlisted CDN
redirects. Account login, favorites and history are not exposed without upstream
permission. Anonymous installation identifiers are not an authentication boundary;
global quotas remain the protection against exhausting the upstream allowance.
