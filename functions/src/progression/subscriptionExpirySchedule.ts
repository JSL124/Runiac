// Scheduled premium subscription expiry sweep (same registration style as
// `settleChallengeDeadlines` / `dispatchScheduledPushNotifications`: a thin
// `onSchedule` wrapper delegating to a testable, dependency-injected core).
// Runs once a day; repeated invocations are idempotent — a user already
// downgraded to `basic` no longer matches the sweep's query.

import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  runSubscriptionExpirySweep,
  type SubscriptionExpirySweepResult,
} from "./subscriptionExpiryCore.js";
import { withScheduledErrorReporting } from "../errors/withErrorReporting.js";
import { scheduledAutomationEnabled } from "../config/automationGate.js";

if (getApps().length === 0) {
  initializeApp();
}

export const expireSubscriptions = onSchedule(
  {
    schedule: "every day 03:00",
    timeZone: "Asia/Singapore",
    region: "asia-southeast1",
  },
  withScheduledErrorReporting("expireSubscriptions", async () => {
    // Gate the schedule wrapper only — expireSubscriptionsNow() and any
    // manual admin-triggered path stay reachable while this sweep is
    // paused, so an admin can always force the sweep manually.
    if (
      !(await scheduledAutomationEnabled(
        getFirestore(),
        "subscriptionExpirySweep",
        "expireSubscriptions",
      ))
    ) {
      return;
    }
    await expireSubscriptionsNow();
  }),
);

export async function expireSubscriptionsNow(
  nowMs: number = Date.now(),
): Promise<SubscriptionExpirySweepResult> {
  return runSubscriptionExpirySweep(getFirestore(), nowMs);
}
