// Feed engagement (like/comment) FCM push (WP2).
//
// This module adds a push send for the same event `engagementNotifications.ts`
// already writes to the inbox. It intentionally reuses that module's already-
// planned `FeedEngagementNotification` rather than re-deriving title/body/
// payload, and reuses the token lookup and invalid-token handling already
// proven by the scheduled-push path (`scheduledPushReaders.ts` /
// `scheduledPushMessagingAdapter.ts`) instead of inventing a second version of
// either.
//
// Deliberate trade-offs baked into this module (read before changing):
//   - No `notificationDeliveries` ledger row. The caller only invokes this
//     sender after the inbox writer's transactional create on the
//     deterministic `{postId}:{kind}:{actorUid}` key returned "written", so
//     that create is already the exactly-once guard. A second ledger here
//     would double the write cost for no added guarantee.
//   - Platform is deliberately NOT filtered. An iOS token cannot currently be
//     registered at all (see the capsule doc), so every enabled token here is
//     Android today, and this path needs no change when iOS registration is
//     enabled later.
//   - One bad token must never cost the others their push: an invalid-token
//     error disables only that one token document, and any other send error
//     is logged and swallowed, in both cases moving on to the remaining
//     devices. The whole function is additionally wrapped so it can never
//     throw to its caller (the emitter's count recompute has already
//     committed by the time this runs — see `engagementNotifications.ts`).

import { Timestamp, type Firestore } from "firebase-admin/firestore";
import { enabledDevices } from "../../notifications/scheduledPushReaders.js";
import type { NotificationDeviceRecord } from "../../notifications/types.js";
import type { FeedEngagementNotification } from "./engagementNotifications.js";

// Minimal structural port so tests can inject a fake without an emulator.
// `getMessaging()` from `firebase-admin/messaging` satisfies this shape
// directly, the same way `scheduledPushFirestore.ts`'s
// `NotificationMessagingSender` does.
export type FeedEngagementMessagingPort = {
  readonly send: (message: {
    readonly token: string;
    readonly notification: {
      readonly title: string;
      readonly body: string;
    };
    readonly data: Readonly<Record<string, string>>;
  }) => Promise<string>;
};

export async function sendFeedEngagementPush(
  firestore: Firestore,
  messaging: FeedEngagementMessagingPort,
  notification: FeedEngagementNotification,
  nowIso: string,
): Promise<void> {
  try {
    const tokensSnapshot = await firestore
      .collection("notificationDevices")
      .doc(notification.ownerUid)
      .collection("tokens")
      .where("enabled", "==", true)
      .get();

    const devices = enabledDevices(
      notification.ownerUid,
      tokensSnapshot.docs.map((document) => document.data()),
    );
    if (devices.length === 0) return; // Clean no-op: nothing registered.

    // Exactly the allowlisted kind/route/postId keys. All three are already
    // string-typed on `FeedEngagementNotificationPayload` (the notification
    // module's own allowlist), so this is a direct copy, not a conversion —
    // if that payload type ever widens to allow a non-string value, this is
    // the point that needs an explicit `String(...)` coercion before it
    // reaches FCM, which rejects non-string `data` values.
    const data: Readonly<Record<string, string>> = {
      kind: notification.payload.kind,
      route: notification.payload.route,
      postId: notification.payload.postId,
    };

    // `allSettled`, not `all`, is deliberate belt-and-braces on top of the
    // per-device try/catch inside `sendToOneDevice`: the stated guarantee is
    // that one device's failure can never affect another, so the fan-out
    // itself must not depend on every promise resolving. If some future edit
    // ever adds a throw path inside `sendToOneDevice` that isn't caught, an
    // `all` here would still let one rejection cut off devices whose sends are
    // still in flight (the exact P2 regression this settled semantics is
    // guarding against).
    await Promise.allSettled(
      devices.map((device) => sendToOneDevice(firestore, messaging, device, notification, data, nowIso)),
    );
  } catch (error) {
    // Belt and braces on top of the caller's own `safeEmit`: this sender must
    // never throw, full stop.
    console.error("[engagementPush] send failed", error);
  }
}

async function sendToOneDevice(
  firestore: Firestore,
  messaging: FeedEngagementMessagingPort,
  device: NotificationDeviceRecord,
  notification: FeedEngagementNotification,
  data: Readonly<Record<string, string>>,
  nowIso: string,
): Promise<void> {
  try {
    await messaging.send({
      token: device.fcmToken,
      notification: { title: notification.title, body: notification.body },
      data,
    });
  } catch (error) {
    if (isInvalidTokenError(error)) {
      // The disable write gets its own try/catch, separate from the one
      // guarding `messaging.send` above: without this, a transient Firestore
      // failure here would reject this device's promise, which — before the
      // `allSettled` fan-out above — used to reject the whole `Promise.all`
      // and return from the caller while the other devices' sends were still
      // in flight, and Cloud Functions may then freeze the instance and lose
      // them. A disable write that itself fails is logged and dropped; the
      // token stays enabled and gets another (harmless) attempt at the next
      // engagement event.
      try {
        await disableInvalidToken(firestore, device, nowIso);
      } catch (disableError) {
        console.error("[engagementPush] failed to disable invalid token", device.tokenFingerprint, disableError);
      }
      return;
    }
    // Any other send error (transient FCM failure, rate limit, ...) is logged
    // and swallowed here, per-device, so it cannot stop the remaining sends.
    console.error("[engagementPush] token send failed", device.tokenFingerprint, error);
  }
}

// Mirrors `notificationDevices/{uid}/tokens/{fp}` disable write in
// `scheduledPushMessagingAdapter.ts` exactly (same fields, same merge
// semantics). Not imported from there because that file is out of this
// capsule's edit scope; kept local rather than exported/shared to avoid
// touching it.
async function disableInvalidToken(
  firestore: Firestore,
  device: NotificationDeviceRecord,
  disabledAt: string,
): Promise<void> {
  await firestore
    .collection("notificationDevices")
    .doc(device.uid)
    .collection("tokens")
    .doc(device.tokenFingerprint)
    .set(
      {
        enabled: false,
        disabledAt,
        updatedAt: Timestamp.fromDate(new Date(disabledAt)),
      },
      { merge: true },
    );
}

function isInvalidTokenError(error: unknown): boolean {
  const code = errorCode(error);
  return code === "messaging/invalid-registration-token" || code === "messaging/registration-token-not-registered";
}

function errorCode(error: unknown): string {
  if (isRecord(error) && typeof error["code"] === "string") {
    return error["code"];
  }
  return "unknown";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
