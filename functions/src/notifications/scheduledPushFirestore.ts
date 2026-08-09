import type { Firestore } from "firebase-admin/firestore";
import {
  planNotificationDispatches,
  sendNotificationDispatches,
} from "./dispatchPlanner.js";
import { firestoreMessagingAdapter } from "./scheduledPushMessagingAdapter.js";
import {
  completedWorkoutIds,
  enabledDevices,
  notificationPreferences,
  plannedWorkouts,
  streakState,
} from "./scheduledPushReaders.js";

export type ScheduledPushDependencies = {
  readonly firestore: Firestore;
  readonly messaging: NotificationMessagingSender;
};

export type NotificationMessagingSender = {
  readonly send: (message: {
    readonly token: string;
    readonly notification: {
      readonly title: string;
      readonly body: string;
    };
    readonly data: Readonly<Record<string, string>>;
  }) => Promise<string>;
};

export type DispatchResult = {
  readonly usersScanned: number;
  readonly dispatchesPlanned: number;
  readonly sendsAttempted: number;
};

export async function dispatchScheduledPushNotificationsForUsers(
  dependencies: ScheduledPushDependencies,
  now: string,
): Promise<DispatchResult> {
  const users = await dependencies.firestore.collection("notificationDevices").get();
  let dispatchesPlanned = 0;
  let sendsAttempted = 0;

  for (const user of users.docs) {
    const uid = user.id;
    const [
      planSnapshot,
      progressSnapshot,
      profileSnapshot,
      preferenceSnapshot,
      deviceSnapshots,
      sentDeliverySnapshots,
    ] = await Promise.all([
      dependencies.firestore.collection("generatedPlans").doc(uid).get(),
      dependencies.firestore.collection("planProgress").doc(uid).get(),
      dependencies.firestore.collection("userProfiles").doc(uid).get(),
      dependencies.firestore.collection("notificationPreferences").doc(uid).get(),
      dependencies.firestore
        .collection("notificationDevices")
        .doc(uid)
        .collection("tokens")
        .where("enabled", "==", true)
        .get(),
      dependencies.firestore
        .collection("notificationDeliveries")
        .where("ownerUid", "==", uid)
        .where("status", "==", "sent")
        .get(),
    ]);
    const devices = enabledDevices(uid, deviceSnapshots.docs.map((document) => document.data()));
    if (devices.length === 0) {
      continue;
    }

    const dispatches = planNotificationDispatches({
      now,
      uid,
      notificationPreferences: notificationPreferences(preferenceSnapshot.data(), profileSnapshot.data()),
      plannedWorkouts: plannedWorkouts(planSnapshot.data()),
      completedWorkoutIds: completedWorkoutIds(progressSnapshot.data()),
      streakState: streakState(profileSnapshot.data()),
    });
    dispatchesPlanned += dispatches.length;

    const sentDeliveryKeys = new Set<string>(sentDeliverySnapshots.docs.map((document) => document.id));
    const results = await sendNotificationDispatches({
      dispatches,
      devices,
      adapter: firestoreMessagingAdapter(dependencies, now),
      sentDeliveryKeys,
      now,
    });
    sendsAttempted += results.filter((result) => result.status !== "skipped-duplicate").length;
  }

  return {
    usersScanned: users.size,
    dispatchesPlanned,
    sendsAttempted,
  };
}
