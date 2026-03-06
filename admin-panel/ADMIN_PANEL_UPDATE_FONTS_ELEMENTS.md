# Admin Panel Update: Fonts + Elements Catalog

Date: March 6, 2026
Project: WonderPic
Target: React Admin Panel Team

## 1) Objective
Implement full Admin Panel support for:
- Global Text Fonts catalog (database + storage-backed).
- Elements catalog upload/management (already available in backend, needs full page integration consistency).

The goal is that any font/element uploaded from Admin Panel appears in the app catalog automatically.

## 2) Backend Status (Ready)
The backend APIs and database are already prepared:
- `GET|POST /functions/v1/fonts-catalog`
- `GET|POST /functions/v1/elements-catalog`

Main API reference:
- `admin-panel/admin panel API.md` (updated)

## 3) Required Admin Panel Changes

## 3.1 Fonts Management Page (New/Updated)
Create or update a dedicated "Fonts" page in admin panel.

Required features:
- Show fonts list with fields:
  - `label`, `family`, `locale`, `preview`, `sort_order`, `is_active`, `created_at`.
- Locale filter: `english` / `arabic`.
- Search by `label` or `family`.
- Upload new font file (`ttf`, `otf`, `ttc`).
- Edit existing font metadata.
- Activate/Deactivate font.
- Delete font.

Upload form fields:
- `locale` (required)
- `label` (required)
- `family` (optional; backend can normalize/generate)
- `preview` (optional)
- `sortOrder` (optional, default `0`)
- `file` (required: ttf/otf/ttc)

## 3.2 Elements Management Page (Confirm/Adjust)
Ensure Elements page behavior is aligned with backend:
- Category selector from `elements_categories` logic.
- Upload image file (`png`, `jpg`, `jpeg`, `webp`) with category.
- Optional title and sort order.
- Delete element asset.
- Upsert category (`slug`, `name`, `sortOrder`, `isActive`).

## 4) API Contract for Admin Panel
Base URL:
- `https://pamlemagzhikexxmaxfz.supabase.co/functions/v1`

Admin header (required for all POST admin actions):
- `x-admin-token: APP_ADMIN_TOKEN`

Important security rule:
- Do not expose `APP_ADMIN_TOKEN` in browser code.
- Use BFF/server route to inject admin token.

## 4.1 Fonts Catalog Endpoints

### GET `/fonts-catalog`
Public listing.

Query params:
- `locale` (optional): `english | arabic`
- `limit` (optional)
- `offset` (optional)
- `includeInactive=true` (admin only, requires valid admin token)

### POST `/fonts-catalog`
Admin actions:
- `action: "upload"`
- `action: "upsert_font"`
- `action: "delete"`
- `action: "list_admin"`

Action payload examples:

`upload`
```json
{
  "action": "upload",
  "locale": "english",
  "label": "My Font",
  "family": "My_Font",
  "preview": "Aa",
  "fileName": "my-font.ttf",
  "mimeType": "font/ttf",
  "fileBase64": "data:font/ttf;base64,...",
  "sortOrder": 0
}
```

`upsert_font`
```json
{
  "action": "upsert_font",
  "fontId": "uuid",
  "label": "My Font Updated",
  "family": "My_Font_Updated",
  "locale": "english",
  "preview": "Aa",
  "sortOrder": 10,
  "isActive": true
}
```

`delete`
```json
{
  "action": "delete",
  "fontId": "uuid"
}
```

`list_admin`
```json
{
  "action": "list_admin",
  "locale": "arabic"
}
```

## 4.2 Elements Catalog Endpoints

### GET `/elements-catalog`
Query params:
- `category` (optional)
- `limit` (optional)
- `offset` (optional)

### POST `/elements-catalog`
Admin actions:
- `action: "upload"`
- `action: "delete"`
- `action: "upsert_category"`

`upload`
```json
{
  "action": "upload",
  "categorySlug": "basic-shapes",
  "title": "Rounded square",
  "fileName": "rounded-square.png",
  "mimeType": "image/png",
  "fileBase64": "data:image/png;base64,...",
  "sortOrder": 0
}
```

`delete`
```json
{
  "action": "delete",
  "assetId": "uuid"
}
```

`upsert_category`
```json
{
  "action": "upsert_category",
  "categorySlug": "stickers",
  "name": "Stickers",
  "sortOrder": 70,
  "isActive": true
}
```

## 5) UI/UX Requirements
- Show loading states for list/upload/update/delete.
- Show clear success and error toasts.
- Disable submit button while request in-flight.
- Auto-refresh list after successful create/update/delete.
- Keep selected filter state after refresh.

## 6) Validation Rules (Client-side)
Fonts:
- Allowed extensions: `ttf`, `otf`, `ttc`.
- Max file size: up to 15 MB.
- `locale` required.
- `label` required.

Elements:
- Allowed mime types: `image/png`, `image/jpeg`, `image/jpg`, `image/webp`.
- Max file size: up to 10 MB.
- `categorySlug` required for upload.

## 7) Error Handling Contract
Error envelope:
```json
{
  "ok": false,
  "error": "ERROR_CODE_OR_MESSAGE"
}
```

Expected admin auth error:
- `403` with `ADMIN_AUTH_REQUIRED`.

## 8) Acceptance Criteria
- Uploading a font from Admin Panel adds it to `fonts-catalog` and it appears in app font list.
- Editing font metadata updates app-visible catalog behavior.
- Deactivating a font hides it from public app list.
- Uploading element assets from Admin Panel shows them in app elements list by category.
- Deleting font/element removes it from visible app catalog.
- No admin token leakage in browser network calls.

## 9) Implementation Note for React Team
Recommended API layer:
- `adminApi.fonts.listAdmin(locale?)`
- `adminApi.fonts.upload(payload)`
- `adminApi.fonts.upsertFont(payload)`
- `adminApi.fonts.delete(fontId)`
- `adminApi.elements.list(category?)`
- `adminApi.elements.upload(payload)`
- `adminApi.elements.upsertCategory(payload)`
- `adminApi.elements.delete(assetId)`

Please implement via BFF routes (server-side token injection).
