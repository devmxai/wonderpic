import { corsHeaders, jsonResponse } from '../_shared/cors.ts';
import { readBackendEnv } from '../_shared/env.ts';
import {
  extractBearerToken,
  isFirebaseAuthError,
  verifyFirebaseIdToken,
} from '../_shared/firebase.ts';
import { firstRow } from '../_shared/rpc.ts';
import { createServiceClient } from '../_shared/supabase.ts';

type FreeTrialConsumePayload = {
  operationType?: string;
  idempotencyKey?: string;
  metadata?: Record<string, unknown>;
};

function mapConsumeError(message: string): number {
  if (message.includes('FREE_TRIAL_EXHAUSTED')) return 402;
  if (message.includes('ACCOUNT_NOT_ACTIVE') || message.includes('ACCOUNT_DELETED')) {
    return 403;
  }
  if (message.includes('IDEMPOTENCY_KEY_REQUIRED')) return 400;
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
    const payload = (await req.json().catch(() => ({}))) as FreeTrialConsumePayload;

    const operationType = payload.operationType?.trim() ?? 'operation';
    const idempotencyKey =
      payload.idempotencyKey?.trim() ?? req.headers.get('x-idempotency-key')?.trim() ?? '';

    const supabase = createServiceClient(env);
    const { data, error } = await supabase.rpc('app_consume_free_trial_action', {
      p_firebase_uid: identity.uid,
      p_idempotency_key: idempotencyKey,
      p_operation_type: operationType,
      p_metadata: payload.metadata ?? {},
    });

    if (error) {
      return jsonResponse(mapConsumeError(error.message), {
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
