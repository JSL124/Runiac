import { Timestamp, type Firestore } from "firebase-admin/firestore";

export const ACTIVITY_FEEDBACK_DAILY_LIMIT = 5;
export type ActivityFeedbackQuotaPolicy = "enforced" | "unlimited-development";

// The default is enforced, so an omitted policy caps model spend rather than
// uncapping it. It used to default to "unlimited-development", which meant
// every entitled runner could drive an unbounded number of paid model calls in
// production — the callable never passes a policy, so the development value
// was the only one production ever used. "unlimited-development" survives as a
// value, but it must now be injected deliberately (tests, emulator drives).
export const DEFAULT_ACTIVITY_FEEDBACK_QUOTA_POLICY: ActivityFeedbackQuotaPolicy =
  "enforced";
const SINGAPORE_UTC_OFFSET_HOURS = 8;

export type ActivityFeedbackQuotaReservation =
  | { readonly kind: "reserved" }
  | { readonly kind: "quota"; readonly retryAfterDate: string };

export function activityFeedbackSingaporeDayKey(now: Date): string {
  const singaporeTime = new Date(
    now.getTime() + SINGAPORE_UTC_OFFSET_HOURS * 60 * 60 * 1000,
  );
  const year = singaporeTime.getUTCFullYear();
  const month = String(singaporeTime.getUTCMonth() + 1).padStart(2, "0");
  const day = String(singaporeTime.getUTCDate()).padStart(2, "0");
  return `${year}${month}${day}`;
}

export function activityFeedbackRetryAfterDate(now: Date): string {
  const singaporeTime = new Date(
    now.getTime() + SINGAPORE_UTC_OFFSET_HOURS * 60 * 60 * 1000,
  );
  const next = new Date(Date.UTC(
    singaporeTime.getUTCFullYear(),
    singaporeTime.getUTCMonth(),
    singaporeTime.getUTCDate() + 1,
  ));
  const year = next.getUTCFullYear();
  const month = String(next.getUTCMonth() + 1).padStart(2, "0");
  const day = String(next.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export async function reserveActivityFeedbackQuota(input: {
  readonly firestore: Firestore;
  readonly uid: string;
  readonly now: Date;
  readonly policy?: ActivityFeedbackQuotaPolicy;
}): Promise<ActivityFeedbackQuotaReservation> {
  const policy = input.policy ?? DEFAULT_ACTIVITY_FEEDBACK_QUOTA_POLICY;
  if (policy === "unlimited-development") {
    return { kind: "reserved" };
  }
  const dayKey = activityFeedbackSingaporeDayKey(input.now);
  const reference = input.firestore.doc(
    `agentUsage/${input.uid}/activityFeedbackDaily/${dayKey}`,
  );
  return input.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const attemptCount = snapshot.exists
      ? Number(snapshot.get("attemptCount") ?? 0)
      : 0;
    if (attemptCount >= ACTIVITY_FEEDBACK_DAILY_LIMIT) {
      return {
        kind: "quota",
        retryAfterDate: activityFeedbackRetryAfterDate(input.now),
      } as const;
    }
    const timestamp = Timestamp.fromDate(input.now);
    if (snapshot.exists) {
      transaction.update(reference, {
        attemptCount: attemptCount + 1,
        updatedAt: timestamp,
      });
    } else {
      transaction.set(reference, {
        schemaVersion: 1,
        dayKey,
        attemptCount: 1,
        createdAt: timestamp,
        updatedAt: timestamp,
      });
    }
    return { kind: "reserved" } as const;
  });
}
