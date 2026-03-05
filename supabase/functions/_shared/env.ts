export type BackendEnv = {
  supabaseUrl: string;
  supabaseServiceRoleKey: string;
  firebaseProjectId: string;
  adminToken: string;
};

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim() ?? '';
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

export function readBackendEnv(): BackendEnv {
  const supabaseUrl = requiredEnv('SUPABASE_URL');
  const supabaseServiceRoleKey = requiredEnv('SUPABASE_SERVICE_ROLE_KEY');
  const firebaseProjectId = requiredEnv('FIREBASE_PROJECT_ID');
  const adminToken = Deno.env.get('APP_ADMIN_TOKEN')?.trim() ?? '';

  return {
    supabaseUrl,
    supabaseServiceRoleKey,
    firebaseProjectId,
    adminToken,
  };
}
