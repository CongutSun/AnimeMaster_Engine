# Bangumi Auth Worker

Cloudflare Workers, SQLite Durable Objects and KV implementation of the AnimeMaster Bangumi OAuth gateway.

Required endpoints:

- `GET /health`
- `GET /auth/bangumi/mobile/start?callback_scheme=animemasteroauth&code_challenge_method=S256&code_challenge=...`
- `GET /auth/bangumi/callback`
- `POST /auth/bangumi/mobile/session`
- `POST /auth/bangumi/mobile/refresh`
- `POST /auth/bangumi/mobile/logout`

Required secrets:

- `BANGUMI_CLIENT_ID`
- `BANGUMI_CLIENT_SECRET`
- `BANGUMI_CALLBACK_URL`

The callback URL must match the URL registered in the Bangumi developer console.

The client keeps a random verifier for each login. The start challenge is its
base64url-encoded SHA-256 digest without padding. The exchange POST sends
`session_id` and `code_verifier` in a JSON body. Pending authorizations and
exchange grants expire after ten minutes. SQLite rotates a valid grant into a
session atomically. A new login requires a client supporting this protocol.

Only the fixed `animemasteroauth://callback` application callback is accepted.
Authorization-start, session-exchange, and Bangumi proxy routes are rate-limited
through the same KV namespace. Remote media-source entries are limited to public
HTTPS endpoints; localhost, private IPv4 ranges, and IPv6 literals are rejected.

Deploy the `BANGUMI_MOBILE_AUTH` SQLite Durable Object binding and migration
with the Worker. Existing KV sessions remain available for refresh and logout.
The standalone gateway requires Node.js 24 and stores sessions in
`data/sessions.sqlite`. On first startup it imports unexpired sessions from
`data/store.json` and retires the old file after committing the import.

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
