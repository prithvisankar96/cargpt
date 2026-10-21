import { createRemoteJWKSet, jwtVerify, SignJWT, type JWTVerifyGetKey } from "jose";

const APPLE_ISSUER = "https://appleid.apple.com";
const SESSION_ISSUER = "cargpt-backend";
const SESSION_AUDIENCE = "cargpt-app";
export const SESSION_TTL_SECONDS = 30 * 24 * 60 * 60;

/** Apple's published signing keys for Sign in with Apple identity tokens (fetched and cached by jose). */
export const appleSigningKeys: JWTVerifyGetKey = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
);

/**
 * Verifies an identity token from Sign in with Apple and returns the stable Apple user ID.
 * Throws if the signature, issuer, audience, or expiry is wrong.
 */
export async function verifyAppleIdentityToken(
  identityToken: string,
  bundleId: string,
  keys: JWTVerifyGetKey,
): Promise<string> {
  const { payload } = await jwtVerify(identityToken, keys, {
    issuer: APPLE_ISSUER,
    audience: bundleId,
  });
  if (!payload.sub) {
    throw new Error("identity token has no subject");
  }
  return payload.sub;
}

export async function issueSessionToken(userId: string, secret: Uint8Array): Promise<string> {
  return new SignJWT()
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuer(SESSION_ISSUER)
    .setAudience(SESSION_AUDIENCE)
    .setIssuedAt()
    .setExpirationTime(`${SESSION_TTL_SECONDS}s`)
    .sign(secret);
}

/** Returns the user ID from a valid session token, or throws. */
export async function verifySessionToken(token: string, secret: Uint8Array): Promise<string> {
  const { payload } = await jwtVerify(token, secret, {
    issuer: SESSION_ISSUER,
    audience: SESSION_AUDIENCE,
    algorithms: ["HS256"],
  });
  if (!payload.sub) {
    throw new Error("session token has no subject");
  }
  return payload.sub;
}
