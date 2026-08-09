import { randomUUID } from "node:crypto";
import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, type DocumentSnapshot, type Firestore, type Transaction } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { onCall } from "firebase-functions/v2/https";
import {
  clearProfileAvatar as clearProfileAvatarCore,
  setProfileAvatar as setProfileAvatarCore,
  type ProfileAvatarCallableRequest,
  type ProfileAvatarPorts,
  type ProfileAvatarProfileSnapshot,
  type ProfileAvatarStoredObject,
  type ProfileAvatarTransactionPort,
} from "./core.js";
import { withCallableErrorReporting } from "../../errors/withErrorReporting.js";
import { assertCallerAccountNotSuspendedInTransaction } from "../../security/accountStatus.js";
import { shouldEnforceAppCheck } from "../../security/appCheck.js";

if (getApps().length === 0) initializeApp();

export const setProfileAvatar = onCall(
  { region: "asia-southeast1", enforceAppCheck: shouldEnforceAppCheck() },
  withCallableErrorReporting("setProfileAvatar", async (request: ProfileAvatarCallableRequest) =>
    setProfileAvatarCore(normalizeRequest(request), createProfileAvatarPorts())),
);

export const clearProfileAvatar = onCall(
  { region: "asia-southeast1", enforceAppCheck: shouldEnforceAppCheck() },
  withCallableErrorReporting("clearProfileAvatar", async (request: ProfileAvatarCallableRequest) =>
    clearProfileAvatarCore(normalizeRequest(request), createProfileAvatarPorts())),
);

function normalizeRequest(request: ProfileAvatarCallableRequest): ProfileAvatarCallableRequest {
  return request.auth === undefined
    ? { data: request.data }
    : { auth: { uid: request.auth.uid }, data: request.data };
}

export function createProfileAvatarPorts(firestore: Firestore = getFirestore()): ProfileAvatarPorts {
  const bucket = getStorage().bucket();
  return {
    async readObject(path) {
      return readStoredAvatarObject(bucket, path);
    },
    async copyCreateOnly(sourcePath, destinationPath, options) {
      try {
        await bucket.file(sourcePath).copy(bucket.file(destinationPath), {
          contentType: "image/png",
          cacheControl: options.cacheControl,
          metadata: { firebaseStorageDownloadTokens: options.token },
          preconditionOpts: { ifGenerationMatch: 0 },
        });
      } catch (error: unknown) {
        if (!isPreconditionFailure(error)) throw error;
      }
    },
    async deleteObject(path) {
      await bucket.file(path).delete({ ignoreNotFound: true });
    },
    newAvatarId() {
      return randomUUID().replace(/-/g, "");
    },
    newDownloadToken() {
      return randomUUID();
    },
    bucketName() {
      return bucket.name;
    },
    emulatorHost() {
      const host = process.env["FIREBASE_STORAGE_EMULATOR_HOST"];
      return typeof host === "string" && host.length > 0 ? host : undefined;
    },
    now() {
      return Date.now();
    },
    async readAccountData(uid) {
      const snapshot = await firestore.doc(`users/${uid}`).get();
      return snapshot.data();
    },
    async readProfileSnapshot(uid) {
      const snapshot = await firestore.doc(`userProfiles/${uid}`).get();
      return toProfileSnapshot(snapshot);
    },
    async runProfileTransaction(uid, body) {
      return firestore.runTransaction(async (transaction) => body(profileTransactionPort(firestore, transaction, uid)));
    },
  };
}

function profileTransactionPort(
  firestore: Firestore,
  transaction: Transaction,
  uid: string,
): ProfileAvatarTransactionPort {
  const profileRef = firestore.doc(`userProfiles/${uid}`);
  return {
    async assertCallerNotSuspended() {
      // Defence-in-depth (see accountStatus.ts): this transaction never
      // otherwise reads the caller's own users/{uid} doc.
      await assertCallerAccountNotSuspendedInTransaction(transaction, firestore, uid);
    },
    async readProfile(): Promise<ProfileAvatarProfileSnapshot> {
      const snapshot = await transaction.get(profileRef);
      return toProfileSnapshot(snapshot);
    },
    writeSetAvatar(fields) {
      transaction.update(profileRef, {
        avatarUrl: fields.avatarUrl,
        avatarObjectPath: fields.avatarObjectPath,
        avatarPreviousObjectPath: fields.avatarPreviousObjectPath ?? FieldValue.delete(),
        avatarUpdatedAt: FieldValue.serverTimestamp(),
      });
    },
    writeClearAvatar() {
      transaction.update(profileRef, {
        avatarUrl: FieldValue.delete(),
        avatarObjectPath: FieldValue.delete(),
        avatarPreviousObjectPath: FieldValue.delete(),
        avatarUpdatedAt: FieldValue.delete(),
      });
    },
  };
}

async function readStoredAvatarObject(
  bucket: ReturnType<ReturnType<typeof getStorage>["bucket"]>,
  path: string,
): Promise<ProfileAvatarStoredObject | undefined> {
  const file = bucket.file(path);
  const [exists] = await file.exists();
  if (!exists) return undefined;
  const [metadata] = await file.getMetadata();
  const [bytes] = await file.download();
  return {
    path,
    contentType: metadata.contentType ?? "",
    metadata: stringMap(metadata.metadata),
    bytes,
  };
}

// Shared by the transactional readProfile and the plain readProfileSnapshot
// pre-check read, so the two can never diverge in how they interpret the
// same document shape.
function toProfileSnapshot(snapshot: DocumentSnapshot): ProfileAvatarProfileSnapshot {
  const data = snapshot.data();
  return {
    exists: snapshot.exists,
    avatarObjectPath: stringField(data, "avatarObjectPath"),
    avatarPreviousObjectPath: stringField(data, "avatarPreviousObjectPath"),
    avatarUpdatedAtMs: timestampMillis(data?.["avatarUpdatedAt"]),
  };
}

function stringField(data: Record<string, unknown> | undefined, key: string): string | undefined {
  const value = data?.[key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function timestampMillis(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (isRecord(value) && typeof value["toMillis"] === "function") {
    return (value["toMillis"] as () => number).call(value);
  }
  return undefined;
}

function stringMap(value: unknown): Readonly<Record<string, string>> {
  if (!isRecord(value)) return {};
  return Object.fromEntries(Object.entries(value).filter((entry): entry is [string, string] => typeof entry[1] === "string"));
}

function isPreconditionFailure(error: unknown): boolean {
  return isRecord(error) && (error["code"] === 409 || error["code"] === 412);
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
