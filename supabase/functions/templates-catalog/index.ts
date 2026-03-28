import { corsHeaders, jsonResponse } from '../_shared/cors.ts';
import { readBackendEnv } from '../_shared/env.ts';
import { createServiceClient } from '../_shared/supabase.ts';

type TemplatesCatalogPayload = {
  action?: string;
  templateId?: string;
  title?: string;
  fileBase64?: string;
  fileName?: string;
  mimeType?: string;
  width?: number;
  height?: number;
  sortOrder?: number;
  isActive?: boolean;
};

type ParsedSvg = {
  bytes: Uint8Array;
  text: string;
  mimeType: 'image/svg+xml' | 'text/xml' | 'application/xml';
};

type SvgDimensions = {
  width: number | null;
  height: number | null;
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

function sanitizeTitle(raw: string | null | undefined): string | null {
  const normalized = (raw ?? '').trim().replace(/\s+/g, ' ');
  if (!normalized) return null;
  return normalized.length <= 100 ? normalized : normalized.slice(0, 100);
}

function decodeBase64ToBytes(base64Payload: string): Uint8Array {
  const binary = atob(base64Payload);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function normalizeSvgMime(raw: string | null | undefined): ParsedSvg['mimeType'] | null {
  const value = (raw ?? '').trim().toLowerCase();
  if (!value) return null;
  if (value === 'image/svg+xml') return 'image/svg+xml';
  if (value === 'text/xml') return 'text/xml';
  if (value === 'application/xml') return 'application/xml';
  return null;
}

function parseSvgPayload(
  fileBase64Raw: string | null | undefined,
  mimeTypeRaw: string | null | undefined,
): ParsedSvg {
  const raw = (fileBase64Raw ?? '').trim();
  if (!raw) {
    throw new Error('FILE_BASE64_REQUIRED');
  }

  let mimeType = normalizeSvgMime(mimeTypeRaw) ?? 'image/svg+xml';
  let payload = raw;

  if (raw.startsWith('data:')) {
    const match = /^data:([^;]+);base64,(.+)$/i.exec(raw);
    if (!match) {
      throw new Error('INVALID_DATA_URL');
    }
    const dataMime = normalizeSvgMime(match[1]);
    if (!dataMime) {
      throw new Error('UNSUPPORTED_MIME_TYPE');
    }
    mimeType = dataMime;
    payload = match[2];
  }

  const bytes = decodeBase64ToBytes(payload);
  if (!bytes.length) {
    throw new Error('EMPTY_FILE');
  }
  if (bytes.length > 15 * 1024 * 1024) {
    throw new Error('FILE_TOO_LARGE');
  }

  const text = new TextDecoder('utf-8', { fatal: false }).decode(bytes);
  if (!/<svg\b/i.test(text)) {
    throw new Error('INVALID_SVG_CONTENT');
  }

  return {
    bytes,
    text,
    mimeType,
  };
}

function parseDimensionScalar(raw: string | null): number | null {
  const value = (raw ?? '').trim();
  if (!value || value.endsWith('%')) return null;
  const match = /^([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*([a-zA-Z]*)$/.exec(value);
  if (!match) return null;
  const parsed = Number.parseFloat(match[1]);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  const unit = (match[2] ?? '').trim().toLowerCase();
  const unitFactors: Record<string, number> = {
    '': 1,
    px: 1,
    pt: 96 / 72,
    pc: 16,
    in: 96,
    cm: 96 / 2.54,
    mm: 96 / 25.4,
    q: 96 / 101.6,
  };
  const factor = unitFactors[unit];
  if (!Number.isFinite(factor) || factor <= 0) return null;
  const valuePx = parsed * factor;
  if (!Number.isFinite(valuePx) || valuePx <= 0) return null;
  return valuePx;
}

function normalizePixelDimension(raw: unknown): number | null {
  if (raw == null) return null;
  const parsed = typeof raw === 'number' ? raw : Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  const rounded = Math.round(parsed);
  if (!Number.isFinite(rounded) || rounded <= 0) return null;
  return Math.min(rounded, 100000);
}

function parseSvgDimensions(svgText: string): SvgDimensions {
  const viewBoxMatch = /\bviewBox\s*=\s*['"]([^'"]+)['"]/i.exec(svgText);
  if (viewBoxMatch) {
    const parts = viewBoxMatch[1]
      .trim()
      .split(/[\s,]+/)
      .map((part) => Number.parseFloat(part))
      .filter((value) => Number.isFinite(value));
    if (parts.length >= 4) {
      const width = parts[2];
      const height = parts[3];
      if (width > 0 && height > 0) {
        return { width, height };
      }
    }
  }

  const widthMatch = /\bwidth\s*=\s*['"]([^'"]+)['"]/i.exec(svgText);
  const heightMatch = /\bheight\s*=\s*['"]([^'"]+)['"]/i.exec(svgText);
  return {
    width: parseDimensionScalar(widthMatch?.[1] ?? null),
    height: parseDimensionScalar(heightMatch?.[1] ?? null),
  };
}

function publicTemplate(row: Record<string, unknown>, adminView = false) {
  return {
    id: row.id,
    title: row.title,
    file_url: row.file_url,
    mime_type: row.mime_type,
    width: row.width,
    height: row.height,
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

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const env = readBackendEnv();
    const supabase = createServiceClient(env);

    if (req.method === 'GET') {
      const url = new URL(req.url);
      const limit = clampInt(url.searchParams.get('limit'), 120, 1, 500);
      const offset = clampInt(url.searchParams.get('offset'), 0, 0, 10000);
      const includeInactiveRequested =
        (url.searchParams.get('includeInactive') ?? '').trim().toLowerCase() === 'true';
      const includeInactive = includeInactiveRequested && isAuthorizedAdmin(req, env.adminToken);

      let query = supabase
        .from('templates_catalog')
        .select('id,title,file_url,mime_type,width,height,sort_order,created_at,is_active,file_path,updated_at')
        .order('sort_order', { ascending: true })
        .order('created_at', { ascending: false })
        .range(offset, offset + limit - 1);

      if (!includeInactive) {
        query = query.eq('is_active', true);
      }

      const { data, error } = await query;
      if (error) {
        return jsonResponse(500, { ok: false, error: error.message });
      }

      return jsonResponse(200, {
        ok: true,
        templates: (data ?? []).map((row) => publicTemplate(row, includeInactive)),
        paging: {
          limit,
          offset,
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

    const payload = (await req.json().catch(() => ({}))) as TemplatesCatalogPayload;
    const action = (payload.action ?? 'upload').trim().toLowerCase();

    if (action === 'delete') {
      const templateId = (payload.templateId ?? '').trim();
      if (!templateId) {
        return jsonResponse(400, { ok: false, error: 'TEMPLATE_ID_REQUIRED' });
      }

      const { data: existing, error: existingError } = await supabase
        .from('templates_catalog')
        .select('id,file_path')
        .eq('id', templateId)
        .maybeSingle();

      if (existingError) {
        return jsonResponse(400, { ok: false, error: existingError.message });
      }
      if (!existing) {
        return jsonResponse(404, { ok: false, error: 'TEMPLATE_NOT_FOUND' });
      }

      const { error: deleteRowError } = await supabase
        .from('templates_catalog')
        .delete()
        .eq('id', templateId);
      if (deleteRowError) {
        return jsonResponse(400, { ok: false, error: deleteRowError.message });
      }

      const filePath = (existing.file_path ?? '').toString().trim();
      if (filePath) {
        await supabase.storage.from('templates').remove([filePath]);
      }

      return jsonResponse(200, { ok: true });
    }

    if (action === 'upsert_template') {
      const templateId = (payload.templateId ?? '').trim();
      if (!templateId) {
        return jsonResponse(400, { ok: false, error: 'TEMPLATE_ID_REQUIRED' });
      }

      const title = sanitizeTitle(payload.title);
      const sortOrder = Number.isFinite(payload.sortOrder)
        ? Number(payload.sortOrder)
        : 0;
      const isActive = payload.isActive ?? true;

      const updateRow: Record<string, unknown> = {
        sort_order: sortOrder,
        is_active: isActive,
      };
      if (title) {
        updateRow.title = title;
      }

      const { data, error } = await supabase
        .from('templates_catalog')
        .update(updateRow)
        .eq('id', templateId)
        .select('id,title,file_url,mime_type,width,height,sort_order,created_at,is_active,file_path,updated_at')
        .single();

      if (error) {
        return jsonResponse(400, { ok: false, error: error.message });
      }

      return jsonResponse(200, {
        ok: true,
        result: publicTemplate(data, true),
      });
    }

    if (action !== 'upload') {
      return jsonResponse(400, { ok: false, error: 'UNSUPPORTED_ACTION' });
    }

    let parsed: ParsedSvg;
    try {
      parsed = parseSvgPayload(payload.fileBase64, payload.mimeType);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'INVALID_FILE';
      return jsonResponse(400, { ok: false, error: message });
    }

    const derivedDimensions = parseSvgDimensions(parsed.text);
    const width = normalizePixelDimension(payload.width) ??
      normalizePixelDimension(derivedDimensions.width);
    const height = normalizePixelDimension(payload.height) ??
      normalizePixelDimension(derivedDimensions.height);

    const now = new Date();
    const year = now.getUTCFullYear().toString();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    const randomPart = crypto.randomUUID().replaceAll('-', '').slice(0, 10);
    const filePath = `templates/${year}/${month}/${Date.now()}_${randomPart}.svg`;

    const { error: uploadError } = await supabase.storage
      .from('templates')
      .upload(filePath, parsed.bytes, {
        contentType: 'image/svg+xml',
        upsert: false,
        cacheControl: '3600',
      });

    if (uploadError) {
      return jsonResponse(400, { ok: false, error: uploadError.message });
    }

    const { data: publicUrlData } = supabase.storage.from('templates').getPublicUrl(filePath);
    const fileUrl = publicUrlData.publicUrl?.trim() ?? '';
    if (!fileUrl) {
      await supabase.storage.from('templates').remove([filePath]);
      return jsonResponse(500, { ok: false, error: 'PUBLIC_URL_RESOLUTION_FAILED' });
    }

    const title = sanitizeTitle(payload.title) ??
      sanitizeTitle(payload.fileName) ??
      'Template';
    const sortOrder = Number.isFinite(payload.sortOrder)
      ? Number(payload.sortOrder)
      : 0;

    const { data: insertRow, error: insertError } = await supabase
      .from('templates_catalog')
      .insert({
        title,
        file_path: filePath,
        file_url: fileUrl,
        mime_type: 'image/svg+xml',
        width,
        height,
        sort_order: sortOrder,
        is_active: true,
      })
      .select('id,title,file_url,mime_type,width,height,sort_order,created_at,is_active,file_path,updated_at')
      .single();

    if (insertError) {
      await supabase.storage.from('templates').remove([filePath]);
      return jsonResponse(400, { ok: false, error: insertError.message });
    }

    return jsonResponse(200, {
      ok: true,
      result: publicTemplate(insertRow, true),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected error';
    return jsonResponse(400, { ok: false, error: message });
  }
});
