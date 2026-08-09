import { randomUUID } from "node:crypto";
import { type Firestore } from "firebase-admin/firestore";

const cleanupLeaseDurationMs = 15 * 60 * 1000;

export function newCleanupLeaseId(): string {
  return randomUUID();
}

export async function claimCleanupLease(firestore: Firestore, periodKey: string, cleanupLeaseId: string): Promise<void> {
  const lockRef = firestore.collection("leaderboardAggregationLocks").doc(`monthly_${periodKey}`);
  await firestore.runTransaction(async (transaction) => {
    const lock = await transaction.get(lockRef);
    const leaseExpiresAt = Date.parse(String(lock.get("leaseExpiresAt") ?? ""));
    if (lock.get("status") === "running" && (!Number.isFinite(leaseExpiresAt) || leaseExpiresAt > Date.now())) {
      throw new Error("cleanup blocked by an active leaderboard refresh");
    }
    const now = new Date();
    transaction.set(lockRef, {
      periodType: "monthly", periodKey, status: "running", buildId: `cleanup_lease_${cleanupLeaseId}`,
      cleanupLeaseId, cleanupLeaseStatus: "deleting", startedAt: now.toISOString(),
      leaseExpiresAt: new Date(now.getTime() + cleanupLeaseDurationMs).toISOString(), updatedAt: now.toISOString(),
    }, { merge: true });
  });
}

export async function releaseCleanupLease(firestore: Firestore, periodKey: string, cleanupLeaseId: string): Promise<void> {
  const lockRef = firestore.collection("leaderboardAggregationLocks").doc(`monthly_${periodKey}`);
  await firestore.runTransaction(async (transaction) => {
    const lock = await transaction.get(lockRef);
    if (lock.get("cleanupLeaseId") !== cleanupLeaseId) return;
    const releasedAt = new Date().toISOString();
    transaction.set(lockRef, { status: "cleanup_released", cleanupLeaseStatus: "released", leaseExpiresAt: releasedAt, updatedAt: releasedAt }, { merge: true });
  });
}
