// Scheduled Challenge deadline-settlement sweep (Todo 6).
//
// One-minute cadence (same registration style as scheduledPushDispatch, but
// 60s): (a) fails ACTIVE instances past scheduledEndsAt, (b) finishes/retries
// SETTLING success settlements with idempotent grant issuance, (c) applies the
// lazy lobby-expiry seam to RECRUITING lobbies past their expiry instant.
// Repeated invocations are idempotent; the core returns per-category counts.

import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  runChallengeSettlementSweep,
  type ChallengeSettlementSweepResult,
} from "./challengeSettlementCore.js";
import {
  runChallengePremiumLapseSweep,
  type PremiumLapseSweepResult,
} from "./challengePremiumLapse.js";
import { withScheduledErrorReporting } from "../errors/withErrorReporting.js";

if (getApps().length === 0) {
  initializeApp();
}

export const settleChallengeDeadlines = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "Asia/Singapore",
    region: "asia-southeast1",
  },
  withScheduledErrorReporting("settleChallengeDeadlines", async () => {
    await settleChallengeDeadlinesNow();
    // The premium-lapse grace deadline is a time instant that nothing writes
    // at, so it needs a sweep of its own — but it rides this existing schedule
    // rather than adding a second scheduled function, which keeps the deploy
    // surface to the one new trigger. It runs after settlement so a challenge
    // that just reached its target settles before anyone is evicted from it.
    await sweepChallengePremiumLapsesNow();
  }),
);

export async function settleChallengeDeadlinesNow(
  nowMs: number = Date.now(),
): Promise<ChallengeSettlementSweepResult> {
  return runChallengeSettlementSweep(getFirestore(), nowMs);
}

export async function sweepChallengePremiumLapsesNow(
  nowMs: number = Date.now(),
): Promise<PremiumLapseSweepResult> {
  return runChallengePremiumLapseSweep(getFirestore(), nowMs);
}
