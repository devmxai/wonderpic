import { corsHeaders, jsonResponse } from '../_shared/cors.ts';
import { readBackendEnv } from '../_shared/env.ts';
import { createServiceClient } from '../_shared/supabase.ts';

type TextFontsCatalogPayload = {
  action?: string;
  fontId?: string;
  family?: string;
  label?: string;
  locale?: string;
  preview?: string;
  sortOrder?: number;
  isActive?: boolean;
  fileBase64?: string;
  fileName?: string;
  mimeType?: string;
};

type ParsedFontFile = {
  bytes: Uint8Array;
  mimeType: string;
  extension: 'ttf' | 'otf' | 'ttc';
};

const FONT_BUCKET = 'text-fonts';
const FONT_MIME_TO_EXTENSION = new Map<string, ParsedFontFile['extension']>([
  ['font/ttf', 'ttf'],
  ['application/x-font-ttf', 'ttf'],
  ['font/otf', 'otf'],
  ['application/x-font-opentype', 'otf'],
  ['application/font-sfnt', 'otf'],
  ['font/collection', 'ttc'],
]);
const EXTENSION_TO_MIME = new Map<ParsedFontFile['extension'], string>([
  ['ttf', 'font/ttf'],
  ['otf', 'font/otf'],
  ['ttc', 'font/collection'],
]);

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

function normalizeLocale(raw: string | null | undefined): 'english' | 'arabic' | '' {
  const value = (raw ?? '').trim().toLowerCase();
  if (value === 'english' || value === 'en' || value === 'latin' || value === 'ltr') {
    return 'english';
  }
  if (value === 'arabic' || value === 'ar' || value === 'rtl') {
    return 'arabic';
  }
  return '';
}

function sanitizeLabel(raw: string | null | undefined): string {
  const value = (raw ?? '').trim().replace(/\s+/g, ' ');
  if (!value) return '';
  return value.length <= 80 ? value : value.slice(0, 80);
}

function sanitizePreview(raw: string | null | undefined, locale: 'english' | 'arabic'): string {
  const fallback = locale === 'arabic' ? 'أبجد' : 'Aa';
  const value = (raw ?? '').trim();
  if (!value) return fallback;
  return value.length <= 36 ? value : value.slice(0, 36);
}

function normalizeFamily(raw: string | null | undefined): string {
  const normalized = (raw ?? '')
    .trim()
    .replace(/[^a-zA-Z0-9]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (!normalized) return '';
  const safe = normalized.length <= 56 ? normalized : normalized.slice(0, 56);
  if (/^[0-9]/.test(safe)) {
    return `Font_${safe}`;
  }
  return safe;
}

function extensionFromFileName(fileName: string | null | undefined): ParsedFontFile['extension'] | null {
  const raw = (fileName ?? '').trim().toLowerCase();
  if (!raw || !raw.includes('.')) return null;
  const ext = raw.split('.').pop() ?? '';
  if (ext === 'ttf' || ext === 'otf' || ext === 'ttc') return ext;
  return null;
}

function decodeBase64ToBytes(base64Payload: string): Uint8Array {
  const binary = atob(base64Payload);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function parseFontPayload(
  fileBase64Raw: string | null | undefined,
  mimeTypeRaw: string | null | undefined,
  fileNameRaw: string | null | undefined,
): ParsedFontFile {
  const raw = (fileBase64Raw ?? '').trim();
  if (!raw) {
    throw new Error('FILE_BASE64_REQUIRED');
  }

  const fileExtension = extensionFromFileName(fileNameRaw);
  let mimeType = (mimeTypeRaw ?? '').trim().toLowerCase();
  let payload = raw;

  if (raw.startsWith('data:')) {
    const match = /^data:([^;]+);base64,(.+)$/i.exec(raw);
    if (!match) {
      throw new Error('INVALID_DATA_URL');
    }
    mimeType = match[1].trim().toLowerCase();
    payload = match[2];
  }

  let extension = FONT_MIME_TO_EXTENSION.get(mimeType);
  if (!extension && fileExtension) {
    extension = fileExtension;
    mimeType = EXTENSION_TO_MIME.get(fileExtension) ?? 'application/octet-stream';
  }
  if (!extension) {
    throw new Error('UNSUPPORTED_FONT_FORMAT');
  }

  const bytes = decodeBase64ToBytes(payload);
  if (!bytes.length) {
    throw new Error('EMPTY_FILE');
  }
  if (bytes.length > 15 * 1024 * 1024) {
    throw new Error('FILE_TOO_LARGE');
  }

  return {
    bytes,
    mimeType,
    extension,
  };
}

function publicFont(row: Record<string, unknown>, adminView = false) {
  return {
    id: row.id,
    family: row.family,
    label: row.label,
    locale: row.locale,
    preview: row.preview,
    file_url: row.file_url,
    mime_type: row.mime_type,
    sort_order: row.sort_order,
    created_at: row.created_at,
    ...(adminView
      ? {
          is_active: row.is_active,
          file_path: row.file_path,
          updated_at: row.updated_at,
        }
      : {}),
  };
}

async function resolveUniqueFamily(
  supabase: ReturnType<typeof createServiceClient>,
  baseFamily: string,
  ignoreId?: string,
): Promise<string> {
  let candidate = normalizeFamily(baseFamily);
  if (!candidate) {
    candidate = `Font_${Date.now().toString().slice(-8)}`;
  }
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const { data, error } = await supabase
      .from('text_fonts_catalog')
      .select('id')
      .eq('family', candidate)
      .maybeSingle();
    if (error) {
      throw new Error(error.message);
    }
    if (!data || (ignoreId && data.id === ignoreId)) {
      return candidate;
    }
    const suffix = crypto.randomUUID().replaceAll('-', '').slice(0, 6);
    const prefix = candidate.length > 48 ? candidate.slice(0, 48) : candidate;
    candidate = `${prefix}_${suffix}`;
  }
  return `${candidate}_${Date.now().toString().slice(-4)}`;
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
      const locale = normalizeLocale(url.searchParams.get('locale'));
      const limit = clampInt(url.searchParams.get('limit'), 200, 1, 1000);
      const offset = clampInt(url.searchParams.get('offset'), 0, 0, 20000);
      const includeInactiveRequested =
        (url.searchParams.get('includeInactive') ?? '').trim().toLowerCase() === 'true';
      const includeInactive = includeInactiveRequested && isAuthorizedAdmin(req, env.adminToken);

      let query = supabase
        .from('text_fonts_catalog')
        .select('id,family,label,locale,preview,file_url,file_path,mime_type,sort_order,is_active,created_at,updated_at')
        .order('sort_order', { ascending: true })
        .order('created_at', { ascending: false });

      if (locale) {
        query = query.eq('locale', locale);
      }
      if (!includeInactive) {
        query = query.eq('is_active', true);
      }

      const { data, error } = await query.range(offset, offset + limit - 1);
      if (error) {
        return jsonResponse(500, { ok: false, error: error.message });
      }

      return jsonResponse(200, {
        ok: true,
        fonts: (data ?? []).map((row) => publicFont(row, includeInactive)),
        paging: {
          limit,
          offset,
          locale: locale || null,
          include_inactive: includeInactive,
        },
      });
    }

    if (req.method !== 'POST') {
      return jsonResponse(405, { ok: false, error: 'Method not allowed' });
    }

    if (!isAuthorizedAdmin(req, env.adminToken)) {
      return jsonResponse(403, { ok: false, error: 'ADMIN_AUTH_REQUIRED' });
    }

    const payload = (await req.json().catch(() => ({}))) as TextFontsCatalogPayload;
    const action = (payload.action ?? 'upload').trim().toLowerCase();

    if (action === 'list_admin') {
      const locale = normalizeLocale(payload.locale);
      let query = supabase
        .from('text_fonts_catalog')
        .select('id,family,label,locale,preview,file_url,file_path,mime_type,sort_order,is_active,created_at,updated_at')
        .order('sort_order', { ascending: true })
        .order('created_at', { ascending: false });
      if (locale) {
        query = query.eq('locale', locale);
      }
      const { data, error } = await query;
      if (error) {
        return jsonResponse(400, { ok: false, error: error.message });
      }
      return jsonResponse(200, {
        ok: true,
        fonts: (data ?? []).map((row) => publicFont(row, true)),
      });
    }

    if (action === 'delete') {
      const fontId = (payload.fontId ?? '').trim();
      if (!fontId) {
        return jsonResponse(400, { ok: false, error: 'FONT_ID_REQUIRED' });
      }

      const { data: existing, error: existingError } = await supabase
        .from('text_fonts_catalog')
        .select('id,file_path')
        .eq('id', fontId)
        .maybeSingle();
      if (existingError) {
        return jsonResponse(400, { ok: false, error: existingError.message });
      }
      if (!existing) {
        return jsonResponse(404, { ok: false, error: 'FONT_NOT_FOUND' });
      }

      const { error: deleteRowError } = await supabase
        .from('text_fonts_catalog')
        .delete()
        .eq('id', fontId);
      if (deleteRowError) {
        return jsonResponse(400, { ok: false, error: deleteRowError.message });
      }

      const filePath = (existing.file_path ?? '').toString().trim();
      if (filePath) {
        await supabase.storage.from(FONT_BUCKET).remove([filePath]);
      }
      return jsonResponse(200, { ok: true });
    }

    if (action === 'upsert_font') {
      const fontId = (payload.fontId ?? '').trim();
      if (!fontId) {
        return jsonResponse(400, { ok: false, error: 'FONT_ID_REQUIRED' });
      }

      const { data: existing, error: existingError } = await supabase
        .from('text_fonts_catalog')
        .select('id,family,locale')
        .eq('id', fontId)
        .maybeSingle();
      if (existingError) {
        return jsonResponse(400, { ok: false, error: existingError.message });
      }
      if (!existing) {
        return jsonResponse(404, { ok: false, error: 'FONT_NOT_FOUND' });
      }

      const nextLocale = payload.locale == null
        ? (existing.locale as 'english' | 'arabic')
        : normalizeLocale(payload.locale);
      if (!nextLocale) {
        return jsonResponse(400, { ok: false, error: 'FONT_LOCALE_REQUIRED' });
      }

      const patch: Record<string, unknown> = {};
      if (payload.family != null) {
        const normalizedFamily = normalizeFamily(payload.family);
        if (!normalizedFamily) {
          return jsonResponse(400, { ok: false, error: 'FONT_FAMILY_REQUIRED' });
        }
        patch.family = await resolveUniqueFamily(supabase, normalizedFamily, fontId);
      }
      if (payload.label != null) {
        const label = sanitizeLabel(payload.label);
        if (!label) {
          return jsonResponse(400, { ok: false, error: 'FONT_LABEL_REQUIRED' });
        }
        patch.label = label;
      }
      if (payload.locale != null) {
        patch.locale = nextLocale;
      }
      if (payload.preview != null) {
        patch.preview = sanitizePreview(payload.preview, nextLocale);
      }
      if (Number.isFinite(payload.sortOrder)) {
        patch.sort_order = Number(payload.sortOrder);
      }
      if (typeof payload.isActive === 'boolean') {
        patch.is_active = payload.isActive;
      }

      if (!Object.keys(patch).length) {
        const { data, error } = await supabase
          .from('text_fonts_catalog')
          .select('id,family,label,locale,preview,file_url,file_path,mime_type,sort_order,is_active,created_at,updated_at')
          .eq('id', fontId)
          .single();
        if (error) {
          return jsonResponse(400, { ok: false, error: error.message });
        }
        return jsonResponse(200, {
          ok: true,
          result: publicFont(data, true),
        });
      }

      const { data, error } = await supabase
        .from('text_fonts_catalog')
        .update(patch)
        .eq('id', fontId)
        .select('id,family,label,locale,preview,file_url,file_path,mime_type,sort_order,is_active,created_at,updated_at')
        .single();
      if (error) {
        return jsonResponse(400, { ok: false, error: error.message });
      }
      return jsonResponse(200, {
        ok: true,
        result: publicFont(data, true),
      });
    }

    if (action !== 'upload') {
      return jsonResponse(400, { ok: false, error: 'UNSUPPORTED_ACTION' });
    }

    const locale = normalizeLocale(payload.locale);
    if (!locale) {
      return jsonResponse(400, { ok: false, error: 'FONT_LOCALE_REQUIRED' });
    }

    let parsed: ParsedFontFile;
    try {
      parsed = parseFontPayload(payload.fileBase64, payload.mimeType, payload.fileName);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'INVALID_FILE';
      return jsonResponse(400, { ok: false, error: message });
    }

    const fallbackLabel = sanitizeLabel(payload.fileName?.replace(/\.[^.]+$/, '') ?? '');
    const label = sanitizeLabel(payload.label) || fallbackLabel;
    if (!label) {
      return jsonResponse(400, { ok: false, error: 'FONT_LABEL_REQUIRED' });
    }

    const familyBase = normalizeFamily(payload.family) || normalizeFamily(label);
    const family = await resolveUniqueFamily(supabase, familyBase);
    const preview = sanitizePreview(payload.preview, locale);
    const sortOrder = Number.isFinite(payload.sortOrder) ? Number(payload.sortOrder) : 0;

    const now = new Date();
    const year = now.getUTCFullYear().toString();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    const randomPart = crypto.randomUUID().replaceAll('-', '').slice(0, 10);
    const filePath =
      `${locale}/${year}/${month}/${Date.now()}_${randomPart}.${parsed.extension}`;

    const { error: uploadError } = await supabase.storage.from(FONT_BUCKET).upload(
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

    const { data: publicUrlData } = supabase.storage.from(FONT_BUCKET).getPublicUrl(filePath);
    const fileUrl = publicUrlData.publicUrl?.trim() ?? '';
    if (!fileUrl) {
      await supabase.storage.from(FONT_BUCKET).remove([filePath]);
      return jsonResponse(500, { ok: false, error: 'PUBLIC_URL_RESOLUTION_FAILED' });
    }

    const { data: insertRow, error: insertError } = await supabase
      .from('text_fonts_catalog')
      .insert({
        family,
        label,
        locale,
        preview,
        file_path: filePath,
        file_url: fileUrl,
        mime_type: parsed.mimeType,
        sort_order: sortOrder,
        is_active: true,
      })
      .select('id,family,label,locale,preview,file_url,file_path,mime_type,sort_order,is_active,created_at,updated_at')
      .single();
    if (insertError) {
      await supabase.storage.from(FONT_BUCKET).remove([filePath]);
      return jsonResponse(400, { ok: false, error: insertError.message });
    }

    return jsonResponse(200, {
      ok: true,
      result: publicFont(insertRow, true),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected error';
    return jsonResponse(400, { ok: false, error: message });
  }
});
