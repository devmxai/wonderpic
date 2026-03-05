import { corsHeaders, jsonResponse } from '../_shared/cors.ts';
import { readBackendEnv } from '../_shared/env.ts';
import { extractBearerToken, isFirebaseAuthError, verifyFirebaseIdToken } from '../_shared/firebase.ts';
import { firstRow } from '../_shared/rpc.ts';
import { createServiceClient } from '../_shared/supabase.ts';

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
    const supabase = createServiceClient(env);

    const metadata = {
      firebase_provider:
        typeof identity.claims.firebase === 'object' && identity.claims.firebase
          ? (identity.claims.firebase as Record<string, unknown>).sign_in_provider ?? null
          : null,
      firebase_claims: identity.claims,
    };

    const { data, error } = await supabase.rpc('app_ensure_account', {
      p_firebase_uid: identity.uid,
      p_email: identity.email,
      p_display_name: identity.name,
      p_photo_url: identity.picture,
      p_metadata: metadata,
    });

    if (error) {
      return jsonResponse(500, { ok: false, error: 'ACCOUNT_SYNC_FAILED', details: error.message });
    }

    const account = firstRow<Record<string, unknown>>(data as Record<string, unknown>[]);
    const { data: freeTrialData, error: freeTrialError } = await supabase.rpc('app_free_trial_state', {
      p_firebase_uid: identity.uid,
    });

    if (freeTrialError) {
      return jsonResponse(500, {
        ok: false,
        error: 'FREE_TRIAL_SYNC_FAILED',
        details: freeTrialError.message,
      });
    }

    const freeTrial = firstRow<Record<string, unknown>>(
      freeTrialData as Record<string, unknown>[],
    );
    const mergedAccount = {
      ...account,
      free_trial_total: freeTrial?.free_trial_total,
      free_trial_remaining: freeTrial?.free_trial_remaining,
    };

    return jsonResponse(200, {
      ok: true,
      identity: {
        uid: identity.uid,
        email: identity.email,
        name: identity.name,
      },
      account: mergedAccount,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected error';
    const status = isFirebaseAuthError(message) ? 401 : 400;
    return jsonResponse(status, { ok: false, error: message });
  }
});
