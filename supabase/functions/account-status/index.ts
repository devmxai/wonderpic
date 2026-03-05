import { corsHeaders, jsonResponse } from '../_shared/cors.ts';
import { readBackendEnv } from '../_shared/env.ts';
import { extractBearerToken, isFirebaseAuthError, verifyFirebaseIdToken } from '../_shared/firebase.ts';
import { firstRow } from '../_shared/rpc.ts';
import { createServiceClient } from '../_shared/supabase.ts';

type AccountStatusPayload = {
  action?: string;
  reason?: string;
  targetFirebaseUid?: string;
  targetStatus?: 'active' | 'suspended' | 'deleted';
  grantAmount?: number;
  idempotencyKey?: string;
  metadata?: Record<string, unknown>;
};

function isAuthorizedAdmin(req: Request, adminToken: string): boolean {
  if (!adminToken) return false;
  const incoming = req.headers.get('x-admin-token')?.trim() ?? '';
  return incoming.length > 0 && incoming === adminToken;
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
    const payload = (await req.json().catch(() => ({}))) as AccountStatusPayload;
    const action = (payload.action ?? 'get').trim();
    const supabase = createServiceClient(env);

    if (action === 'admin_set_status' || action === 'admin_grant_credits') {
      if (!isAuthorizedAdmin(req, env.adminToken)) {
        return jsonResponse(403, { ok: false, error: 'ADMIN_AUTH_REQUIRED' });
      }

      const targetUid = payload.targetFirebaseUid?.trim() ?? '';
      if (!targetUid) {
        return jsonResponse(400, { ok: false, error: 'TARGET_FIREBASE_UID_REQUIRED' });
      }

      if (action === 'admin_set_status') {
        const targetStatus = payload.targetStatus?.trim() ?? '';
        const { data, error } = await supabase.rpc('app_set_account_status', {
          p_firebase_uid: targetUid,
          p_status: targetStatus,
          p_reason: payload.reason ?? null,
        });

        if (error) {
          return jsonResponse(400, { ok: false, error: error.message, code: error.code });
        }

        return jsonResponse(200, {
          ok: true,
          result: firstRow<Record<string, unknown>>(data as Record<string, unknown>[]),
        });
      }

      const grantAmount = Number(payload.grantAmount ?? 0);
      const idempotencyKey = payload.idempotencyKey?.trim() ?? '';
      const { data, error } = await supabase.rpc('app_grant_credits', {
        p_firebase_uid: targetUid,
        p_amount: grantAmount,
        p_idempotency_key: idempotencyKey,
        p_reason: payload.reason ?? 'admin_grant',
        p_metadata: payload.metadata ?? {},
      });

      if (error) {
        return jsonResponse(400, { ok: false, error: error.message, code: error.code });
      }

      return jsonResponse(200, {
        ok: true,
        result: firstRow<Record<string, unknown>>(data as Record<string, unknown>[]),
      });
    }

    const idToken = extractBearerToken(req.headers.get('Authorization'));
    const identity = await verifyFirebaseIdToken(idToken, env.firebaseProjectId);

    if (action === 'delete_me') {
      const { data, error } = await supabase.rpc('app_set_account_status', {
        p_firebase_uid: identity.uid,
        p_status: 'deleted',
        p_reason: payload.reason ?? 'user_requested_delete',
      });

      if (error) {
        return jsonResponse(400, { ok: false, error: error.message, code: error.code });
      }

      return jsonResponse(200, {
        ok: true,
        result: firstRow<Record<string, unknown>>(data as Record<string, unknown>[]),
      });
    }

    const { data: ensured, error: ensureError } = await supabase.rpc('app_ensure_account', {
      p_firebase_uid: identity.uid,
      p_email: identity.email,
      p_display_name: identity.name,
      p_photo_url: identity.picture,
      p_metadata: {
        firebase_provider:
          typeof identity.claims.firebase === 'object' && identity.claims.firebase
            ? (identity.claims.firebase as Record<string, unknown>).sign_in_provider ?? null
            : null,
      },
    });

    if (ensureError) {
      return jsonResponse(500, { ok: false, error: ensureError.message, code: ensureError.code });
    }

    const ensuredAccount = firstRow<Record<string, unknown>>(ensured as Record<string, unknown>[]);

    const { data, error } = await supabase.rpc('app_account_state', {
      p_firebase_uid: identity.uid,
    });

    if (error) {
      return jsonResponse(500, { ok: false, error: error.message, code: error.code });
    }

    const { data: freeTrialData, error: freeTrialError } = await supabase.rpc(
      'app_free_trial_state',
      {
        p_firebase_uid: identity.uid,
      },
    );

    if (freeTrialError) {
      return jsonResponse(500, {
        ok: false,
        error: freeTrialError.message,
        code: freeTrialError.code,
      });
    }

    const accountState = firstRow<Record<string, unknown>>(data as Record<string, unknown>[]);
    const freeTrialState = firstRow<Record<string, unknown>>(
      freeTrialData as Record<string, unknown>[],
    );
    const mergedState = {
      ...accountState,
      free_trial_total: freeTrialState?.free_trial_total,
      free_trial_remaining: freeTrialState?.free_trial_remaining,
    };

    return jsonResponse(200, {
      ok: true,
      ensuredAccount,
      result: mergedState,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected error';
    const status = isFirebaseAuthError(message) ? 401 : 400;
    return jsonResponse(status, { ok: false, error: message });
  }
});
