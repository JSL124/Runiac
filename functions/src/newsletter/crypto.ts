import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

/**
 * Token contract for the whole newsletter module: a "raw" token is 32 random
 * bytes, base64url-encoded, handed to the recipient inside a link. Only
 * sha256(raw) is ever persisted for verification, so a Firestore read alone
 * can never mint a working link. See subscribeNewsletter.ts's file header
 * for the one deliberate exception (the unsubscribe token's raw value is
 * also retained, not just its hash) and why.
 */
export function generateRawToken(): string {
  return randomBytes(32).toString("base64url");
}

export function sha256Hex(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

export function subscriberIdForEmail(emailLower: string): string {
  return sha256Hex(emailLower);
}

/**
 * Constant-time comparison for two hex-encoded sha256 digests. Both inputs
 * are attacker-adjacent (one derived from a caller-supplied token), so a
 * length-dependent or short-circuiting compare could leak timing
 * information about how close a guess is. Digests of different lengths
 * (malformed input) are rejected without falling through to
 * timingSafeEqual, which throws on mismatched buffer lengths.
 */
export function hashesEqual(a: string, b: string): boolean {
  const bufferA = Buffer.from(a, "utf8");
  const bufferB = Buffer.from(b, "utf8");
  if (bufferA.length !== bufferB.length) {
    return false;
  }
  return timingSafeEqual(bufferA, bufferB);
}
