import { createRemoteJWKSet, jwtVerify, type JWTPayload } from 'npm:jose@5.9.6';

const firebaseJwks = createRemoteJWKSet(
  new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'),
);

export type FirebaseIdentity = {
  uid: string;
  email: string | null;
  name: string | null;
  picture: string | null;
  claims: JWTPayload;
};

export function extractBearerToken(authorizationHeader: string | null): string {
  const raw = authorizationHeader?.trim() ?? '';
  if (!raw.toLowerCase().startsWith('bearer ')) {
    throw new Error('Missing Bearer token');
  }
  const token = raw.slice(7).trim();
  if (!token) {
    throw new Error('Bearer token is empty');
  }
  return token;
}

export async function verifyFirebaseIdToken(
  idToken: string,
  firebaseProjectId: string,
): Promise<FirebaseIdentity> {
  const { payload } = await jwtVerify(idToken, firebaseJwks, {
    issuer: `https://securetoken.google.com/${firebaseProjectId}`,
    audience: firebaseProjectId,
  });

  const uid = String(payload.sub ?? '').trim();
  if (!uid) {
    throw new Error('Firebase token missing subject');
  }

  return {
    uid,
    email: typeof payload.email === 'string' ? payload.email : null,
    name: typeof payload.name === 'string' ? payload.name : null,
    picture: typeof payload.picture === 'string' ? payload.picture : null,
    claims: payload,
  };
}

export function isFirebaseAuthError(message: string): boolean {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('bearer token') ||
    normalized.includes('invalid compact jws') ||
    normalized.includes('jwt') ||
    normalized.includes('jws') ||
    normalized.includes('signature') ||
    normalized.includes('token')
  );
}
