# Admin Panel Update: Templates (SVG Catalog)

Date: March 6, 2026
Project: WonderPic
Target: React Admin Panel Team

## 1) Objective
Add a new **Templates** section in Admin Panel to upload and manage SVG templates.

Goal:
- Admin uploads SVG template files.
- Templates appear in app Templates bottom sheet.
- When user opens template in app, it opens as a new project using the SVG native workspace size.

## 2) Backend Status (Ready)
Backend is already implemented and ready:
- `GET|POST /functions/v1/templates-catalog`
- Storage bucket: `templates`
- DB table: `public.templates_catalog`

Reference:
- `supabase/functions/templates-catalog/index.ts`
- `supabase/migrations/202603060002_templates_catalog_foundation.sql`

## 3) Required Admin Panel Changes
Create a dedicated page: **Templates**.

Required UI features:
- List templates in cards/grid.
- Show fields: `title`, `preview`, `width`, `height`, `sort_order`, `is_active`, `created_at`.
- Upload new SVG template.
- Edit metadata (`title`, `sortOrder`, `isActive`).
- Delete template.
- Manual refresh button.

## 4) API Contract for Admin Panel
Base URL:
- `https://pamlemagzhikexxmaxfz.supabase.co/functions/v1`

Admin header (required for admin actions):
- `x-admin-token: APP_ADMIN_TOKEN`

Security rule:
- Do not expose admin token in client browser.
- Use BFF/server route to inject token.

## 4.1 GET `/templates-catalog`
Public list endpoint.

Query params:
- `limit` (optional, default server-side)
- `offset` (optional)
- `includeInactive=true` (admin only, requires valid admin token)

Example:
```bash
curl 'https://pamlemagzhikexxmaxfz.supabase.co/functions/v1/templates-catalog?limit=240&offset=0'
```

Expected response:
```json
{
  "ok": true,
  "templates": [
    {
      "id": "uuid",
      "title": "Story Promo Pack",
      "file_url": "https://.../storage/v1/object/public/templates/templates/2026/03/..svg",
      "mime_type": "image/svg+xml",
      "width": 1080,
      "height": 1920,
      "sort_order": 10,
      "created_at": "2026-03-06T...Z"
    }
  ],
  "paging": {
    "limit": 240,
    "offset": 0,
    "include_inactive": false
  }
}
```

## 4.2 POST `/templates-catalog`
Admin actions:
- `action: "upload"`
- `action: "upsert_template"`
- `action: "delete"`

### Action: `upload`
```json
{
  "action": "upload",
  "title": "Story Promo Pack",
  "fileName": "story-promo.svg",
  "mimeType": "image/svg+xml",
  "fileBase64": "data:image/svg+xml;base64,...",
  "sortOrder": 10
}
```

Notes:
- File must be SVG.
- Backend extracts dimensions from `viewBox` or `width/height` when available.
- Optional `width` and `height` can be sent as hints.

### Action: `upsert_template`
```json
{
  "action": "upsert_template",
  "templateId": "uuid",
  "title": "Story Promo Pack v2",
  "sortOrder": 20,
  "isActive": true
}
```

### Action: `delete`
```json
{
  "action": "delete",
  "templateId": "uuid"
}
```

## 5) Frontend Validation Rules
- Allowed extension: `.svg` only.
- Allowed MIME: `image/svg+xml`.
- Max size: `15 MB`.
- `title` required on upload.
- Reject empty/invalid SVG immediately in UI.

## 6) UX Requirements
- Show loading states for list/upload/update/delete.
- Disable action buttons while request in-flight.
- Show success/error toast for every operation.
- Auto-refresh list after successful upload/edit/delete.
- Keep page filter/sort state after refresh.

## 7) Error Contract
Error envelope:
```json
{
  "ok": false,
  "error": "ERROR_CODE_OR_MESSAGE"
}
```

Common admin error:
- `403` + `ADMIN_AUTH_REQUIRED`

## 8) Important Template Quality Note
To keep layers editable in app:
- Upload **layered SVG** (groups/objects preserved).
- Do not flatten everything into one path before upload.

If source is EPS/AI:
- Convert to SVG before upload.
- Keep export settings that preserve layers/groups.

## 9) Acceptance Criteria
- Templates section exists in Admin Panel.
- SVG upload succeeds and appears in templates list.
- Edit (title/order/active) works.
- Delete removes template and storage object.
- Uploaded template appears in app Templates tab.
- Opening template in app creates a new project with correct SVG workspace dimensions.
- No admin token leakage in browser network calls.

## 10) Suggested React API Layer
- `adminApi.templates.list({ includeInactive?, limit?, offset? })`
- `adminApi.templates.upload(payload)`
- `adminApi.templates.upsertTemplate(payload)`
- `adminApi.templates.delete(templateId)`

Implementation must be through server-side/BFF routes.
