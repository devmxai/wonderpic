import { corsHeaders, jsonResponse } from '../_shared/cors.ts';
import { readBackendEnv } from '../_shared/env.ts';
import { createServiceClient } from '../_shared/supabase.ts';

type ElementCatalogPayload = {
  action?: string;
  categorySlug?: string;
  name?: string;
  sortOrder?: number;
  isActive?: boolean;
  fileBase64?: string;
  fileName?: string;
  title?: string;
  mimeType?: string;
  width?: number;
  height?: number;
  assetId?: string;
};

type ParsedImage = {
  bytes: Uint8Array;
  mimeType: 'image/png' | 'image/jpeg' | 'image/jpg' | 'image/webp';
  extension: 'png' | 'jpg' | 'webp';
};

function isAuthorizedAdmin(req: Request, adminToken: string): boolean {
  if (!adminToken) return false;
  const incoming = req.headers.get('x-admin-token')?.trim() ?? '';
  return incoming.length > 0 && incoming === adminToken;
}

function clampInt(value: string | null, fallback: number, min: number, max: number): number {
  const parsed = Number.parseInt((value ?? '').trim(), 10);
  if (Number.isNaN(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function normalizeSlug(raw: string | null | undefined): string {
  return (raw ?? '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function sanitizeTitle(raw: string | null | undefined): string | null {
  const normalized = (raw ?? '').trim();
  if (!normalized) return null;
  return normalized.length <= 80 ? normalized : normalized.slice(0, 80);
}

function decodeBase64ToBytes(base64Payload: string): Uint8Array {
  const binary = atob(base64Payload);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function parseImagePayload(
  fileBase64Raw: string | null | undefined,
  mimeTypeRaw: string | null | undefined,
): ParsedImage {
  const raw = (fileBase64Raw ?? '').trim();
  if (!raw) {
    throw new Error('FILE_BASE64_REQUIRED');
  }

  let mimeType = (mimeTypeRaw ?? '').trim().toLowerCase();
  let payload = raw;

  if (raw.startsWith('data:')) {
    const match = /^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/i.exec(raw);
    if (!match) {
      throw new Error('INVALID_DATA_URL');
    }
    mimeType = match[1].toLowerCase();
    payload = match[2];
  }

  if (!mimeType) {
    throw new Error('MIME_TYPE_REQUIRED');
  }

  const allowed = new Set(['image/png', 'image/jpeg', 'image/jpg', 'image/webp']);
  if (!allowed.has(mimeType)) {
    throw new Error('UNSUPPORTED_MIME_TYPE');
  }

  const bytes = decodeBase64ToBytes(payload);
  if (!bytes.length) {
    throw new Error('EMPTY_FILE');
  }
  if (bytes.length > 10 * 1024 * 1024) {
    throw new Error('FILE_TOO_LARGE');
  }

  const extension: ParsedImage['extension'] =
    mimeType === 'image/png' ? 'png' : mimeType === 'image/webp' ? 'webp' : 'jpg';

  return {
    bytes,
    mimeType: mimeType as ParsedImage['mimeType'],
    extension,
  };
}

function publicAsset(row: Record<string, unknown>) {
  return {
    id: row.id,
    category_slug: row.category_slug,
    title: row.title,
    file_url: row.file_url,
    mime_type: row.mime_type,
    width: row.width,
    height: row.height,
    sort_order: row.sort_order,
    created_at: row.created_at,
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const env = readBackendEnv();
    const supabase = createServiceClient(env);

    if (req.method === 'GET') {
      const url = new URL(req.url);
      const categorySlug = normalizeSlug(url.searchParams.get('category'));
      const limit = clampInt(url.searchParams.get('limit'), 120, 1, 500);
      const offset = clampInt(url.searchParams.get('offset'), 0, 0, 10000);

      const { data: categoriesData, error: categoriesError } = await supabase
        .from('elements_categories')
        .select('slug,name,sort_order')
        .eq('is_active', true)
        .order('sort_order', { ascending: true })
        .order('name', { ascending: true });

      if (categoriesError) {
        return jsonResponse(500, { ok: false, error: categoriesError.message });
      }

      let assetsQuery = supabase
        .from('elements_assets')
        .select('id,category_slug,title,file_url,mime_type,width,height,sort_order,created_at')
        .eq('is_active', true)
        .order('sort_order', { ascending: true })
        .order('created_at', { ascending: false });

      if (categorySlug) {
        assetsQuery = assetsQuery.eq('category_slug', categorySlug);
      }

      const { data: assetsData, error: assetsError } = await assetsQuery.range(
        offset,
        offset + limit - 1,
      );

      if (assetsError) {
        return jsonResponse(500, { ok: false, error: assetsError.message });
      }

      const categories = (categoriesData ?? []).map((row) => ({
        slug: row.slug,
        name: row.name,
        sort_order: row.sort_order,
      }));
      const assets = (assetsData ?? []).map((row) => publicAsset(row));

      return jsonResponse(200, {
        ok: true,
        categories,
        assets,
        paging: {
          limit,
          offset,
          category: categorySlug || null,
        },
      });
    }

    if (req.method !== 'POST') {
      return jsonResponse(405, { ok: false, error: 'Method not allowed' });
    }

    if (!isAuthorizedAdmin(req, env.adminToken)) {
      return jsonResponse(403, { ok: false, error: 'ADMIN_AUTH_REQUIRED' });
    }

    const payload = (await req.json().catch(() => ({}))) as ElementCatalogPayload;
    const action = (payload.action ?? 'upload').trim().toLowerCase();

    if (action === 'upsert_category') {
      const slug = normalizeSlug(payload.categorySlug);
      const name = (payload.name ?? '').trim();
      if (!slug) {
        return jsonResponse(400, { ok: false, error: 'CATEGORY_SLUG_REQUIRED' });
      }
      if (!name) {
        return jsonResponse(400, { ok: false, error: 'CATEGORY_NAME_REQUIRED' });
      }

      const sortOrder = Number.isFinite(payload.sortOrder)
        ? Number(payload.sortOrder)
        : 0;
      const isActive = payload.isActive ?? true;

      const { data, error } = await supabase
        .from('elements_categories')
        .upsert(
          {
            slug,
            name,
            sort_order: sortOrder,
            is_active: isActive,
          },
          {
            onConflict: 'slug',
          },
        )
        .select('slug,name,sort_order,is_active')
        .single();

      if (error) {
        return jsonResponse(400, { ok: false, error: error.message });
      }

      return jsonResponse(200, {
        ok: true,
        result: data,
      });
    }

    if (action === 'delete') {
      const assetId = (payload.assetId ?? '').trim();
      if (!assetId) {
        return jsonResponse(400, { ok: false, error: 'ASSET_ID_REQUIRED' });
      }

      const { data: existing, error: existingError } = await supabase
        .from('elements_assets')
        .select('id,file_path')
        .eq('id', assetId)
        .maybeSingle();

      if (existingError) {
        return jsonResponse(400, { ok: false, error: existingError.message });
      }
      if (!existing) {
        return jsonResponse(404, { ok: false, error: 'ASSET_NOT_FOUND' });
      }

      const { error: deleteRowError } = await supabase
        .from('elements_assets')
        .delete()
        .eq('id', assetId);
      if (deleteRowError) {
        return jsonResponse(400, { ok: false, error: deleteRowError.message });
      }

      const filePath = (existing.file_path ?? '').toString().trim();
      if (filePath) {
        await supabase.storage.from('elements').remove([filePath]);
      }

      return jsonResponse(200, { ok: true });
    }

    if (action !== 'upload') {
      return jsonResponse(400, { ok: false, error: 'UNSUPPORTED_ACTION' });
    }

    const categorySlug = normalizeSlug(payload.categorySlug);
    if (!categorySlug) {
      return jsonResponse(400, { ok: false, error: 'CATEGORY_SLUG_REQUIRED' });
    }

    const { data: categoryRow, error: categoryError } = await supabase
      .from('elements_categories')
      .select('slug,name,is_active')
      .eq('slug', categorySlug)
      .maybeSingle();

    if (categoryError) {
      return jsonResponse(400, { ok: false, error: categoryError.message });
    }
    if (!categoryRow || categoryRow.is_active !== true) {
      return jsonResponse(400, { ok: false, error: 'CATEGORY_NOT_AVAILABLE' });
    }

    let parsed: ParsedImage;
    try {
      parsed = parseImagePayload(payload.fileBase64, payload.mimeType);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'INVALID_FILE';
      return jsonResponse(400, { ok: false, error: message });
    }

    const now = new Date();
    const year = now.getUTCFullYear().toString();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    const randomPart = crypto.randomUUID().replaceAll('-', '').slice(0, 10);
    const filePath = `${categorySlug}/${year}/${month}/${Date.now()}_${randomPart}.${parsed.extension}`;

    const { error: uploadError } = await supabase.storage.from('elements').upload(
      filePath,
      parsed.bytes,
      {
        contentType: parsed.mimeType,
        upsert: false,
        cacheControl: '3600',
      },
    );

    if (uploadError) {
      return jsonResponse(400, { ok: false, error: uploadError.message });
    }

    const { data: publicUrlData } = supabase.storage.from('elements').getPublicUrl(filePath);
    const fileUrl = publicUrlData.publicUrl?.trim() ?? '';
    if (!fileUrl) {
      await supabase.storage.from('elements').remove([filePath]);
      return jsonResponse(500, { ok: false, error: 'PUBLIC_URL_RESOLUTION_FAILED' });
    }

    const inferredTitle = sanitizeTitle(payload.title) ??
      sanitizeTitle(payload.fileName) ??
      null;
    const sortOrder = Number.isFinite(payload.sortOrder) ? Number(payload.sortOrder) : 0;
    const width = Number.isFinite(payload.width) ? Number(payload.width) : null;
    const height = Number.isFinite(payload.height) ? Number(payload.height) : null;

    const { data: insertRow, error: insertError } = await supabase
      .from('elements_assets')
      .insert({
        category_slug: categorySlug,
        title: inferredTitle,
        file_path: filePath,
        file_url: fileUrl,
        mime_type: parsed.mimeType,
        width,
        height,
        sort_order: sortOrder,
        is_active: true,
      })
      .select('id,category_slug,title,file_url,mime_type,width,height,sort_order,created_at')
      .single();

    if (insertError) {
      await supabase.storage.from('elements').remove([filePath]);
      return jsonResponse(400, { ok: false, error: insertError.message });
    }

    return jsonResponse(200, {
      ok: true,
      result: publicAsset(insertRow),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected error';
    return jsonResponse(400, { ok: false, error: message });
  }
});
