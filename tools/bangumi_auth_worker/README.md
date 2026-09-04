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
