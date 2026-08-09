import { getApps, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore, type Firestore } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { withScheduledErrorReporting } from "../errors/withErrorReporting.js";
import { NEWSLETTER_RATE_LIMITS_COLLECTION, NEWSLETTER_SUBSCRIBERS_COLLECTION } from "./collections.js";
import { IP_RATE_LIMIT_WINDOW_MS } from "./rateLimit.js";

// Daily data-minimisation sweep: an address that never confirms is not a
// subscriber, and holding it indefinitely serves no purpose. Also prunes
// stale newsletterRateLimits counter docs so that collection does not grow
// unbounded with one document per IP that has ever hit the public endpoint.
const PENDING_RETENTION_MS = 30 * 24 * 60 * 60 * 1000; // 30 days
// A rate-limit doc is "stale" once its window is long over — twice the
// window length gives comfortable margin without needing any query on it.
const RATE_LIMIT_RETENTION_MS = 2 * IP_RATE_LIMIT_WINDOW_MS;

export type SweepResult = {
  readonly deletedSubscribers: number;
  readonly deletedRateLimits: number;
};

export type NewsletterSweepPort = {
  readonly now: () => Date;
  readonly listStalePendingSubscriberIds: (cutoffMs: number) => Promise<readonly string[]>;
  readonly deleteSubscriber: (subscriberId: string) => Promise<void>;
  readonly listStaleRateLimitIds: (cutoffMs: number) => Promise<readonly string[]>;
  readonly deleteRateLimit: (ipHash: string) => Promise<void>;
};

export async function sweepUnconfirmedSubscribersNow(port: NewsletterSweepPort): Promise<SweepResult> {
  const nowMs = port.now().getTime();

  const staleSubscriberIds = await port.listStalePendingSubscriberIds(nowMs - PENDING_RETENTION_MS);
  for (const subscriberId of staleSubscriberIds) {
    await port.deleteSubscriber(subscriberId);
  }

  const staleRateLimitIds = await port.listStaleRateLimitIds(nowMs - RATE_LIMIT_RETENTION_MS);
  for (const ipHash of staleRateLimitIds) {
    await port.deleteRateLimit(ipHash);
  }

  return { deletedSubscribers: staleSubscriberIds.length, deletedRateLimits: staleRateLimitIds.length };
}

if (getApps().length === 0) {
  initializeApp();
}

export const sweepUnconfirmedSubscribers = onSchedule(
  { schedule: "every day 03:00", timeZone: "Asia/Singapore", region: "asia-southeast1" },
  withScheduledErrorReporting("sweepUnconfirmedSubscribers", async () => {
    await sweepUnconfirmedSubscribersNow(firebaseNewsletterSweepPort(getFirestore()));
  }),
);

function firebaseNewsletterSweepPort(firestore: Firestore): NewsletterSweepPort {
  return {
    now: () => new Date(),
    listStalePendingSubscriberIds: async (cutoffMs) => {
      // Uses the status+createdAt composite index (firestore.indexes.json).
      const snapshot = await firestore
        .collection(NEWSLETTER_SUBSCRIBERS_COLLECTION)
        .where("status", "==", "pending")
        .where("createdAt", "<", Timestamp.fromMillis(cutoffMs))
        .get();
      return snapshot.docs.map((doc) => doc.id);
    },
    deleteSubscriber: async (subscriberId) => {
      await firestore.collection(NEWSLETTER_SUBSCRIBERS_COLLECTION).doc(subscriberId).delete();
    },
    listStaleRateLimitIds: async (cutoffMs) => {
      // Full scan, deliberately unindexed: newsletterRateLimits is a small,
      // hot-path-only collection (one doc per IP that has ever hit the
      // public subscribe endpoint), and adding a composite index here would
      // only ever serve this once-daily background sweep — see
      // rateLimit.ts's file header for the matching note on the write side.
      const snapshot = await firestore.collection(NEWSLETTER_RATE_LIMITS_COLLECTION).get();
      const stale: string[] = [];
      for (const doc of snapshot.docs) {
        const windowStart = doc.data()["windowStart"];
        if (typeof windowStart === "number" && windowStart < cutoffMs) {
          stale.push(doc.id);
        }
      }
      return stale;
    },
    deleteRateLimit: async (ipHash) => {
      await firestore.collection(NEWSLETTER_RATE_LIMITS_COLLECTION).doc(ipHash).delete();
    },
  };
}
