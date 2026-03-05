# WonderPic Admin Panel (React) + API Documentation

هذا الدليل يشرح:
- API الحالي الفعلي لتطبيق WonderPic.
- طريقة بناء Admin Panel احترافي بـ React بشكل آمن.
- كيف تتحكم بالمستخدمين والكريديت وتتابع حالة النظام.

## 1) Base URL

استخدم هذا الـ base:

```txt
https://pamlemagzhikexxmaxfz.supabase.co/functions/v1
```

## 2) Authentication & Security Model

### User-level endpoints
تحتاج:
- `Authorization: Bearer <FIREBASE_ID_TOKEN>`
- `apikey: <SUPABASE_PUBLISHABLE_KEY>`

### Admin actions
`account-status` (admin actions) يحتاج أيضًا:
- `x-admin-token: <APP_ADMIN_TOKEN>`

مهم جدًا:
- لا تضع `APP_ADMIN_TOKEN` داخل React frontend.
- استخدم Backend-for-Frontend (BFF) بسيط (Node/Express أو Next API routes) ليحقن `x-admin-token` من السيرفر فقط.

## 3) API Endpoints (Current)

### 3.1 `POST /account-session`
Sync حساب Firebase مع قاعدة البيانات + إرجاع حالة الحساب.

Request body:
```json
{}
```

Success response (200):
```json
{
  "ok": true,
  "identity": {
    "uid": "firebase_uid",
    "email": "user@email.com",
    "name": "User Name"
  },
  "account": {
    "account_id": "uuid",
    "firebase_uid": "firebase_uid",
    "status": "active",
    "email": "user@email.com",
    "display_name": "User Name",
    "posted_balance": 0,
    "reserved_balance": 0,
    "available_balance": 0,
    "updated_at": "...",
    "free_trial_total": 15,
    "free_trial_remaining": 15
  }
}
```

---

### 3.2 `POST /account-status`
Endpoint متعدد الأفعال.

#### `action = get` (افتراضي)
يرجع حالة الحساب الحالي + free trial.

Request body:
```json
{ "action": "get" }
```

#### `action = delete_me`
يحوّل الحساب الحالي إلى `deleted`.

Request body:
```json
{ "action": "delete_me", "reason": "optional" }
```

#### `action = admin_set_status` (Admin)
تغيير حالة أي مستخدم (`active | suspended | deleted`).

Headers إضافية:
- `x-admin-token`

Request body:
```json
{
  "action": "admin_set_status",
  "targetFirebaseUid": "target_uid",
  "targetStatus": "suspended",
  "reason": "fraud_check"
}
```

#### `action = admin_grant_credits` (Admin)
منح كريديت لمستخدم.

Headers إضافية:
- `x-admin-token`

Request body:
```json
{
  "action": "admin_grant_credits",
  "targetFirebaseUid": "target_uid",
  "grantAmount": 100,
  "idempotencyKey": "grant-2026-03-04-target_uid-001",
  "reason": "manual_adjustment",
  "metadata": { "ticket": "SUP-122" }
}
```

---

### 3.3 `POST /credits-reserve`
يحجز رصيد قبل التنفيذ (idempotent).

Request body:
```json
{
  "amount": 1,
  "idempotencyKey": "op_123_reserve",
  "operationKey": "op_123",
  "reason": "ai_generate",
  "ttlSeconds": 900,
  "metadata": { "model": "nano" }
}
```

Errors:
- `402` -> `INSUFFICIENT_CREDITS`
- `403` -> account not active/deleted
- `400` -> invalid payload

---

### 3.4 `POST /credits-commit`
تثبيت الخصم بعد نجاح العملية.

Request body:
```json
{
  "holdId": "uuid",
  "idempotencyKey": "op_123_commit",
  "reason": "ai_generate",
  "metadata": { "phase": "commit" }
}
```

---

### 3.5 `POST /credits-refund`
استرجاع رصيد hold ملتزم سابقًا.

Request body:
```json
{
  "holdId": "uuid",
  "idempotencyKey": "op_123_refund",
  "reason": "rollback",
  "metadata": { "phase": "refund" }
}
```

---

### 3.6 `POST /free-trial-consume`
يخصم 1 من free trial على السيرفر (مرتبط بالحساب، ليس local).

Request body:
```json
{
  "operationType": "ai_generate",
  "idempotencyKey": "op_123_trial",
  "metadata": { "source": "editor" }
}
```

Success response (200):
```json
{
  "ok": true,
  "result": {
    "account_id": "uuid",
    "account_status": "active",
    "free_trial_total": 15,
    "free_trial_remaining": 14,
    "available_balance": 0,
    "consumed": true
  }
}
```

Errors:
- `402` -> `FREE_TRIAL_EXHAUSTED`
- `403` -> account not active
- `400` -> missing idempotency

---

### 3.7 `GET|POST /kie-proxy?path=/api/...`
Proxy لـ KIE مع حقن `KIE_API_KEY` من أسرار Edge Function.

Rules:
- `path` لازم يبدأ بـ `/api/`.
- المسارات التي تبدأ `/api/file-` تُحوّل تلقائيًا لـ upload base.

---

### 3.8 `GET|POST /elevenlabs-proxy?path=/v1/...`
Proxy لـ ElevenLabs مع حقن `ELEVENLABS_API_KEY` من أسرار Edge Function.

Rules:
- `path` لازم يبدأ بـ `/v1/`.

---

### 3.9 `GET|POST /elements-catalog`
Catalog خاص بقسم `Elements` في التطبيق.

#### `GET` (public read)
يجلب الأقسام + العناصر (حسب القسم اختياريًا).

Query params:
- `category` (اختياري): slug القسم
- `limit` (اختياري): افتراضي 120
- `offset` (اختياري): افتراضي 0

Example:
```bash
curl 'https://pamlemagzhikexxmaxfz.supabase.co/functions/v1/elements-catalog?category=basic-shapes&limit=120'
```

Response:
```json
{
  "ok": true,
  "categories": [
    { "slug": "basic-shapes", "name": "Basic", "sort_order": 10 }
  ],
  "assets": [
    {
      "id": "uuid",
      "category_slug": "basic-shapes",
      "title": "Rounded square",
      "file_url": "https://.../storage/v1/object/public/elements/basic-shapes/....png",
      "mime_type": "image/png",
      "width": 1024,
      "height": 1024,
      "sort_order": 0
    }
  ]
}
```

#### `POST` admin actions (requires `x-admin-token`)
Headers:
- `x-admin-token: APP_ADMIN_TOKEN`

Actions:

1) `upload`
```json
{
  "action": "upload",
  "categorySlug": "basic-shapes",
  "title": "Rounded square",
  "fileName": "rounded-square.png",
  "mimeType": "image/png",
  "fileBase64": "data:image/png;base64,....",
  "sortOrder": 0
}
```

2) `delete`
```json
{
  "action": "delete",
  "assetId": "uuid"
}
```

3) `upsert_category`
```json
{
  "action": "upsert_category",
  "categorySlug": "stickers",
  "name": "Stickers",
  "sortOrder": 70,
  "isActive": true
}
```

## 4) Error Envelope (موحّد)

غالبًا الأخطاء تكون بهذا الشكل:

```json
{
  "ok": false,
  "error": "ERROR_CODE_OR_MESSAGE",
  "code": "optional_db_code"
}
```

## 5) React Admin Panel Architecture (Professional)

### Recommended stack
- React + TypeScript (Vite)
- React Router
- TanStack Query
- Axios
- Zod (schema validation)
- Zustand (lightweight UI state)
- Recharts (dashboard charts)
- Tailwind CSS + shadcn/ui (أو MUI)

### Bootstrap
```bash
npm create vite@latest wonderpic-admin -- --template react-ts
cd wonderpic-admin
npm i axios @tanstack/react-query react-router-dom zod zustand recharts
npm i -D tailwindcss postcss autoprefixer
```

### Suggested folder structure
```txt
src/
  app/
    router.tsx
    providers.tsx
  modules/
    dashboard/
    users/
    credits/
    settings/
    audit/
  services/
    api-client.ts
    admin-api.ts
    schemas.ts
  components/
  pages/
```

## 6) BFF Layer (مهم للأمان)

لا تنادِ `admin_*` actions مباشرة من React.

ابنِ BFF endpoints مثل:
- `POST /api/admin/users/status`
- `POST /api/admin/users/grant-credits`

الـ BFF يقوم بـ:
1. التحقق من جلسة admin.
2. قراءة `APP_ADMIN_TOKEN` من env السيرفر.
3. مناداة `/functions/v1/account-status` مع `x-admin-token`.

## 7) Admin Features Map

### Users module
- Suspend/Activate/Delete by Firebase UID (`admin_set_status`).
- عرض آخر حالة حساب + available balance + free trial.

### Credits module
- Grant credits (`admin_grant_credits`).
- سجل عمليات grant/reserve/commit/refund (يفضل endpoint إضافي للـ ledger list لاحقًا).

### App health module
- مراقبة أخطاء 4xx/5xx من الـ functions.
- latency per endpoint.
- rate of `INSUFFICIENT_CREDITS` و `FREE_TRIAL_EXHAUSTED`.

## 8) Production checklist

- `APP_ADMIN_TOKEN` قوي وطويل ويتم تدويره دوريًا.
- تفعيل RBAC داخلي للـ admin roles.
- Audit logging لكل admin action.
- rate limiting على BFF.
- لا يتم كشف `service_role` ولا `APP_ADMIN_TOKEN` في المتصفح.

---

## 9) Quick cURL examples

### Get current account status
```bash
curl -X POST 'https://pamlemagzhikexxmaxfz.supabase.co/functions/v1/account-status' \
  -H 'Authorization: Bearer FIREBASE_ID_TOKEN' \
  -H 'apikey: SUPABASE_PUBLISHABLE_KEY' \
  -H 'Content-Type: application/json' \
  -d '{"action":"get"}'
```

### Admin grant credits
```bash
curl -X POST 'https://pamlemagzhikexxmaxfz.supabase.co/functions/v1/account-status' \
  -H 'Authorization: Bearer FIREBASE_ID_TOKEN' \
  -H 'apikey: SUPABASE_PUBLISHABLE_KEY' \
  -H 'x-admin-token: APP_ADMIN_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"action":"admin_grant_credits","targetFirebaseUid":"UID","grantAmount":50,"idempotencyKey":"grant-uid-001"}'
```

### Consume free trial
```bash
curl -X POST 'https://pamlemagzhikexxmaxfz.supabase.co/functions/v1/free-trial-consume' \
  -H 'Authorization: Bearer FIREBASE_ID_TOKEN' \
  -H 'apikey: SUPABASE_PUBLISHABLE_KEY' \
  -H 'Content-Type: application/json' \
  -d '{"operationType":"ai_generate","idempotencyKey":"op_123_trial"}'
```
