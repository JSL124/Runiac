import { Timestamp, type Firestore } from "firebase-admin/firestore";

// Enforced from the day this agent shipped, unlike the activity-feedback
// counter that is still short-circuited by a development policy. This is the
// only OpenAI-backed surface a runner can reach without first completing a run,
// so an unbounded default would be the easiest way to spend the project's model
// budget. The client's seven-day content-fingerprint cache means a runner
// re-reading the same workout does not consume an attempt.

export const WORKOUT_BRIEFING_DAILY_LIMIT = 5;
const SINGAPORE_UTC_OFFSET_HOURS = 8;

export type WorkoutBriefingQuotaReservation =
  | { readonly kind: "reserved" }
  | { readonly kind: "quota"; readonly retryAfterDate: string };

export function workoutBriefingSingaporeDayKey(now: Date): string {
  const singaporeTime = new Date(
    now.getTime() + SINGAPORE_UTC_OFFSET_HOURS * 60 * 60 * 1000,
  );
  const year = singaporeTime.getUTCFullYear();
  const month = String(singaporeTime.getUTCMonth() + 1).padStart(2, "0");
  const day = String(singaporeTime.getUTCDate()).padStart(2, "0");
  return `${year}${month}${day}`;
}

export function workoutBriefingRetryAfterDate(now: Date): string {
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

export async function reserveWorkoutBriefingQuota(input: {
  readonly firestore: Firestore;
  readonly uid: string;
  readonly now: Date;
  readonly dailyLimit?: number;
}): Promise<WorkoutBriefingQuotaReservation> {
  const dailyLimit = input.dailyLimit ?? WORKOUT_BRIEFING_DAILY_LIMIT;
  const dayKey = workoutBriefingSingaporeDayKey(input.now);
  const reference = input.firestore.doc(
    `agentUsage/${input.uid}/workoutBriefingDaily/${dayKey}`,
  );
  return input.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const attemptCount = snapshot.exists
      ? Number(snapshot.get("attemptCount") ?? 0)
      : 0;
    if (attemptCount >= dailyLimit) {
      return {
        kind: "quota",
        retryAfterDate: workoutBriefingRetryAfterDate(input.now),
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
