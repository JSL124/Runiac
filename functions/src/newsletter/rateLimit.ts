import type { Firestore } from "firebase-admin/firestore";
import { NEWSLETTER_RATE_LIMITS_COLLECTION } from "./collections.js";

export const IP_RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
export const IP_RATE_LIMIT_MAX = 5;

/**
 * newsletterRateLimits/{ipHash} is a plain counter doc: { windowStart,
 * count }, both plain numbers (not a Firestore Timestamp / serverTimestamp
 * sentinel — a transaction cannot read back the resolved value of a
 * serverTimestamp() write within the same transaction, and this needs to
 * compare "now" against the stored window start on every call). Deliberately
 * NOT queried by timestamp anywhere on this path — the hot path is always a
 * single doc get by ipHash, so no composite index is needed here. (The
 * daily sweep that prunes stale rate-limit docs uses an unindexed full scan
 * instead of a query, for the same reason — see sweepUnconfirmedSubscribers.ts.)
 *
 * Returns true if the call is allowed (and has been counted against the
 * window), false if the caller is over the 5/hour limit.
 */
export async function checkAndConsumeIpRateLimit(
  firestore: Firestore,
  ipHash: string,
  nowMs: number,
): Promise<boolean> {
  const ref = firestore.collection(NEWSLETTER_RATE_LIMITS_COLLECTION).doc(ipHash);
  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data();
    const windowStart = typeof data?.["windowStart"] === "number" ? data["windowStart"] : null;
    const count = typeof data?.["count"] === "number" ? data["count"] : 0;
    const windowExpired = windowStart === null || nowMs - windowStart >= IP_RATE_LIMIT_WINDOW_MS;

    if (windowExpired) {
      transaction.set(ref, { windowStart: nowMs, count: 1 });
      return true;
    }

    if (count >= IP_RATE_LIMIT_MAX) {
      return false;
    }

    transaction.set(ref, { windowStart, count: count + 1 });
    return true;
  });
}
