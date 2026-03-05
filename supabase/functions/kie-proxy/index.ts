import { corsHeaders, jsonResponse } from '../_shared/cors.ts';

const KIE_MAIN_BASE = 'https://api.kie.ai';
const KIE_UPLOAD_BASE = 'https://kieai.redpandaai.co';

function readPathParam(req: Request): string {
  const path = new URL(req.url).searchParams.get('path')?.trim() ?? '';
  if (!path.startsWith('/api/')) {
    throw new Error('Invalid path parameter');
  }
  return path;
}

function resolveTarget(path: string): URL {
  const base = path.startsWith('/api/file-') ? KIE_UPLOAD_BASE : KIE_MAIN_BASE;
  return new URL(path, base);
}

function pickForwardHeaders(req: Request): Headers {
  const headers = new Headers();
  const contentType = req.headers.get('content-type');
  const accept = req.headers.get('accept');
  if (contentType && contentType.trim().isNotEmpty) {
    headers.set('content-type', contentType);
  }
  if (accept && accept.trim().isNotEmpty) {
    headers.set('accept', accept);
  }
  return headers;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'GET' && req.method !== 'POST') {
    return jsonResponse(405, { ok: false, error: 'Method not allowed' });
  }

  try {
    const path = readPathParam(req);
    const targetUrl = resolveTarget(path);
    const apiKey = Deno.env.get('KIE_API_KEY')?.trim() ?? '';
    if (!apiKey) {
      return jsonResponse(500, { ok: false, error: 'KIE_API_KEY is not set in function secrets.' });
    }

    const headers = pickForwardHeaders(req);
    headers.set('Authorization', `Bearer ${apiKey}`);

    const upstream = await fetch(targetUrl, {
      method: req.method,
      headers,
      body: req.method == 'GET' ? undefined : req.body,
    });

    const responseHeaders = new Headers(corsHeaders);
    const upstreamType = upstream.headers.get('content-type');
    if (upstreamType && upstreamType.trim().isNotEmpty) {
      responseHeaders.set('Content-Type', upstreamType);
    }

    return new Response(upstream.body, {
      status: upstream.status,
      headers: responseHeaders,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected error';
    return jsonResponse(400, { ok: false, error: message });
  }
});
