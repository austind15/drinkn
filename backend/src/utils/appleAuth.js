import { createRemoteJWKSet, jwtVerify, decodeJwt } from 'jose';

const APPLE_ISSUER = 'https://appleid.apple.com';
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';

const jwks = createRemoteJWKSet(new URL(APPLE_JWKS_URL));

// Verify an identityToken from Sign in with Apple on iOS.
// Returns the verified payload (sub, email, etc.) or throws.
export async function verifyAppleIdentityToken(identityToken) {
  const audience = process.env.APPLE_BUNDLE_ID;
  if (!audience) {
    throw new Error('APPLE_BUNDLE_ID env var is not set');
  }
  let payload;
  try {
    ({ payload } = await jwtVerify(identityToken, jwks, {
      issuer: APPLE_ISSUER,
      audience,
    }));
  } catch (err) {
    // Helpful diagnostic: show what aud the token *actually* has so we can
    // compare against APPLE_BUNDLE_ID without trusting it.
    try {
      const claims = decodeJwt(identityToken);
      console.error(
        `[appleAuth] verify failed (${err.code || err.message}). ` +
        `expected aud="${audience}", got aud="${claims.aud}", iss="${claims.iss}", sub="${claims.sub}"`
      );
    } catch {}
    throw err;
  }
  if (!payload.sub) {
    throw new Error('Apple identity token missing sub claim');
  }
  return payload;
}
