# Beer Tracker — Backend

Node.js 20 + Express + Supabase. Verifies Sign in with Apple identity tokens
and issues backend session JWTs that the iOS app sends as `Authorization:
Bearer <token>`.

## Quickstart

```bash
cd backend
cp .env.example .env
# fill in SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, APPLE_BUNDLE_ID, SESSION_JWT_SECRET
npm install
npm run dev
```

Health check: `curl http://localhost:3000/health`

## Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/auth/apple` | — | Body `{ identityToken }`. Returns `{ token, user, profileComplete }` |
| GET | `/users/me` | ✅ | Current user |
| PUT | `/users/me` | ✅ | multipart `nickname`, `profilePicture` |
| GET | `/users` | ✅ | Leaderboard |
| GET | `/users/:id/stats` | ✅ | Per-user stats |
| POST | `/beers` | ✅ | multipart `photo` (req), `latitude`, `longitude`, `locationName`, `note` |
| GET | `/beers` | ✅ | Paginated `?limit=20&offset=0` |
| GET | `/beers/total` | ✅ | `{ total, goal }` |
| GET | `/beers/map` | ✅ | Beers with coords |
| GET | `/beers/stats` | ✅ | Aggregate chart data |

## Coordinate blurring

`utils/geo.js` rounds lat/lon to 3 decimals (~100 m) before persistence.

## Deploying

- Railway / Fly.io / a tiny VPS will all work fine. Set the env vars from
  `.env.example`.
- The backend uses the Supabase **service role** key, so it must never run in
  the iOS app or in any environment a user can read.
