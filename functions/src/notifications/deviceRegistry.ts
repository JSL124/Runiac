import { createHash } from "node:crypto";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { withCallableErrorReporting } from "../errors/withErrorReporting.js";

type CallableNotificationRequest = {
  readonly auth?: {
    readonly uid: string;
  };
  readonly data: unknown;
};

type NotificationPlatform = "android" | "ios" | "web";

type RegisterNotificationDevicePayload = {
  readonly token: string;
  readonly platform: NotificationPlatform;
  readonly appInstallationId: string;
  readonly now: string;
};

type UnregisterNotificationDevicePayload = {
  readonly token: string;
  readonly now: string;
};

export type NotificationDeviceMutationResult = {
  readonly status: "registered" | "disabled";
  readonly fingerprint: string;
};

if (getApps().length === 0) {
  initializeApp();
}

export const registerNotificationDevice = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("registerNotificationDevice", async (request: CallableNotificationRequest) =>
    registerNotificationDeviceForCallable(request, getFirestore())),
);

export const unregisterNotificationDevice = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("unregisterNotificationDevice", async (request: CallableNotificationRequest) =>
    unregisterNotificationDeviceForCallable(request, getFirestore())),
);

export async function registerNotificationDeviceForCallable(
  request: CallableNotificationRequest,
  firestore: Firestore,
): Promise<NotificationDeviceMutationResult> {
  const uid = authenticatedUid(request);
  const payload = parseRegisterPayload(request.data);
  const fingerprint = hashNotificationToken(payload.token);
  const tokenRef = firestore.doc(`notificationDevices/${uid}/tokens/${fingerprint}`);

  // An FCM token is per-device, not per-account: when a runner signs out and a
  // different runner signs in on the same phone, the new sign-in registers the
  // SAME token under a new uid while the previous owner's row is left
  // `enabled: true` (the client's `unregisterCurrentDevice()` deliberately
  // skips the remote unregister on an account switch, because it can only
  // name the token, and the server would resolve the caller from
  // `request.auth.uid` — i.e. the NEW owner — and disable the wrong row; see
  // that function's comment). Left alone, that stale row keeps receiving this
  // capsule's FCM push, so the previous owner's social activity ("X liked your
  // run") is drawn as a banner on a lock screen someone else is now using.
  // Registration is the only place that can safely resolve this: it is the
  // one moment we know a specific device now belongs to a specific uid, so
  // ownership transfers here rather than at send time. This also means every
  // sign-in repairs the row for already-shipped clients with no app update,
  // which is why this fix belongs in this callable and not in a client patch.
  await releaseTokenFromOtherOwners(firestore, uid, fingerprint, payload.now);

  await firestore.doc(`notificationDevices/${uid}`).set(
    {
      ownerUid: uid,
      updatedAt: payload.now,
    },
    { merge: true },
  );
  await tokenRef.set(
    {
      ownerUid: uid,
      tokenFingerprint: fingerprint,
      fcmToken: payload.token,
      platform: payload.platform,
      appInstallationId: payload.appInstallationId,
      enabled: true,
      registeredAt: payload.now,
      updatedAt: payload.now,
      disabledAt: null,
    },
    { merge: true },
  );

  return {
    status: "registered",
    fingerprint,
  };
}

export async function unregisterNotificationDeviceForCallable(
  request: CallableNotificationRequest,
  firestore: Firestore,
): Promise<NotificationDeviceMutationResult> {
  const uid = authenticatedUid(request);
  const payload = parseUnregisterPayload(request.data);
  const fingerprint = hashNotificationToken(payload.token);

  await firestore.doc(`notificationDevices/${uid}/tokens/${fingerprint}`).set(
    {
      ownerUid: uid,
      tokenFingerprint: fingerprint,
      enabled: false,
      updatedAt: payload.now,
      disabledAt: payload.now,
    },
    { merge: true },
  );

  return {
    status: "disabled",
    fingerprint,
  };
}

// Finds every `tokens` row under a DIFFERENT uid that shares this device's
// token fingerprint and disables it, so the device's push delivery follows
// its current owner.
//
// This is a single-field equality filter, not a multi-field composite query,
// so it needs no COMPOSITE index. It mirrors the collection-group pattern
// `friendsNicknameFanout.ts` already uses on `friends`/`friendRequests`/
// `blockedUsers` (`.where("uid", "==", uid)`) — and per `firestore.indexes.json`,
// those three each needed an explicit `fieldOverrides` entry enabling
// `COLLECTION_GROUP` query scope for their filtered field before the query
// would run in production (Firestore's automatic single-field indexes default
// to `COLLECTION` scope only). `tokens`/`tokenFingerprint` has no such entry
// yet, so the same override is very likely needed here too before deploy; see
// the capsule/handoff notes for this open item — it is a `firestore.indexes.json`
// change and out of this edit's scope.
//
// This must never fail the registration it is called from: an already-signed-
// in runner losing their OWN working device row because a stale row from a
// previous owner could not be released would be strictly worse than leaving
// that stale row alone for one more push. So every failure here is logged and
// swallowed, never rethrown.
async function releaseTokenFromOtherOwners(
  firestore: Firestore,
  callerUid: string,
  fingerprint: string,
  disabledAt: string,
): Promise<void> {
  try {
    const staleTokens = await firestore
      .collectionGroup("tokens")
      .where("tokenFingerprint", "==", fingerprint)
      .get();

    const releases = staleTokens.docs
      .filter((document) => document.ref.parent.parent?.id !== callerUid)
      .map((document) =>
        document.ref.set(
          {
            enabled: false,
            updatedAt: disabledAt,
            disabledAt,
          },
          { merge: true },
        ).catch((error: unknown) => {
          console.error("[deviceRegistry] failed to release a stale token row", document.ref.path, error);
        }));

    await Promise.all(releases);
  } catch (error) {
    console.error("[deviceRegistry] failed to look up other owners of a registering token", fingerprint, error);
  }
}

export function hashNotificationToken(token: string): string {
  if (token.length === 0) {
    throw new HttpsError("invalid-argument", "A notification token is required.");
  }

  return createHash("sha256").update(token, "utf8").digest("hex");
}

function authenticatedUid(request: CallableNotificationRequest): string {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication is required to manage notification devices.");
  }

  return uid;
}

function parseRegisterPayload(data: unknown): RegisterNotificationDevicePayload {
  const value = parseObject(data);
  const token = readRequiredString(value, "token");
  const appInstallationId = readRequiredString(value, "appInstallationId");
  const now = readRequiredIsoInstant(value, "now");
  const platform = readPlatform(value["platform"]);

  return {
    token,
    platform,
    appInstallationId,
    now,
  };
}

function parseUnregisterPayload(data: unknown): UnregisterNotificationDevicePayload {
  const value = parseObject(data);

  return {
    token: readRequiredString(value, "token"),
    now: readRequiredIsoInstant(value, "now"),
  };
}

function parseObject(data: unknown): Record<string, unknown> {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Notification device payload must be an object.");
  }

  return data;
}

function isRecord(data: unknown): data is Record<string, unknown> {
  return typeof data === "object" && data !== null && !Array.isArray(data);
}

function readRequiredString(data: Record<string, unknown>, field: string): string {
  const value = data[field];
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }

  return value;
}

function readRequiredIsoInstant(data: Record<string, unknown>, field: string): string {
  const value = readRequiredString(data, field);
  const date = new Date(value);
  if (Number.isNaN(date.getTime()) || date.toISOString() !== value) {
    throw new HttpsError("invalid-argument", `${field} must be an ISO-8601 UTC instant.`);
  }

  return value;
}

function readPlatform(value: unknown): NotificationPlatform {
  if (value === "android" || value === "ios" || value === "web") {
    return value;
  }

  throw new HttpsError("invalid-argument", "platform must be android, ios, or web.");
}
