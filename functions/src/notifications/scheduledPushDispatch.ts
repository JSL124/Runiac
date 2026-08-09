import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  dispatchScheduledPushNotificationsForUsers,
  type DispatchResult,
  type ScheduledPushDependencies,
} from "./scheduledPushFirestore.js";
import { withScheduledErrorReporting } from "../errors/withErrorReporting.js";
import { scheduledAutomationEnabled } from "../config/automationGate.js";

if (getApps().length === 0) {
  initializeApp();
}

export const dispatchScheduledPushNotifications = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "Asia/Singapore",
    region: "asia-southeast1",
  },
  withScheduledErrorReporting("dispatchScheduledPushNotifications", async () => {
    const firestore = getFirestore();
    // Gate the schedule wrapper only — dispatchScheduledPushNotificationsNow()
    // and any manual admin-triggered path stay reachable while this sweep is
    // paused, so an admin can always force dispatch manually.
    if (
      !(await scheduledAutomationEnabled(
        firestore,
        "pushNotificationDispatch",
        "dispatchScheduledPushNotifications",
      ))
    ) {
      return;
    }
    await dispatchScheduledPushNotificationsNow({
      firestore,
      messaging: getMessaging(),
    });
  }),
);

export async function dispatchScheduledPushNotificationsNow(
  dependencies: ScheduledPushDependencies,
  now: string = new Date().toISOString(),
): Promise<DispatchResult> {
  return dispatchScheduledPushNotificationsForUsers(dependencies, now);
}
