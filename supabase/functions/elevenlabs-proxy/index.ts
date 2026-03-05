import { corsHeaders, jsonResponse } from '../_shared/cors.ts';

const ELEVEN_BASE = 'https://api.elevenlabs.io';

function readPathParam(req: Request): string {
  const path = new URL(req.url).searchParams.get('path')?.trim() ?? '';
  if (!path.startsWith('/v1/')) {
    throw new Error('Invalid path parameter');
  }
  return path;
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
    const targetUrl = new URL(path, ELEVEN_BASE);
    const apiKey = Deno.env.get('ELEVENLABS_API_KEY')?.trim() ?? '';
    if (!apiKey) {
      return jsonResponse(500, {
        ok: false,
        error: 'ELEVENLABS_API_KEY is not set in function secrets.',
      });
    }

    const headers = pickForwardHeaders(req);
    headers.set('xi-api-key', apiKey);

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
