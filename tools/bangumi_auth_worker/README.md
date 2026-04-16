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
