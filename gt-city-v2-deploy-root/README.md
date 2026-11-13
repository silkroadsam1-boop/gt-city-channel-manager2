# GT City Channel Manager v2 — Deployable foundation

## Render
- Root Directory: leave blank when these files are uploaded to repository root.
- Build Command: `npm install`
- Start Command: `npm start`
- Add `DATABASE_URL` from a separate Render PostgreSQL database before using database endpoints.

## Health check
`GET /api/health`

## Important
This is the initial deployable API foundation, not a finished PMS or live OTA integration. Apply `db/migrations/001_core_schema.sql` to a new PostgreSQL database only after provisioning it. It does not read or require the old `data.json`. Keep the existing production service untouched until the new service has been tested.
