import { createClient } from 'npm:@supabase/supabase-js@2.49.1';
import type { BackendEnv } from './env.ts';

export function createServiceClient(env: BackendEnv) {
  return createClient(env.supabaseUrl, env.supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}
