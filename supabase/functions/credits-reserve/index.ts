import { corsHeaders, jsonResponse } from '../_shared/cors.ts';
import { readBackendEnv } from '../_shared/env.ts';
import { extractBearerToken, isFirebaseAuthError, verifyFirebaseIdToken } from '../_shared/firebase.ts';
import { firstRow } from '../_shared/rpc.ts';
import { createServiceClient } from '../_shared/supabase.ts';

type ReservePayload = {
  amount?: number;
  idempotencyKey?: string;
  operationKey?: string;
  reason?: string;
  ttlSeconds?: number;
  metadata?: Record<string, unknown>;
};

function mapReserveError(message: string): number {
  if (message.includes('INSUFFICIENT_CREDITS')) return 402;
  if (message.includes('ACCOUNT_NOT_ACTIVE') || message.includes('ACCOUNT_DELETED')) return 403;
  if (message.includes('IDEMPOTENCY_KEY_REQUIRED') || message.includes('INVALID_AMOUNT')) return 400;
  return 500;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse(405, { ok: false, error: 'Method not allowed' });
  }

  try {
    const env = readBackendEnv();
    const idToken = extractBearerToken(req.headers.get('Authorization'));
    const identity = await verifyFirebaseIdToken(idToken, env.firebaseProjectId);
    const payload = (await req.json().catch(() => ({}))) as ReservePayload;

    const amount = Number(payload.amount ?? 0);
    const idempotencyKey =
      payload.idempotencyKey?.trim() ?? req.headers.get('x-idempotency-key')?.trim() ?? '';
    const operationKey = payload.operationKey?.trim() ?? idempotencyKey;

    const supabase = createServiceClient(env);
    const { data, error } = await supabase.rpc('app_reserve_credits', {
      p_firebase_uid: identity.uid,
      p_amount: amount,
      p_idempotency_key: idempotencyKey,
      p_operation_key: operationKey,
      p_reason: payload.reason ?? null,
      p_ttl_seconds: payload.ttlSeconds ?? 900,
      p_metadata: payload.metadata ?? {},
    });

    if (error) {
      return jsonResponse(mapReserveError(error.message), {
        ok: false,
        error: error.message,
        code: error.code,
      });
    }

    return jsonResponse(200, {
      ok: true,
      result: firstRow<Record<string, unknown>>(data as Record<string, unknown>[]),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected error';
    const status = isFirebaseAuthError(message) ? 401 : 400;
    return jsonResponse(status, { ok: false, error: message });
  }
});
