# Supabase Edge Functions (Phase 1)

This folder contains the WonderPic backend foundation for:
- Firebase Auth identity verification (ID token)
- Credits ledger reserve/commit/refund
- Account lifecycle status (active/suspended/deleted)

## Functions

- `account-session`
  - Verifies Firebase ID token.
  - Upserts account profile in DB.
  - Returns account + balances.

- `account-status`
  - User mode:
    - `get` (default)
    - `delete_me`
  - Admin mode (requires `x-admin-token`):
    - `admin_set_status`
    - `admin_grant_credits`

- `credits-reserve`
  - Reserves credits using idempotency.

- `credits-commit`
  - Commits a reserved hold (deduct credits).

- `credits-refund`
  - Refunds a committed hold.

- `kie-proxy`
  - Pass-through proxy for KIE endpoints.
  - Injects `KIE_API_KEY` from function secrets.

- `elevenlabs-proxy`
  - Pass-through proxy for ElevenLabs endpoints.
  - Injects `ELEVENLABS_API_KEY` from function secrets.

- `elements-catalog`
  - `GET` public listing for editor Elements tabs.
  - `POST` admin actions (requires `x-admin-token`):
    - `upload` element file (PNG/JPG/WebP) into storage bucket `elements`
    - `delete` by asset id
    - `upsert_category`

- `fonts-catalog`
  - `GET` public listing for editor Text fonts tabs.
  - `POST` admin actions (requires `x-admin-token`):
    - `upload` font file (TTF/OTF/TTC) into storage bucket `text-fonts`
    - `delete` by font id
    - `upsert_font`
    - `list_admin`

- `templates-catalog`
  - `GET` public listing for editor Templates tab.
  - `POST` admin actions (requires `x-admin-token`):
    - `upload` template file (SVG) into storage bucket `templates`
    - `delete` by template id
    - `upsert_template`

## Required secrets

Set these in Supabase project secrets:

```bash
supabase secrets set \
  SUPABASE_URL="https://YOUR_PROJECT_REF.supabase.co" \
  SUPABASE_SERVICE_ROLE_KEY="sb_secret_xxx" \
  FIREBASE_PROJECT_ID="your-firebase-project-id" \
  APP_ADMIN_TOKEN="replace-with-long-random-token"
```

For provider proxies:

```bash
supabase secrets set \
  KIE_API_KEY="..." \
  ELEVENLABS_API_KEY="..."
```

## Deploy

```bash
supabase functions deploy account-session
supabase functions deploy account-status
supabase functions deploy credits-reserve
supabase functions deploy credits-commit
supabase functions deploy credits-refund
supabase functions deploy elements-catalog
supabase functions deploy fonts-catalog
supabase functions deploy templates-catalog
```

## Invoke examples

User session sync:

```bash
curl -X POST "https://YOUR_PROJECT_REF.supabase.co/functions/v1/account-session" \
  -H "Authorization: Bearer FIREBASE_ID_TOKEN" \
  -H "apikey: sb_publishable_xxx" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Reserve credits:

```bash
curl -X POST "https://YOUR_PROJECT_REF.supabase.co/functions/v1/credits-reserve" \
  -H "Authorization: Bearer FIREBASE_ID_TOKEN" \
  -H "apikey: sb_publishable_xxx" \
  -H "Content-Type: application/json" \
  -d '{"amount":3.5,"idempotencyKey":"reserve-job-123","operationKey":"job-123"}'
```
