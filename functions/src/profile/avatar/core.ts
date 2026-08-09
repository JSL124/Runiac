import { HttpsError } from "firebase-functions/v2/https";
import {
  buildAvatarDownloadUrl,
  isAvatarObjectPath,
  isOwnedAvatarStagingPath,
  newAvatarObjectPath,
} from "./avatarPaths.js";
import { validateAvatarPng } from "../../feed/png.js";
// Pure predicate, not a firebase-admin runtime import: accountStatus.ts's
// only firebase-admin reference is an `import type` (Firestore/Transaction),
// which tsc erases entirely, so this stays safe for core.ts to import.
// Reusing it (rather than re-declaring the suspended-status set here) is
// what keeps the pre-check and the in-transaction check from ever drifting
// to different blocking-status definitions.
import { assertAccountNotSuspended } from "../../security/accountStatus.js";

// Cache-Control is a cost lever only: Flutter's Image.network/NetworkImage
// ignores HTTP Cache-Control entirely (its ImageCache is in-memory only), so
// this only reduces redundant origin/CDN fetches. Deliberately not
// "immutable" — the object path is reused across an id's lifetime only once
// (a fresh id is always minted on replace), so there is no correctness
// requirement for immutability, only a cost one.
export const AVATAR_CACHE_CONTROL = "public, max-age=3600";

// A caller may replace their avatar at most once per this window. This is
// also the reason avatarUpdatedAt exists on userProfiles/{uid}: it doubles as
// the cooldown key, checked against ports.now() from inside the very
// transaction that would perform the next replace.
export const AVATAR_REPLACE_COOLDOWN_MS = 60_000;

// Distinct, stable machine-readable reason surfaced on HttpsError.details so
// a client can special-case "you must wait" without string-matching the
// human-readable message.
export const AVATAR_REPLACE_COOLDOWN_REASON = "avatar_replace_cooldown";

export type ProfileAvatarStoredObject = {
  readonly path: string;
  readonly contentType: string;
  readonly metadata: Readonly<Record<string, string>>;
  readonly bytes: Uint8Array;
};

export type ProfileAvatarProfileSnapshot = {
  readonly exists: boolean;
  readonly avatarObjectPath: string | undefined;
  readonly avatarPreviousObjectPath: string | undefined;
  // Milliseconds since epoch, already converted from whatever timestamp
  // representation Firestore hands back — core.ts never sees a Firestore
  // Timestamp type, so it stays free of a firebase-admin import.
  readonly avatarUpdatedAtMs: number | undefined;
};

export type ProfileAvatarSetFields = {
  readonly avatarUrl: string;
  readonly avatarObjectPath: string;
  readonly avatarPreviousObjectPath: string | undefined;
};

// A narrow, port-scoped handle for the single Firestore transaction each
// callable runs. Every method here is expected to be backed by reads/writes
// against the SAME underlying transaction — the adapter in callable.ts is
// responsible for that wiring; core.ts only sequences calls against this
// interface.
export interface ProfileAvatarTransactionPort {
  // Defence-in-depth (see accountStatus.ts): must be called before any write
  // in the transaction.
  assertCallerNotSuspended(): Promise<void>;
  readProfile(): Promise<ProfileAvatarProfileSnapshot>;
  writeSetAvatar(fields: ProfileAvatarSetFields): void;
  writeClearAvatar(): void;
}

export interface ProfileAvatarPorts {
  readObject(path: string): Promise<ProfileAvatarStoredObject | undefined>;
  // Contract mirrors functions/src/feed/publish/core.ts's copyCreateOnly:
  // create-only (ifGenerationMatch: 0) at the adapter layer, and a
  // precondition failure (the destination already exists) is swallowed by
  // the adapter, never rethrown here — core.ts always treats a resolved
  // promise as "the destination object exists with this content".
  copyCreateOnly(
    sourcePath: string,
    destinationPath: string,
    options: { readonly token: string; readonly cacheControl: string },
  ): Promise<void>;
  deleteObject(path: string): Promise<void>;
  newAvatarId(): string;
  newDownloadToken(): string;
  bucketName(): string;
  emulatorHost(): string | undefined;
  now(): number;
  // Plain (non-transactional) reads used ONLY for the cheap advisory
  // pre-check in setProfileAvatar, before the expensive Storage copy. Never
  // used to decide what gets written — see setProfileAvatar for why both
  // this and the transactional checks below must both exist.
  readAccountData(uid: string): Promise<Readonly<Record<string, unknown>> | undefined>;
  readProfileSnapshot(uid: string): Promise<ProfileAvatarProfileSnapshot>;
  runProfileTransaction<T>(uid: string, body: (tx: ProfileAvatarTransactionPort) => Promise<T>): Promise<T>;
}

export type ProfileAvatarCallableRequest = {
  readonly auth?: { readonly uid: string };
  readonly data: unknown;
};

export type SetProfileAvatarResult = { readonly avatarUrl: string };
export type ClearProfileAvatarResult = { readonly cleared: true };

export async function setProfileAvatar(
  request: ProfileAvatarCallableRequest,
  ports: ProfileAvatarPorts,
): Promise<SetProfileAvatarResult> {
  const uid = requireAuthUid(request);
  const { stagingPath } = parseSetProfileAvatarPayload(request.data);
  if (!isOwnedAvatarStagingPath(stagingPath, uid)) {
    throw new HttpsError("invalid-argument", "stagingPath is not an owned avatar staging path.");
  }

  const staged = await ports.readObject(stagingPath);
  if (staged === undefined || !isSafeAvatarStagingObject(staged, stagingPath, uid)) {
    throw new HttpsError("failed-precondition", "Staged avatar image is invalid.");
  }

  // Cheap advisory pre-check, BEFORE the expensive Storage copy below. The
  // cooldown's whole purpose is to throttle upload/copy abuse — a caller
  // retrying a call they already know will be rejected must not still mint
  // a fresh orphaned avatars/ object on every attempt. This is intentionally
  // racy (plain reads, no transaction): it is NOT the authoritative gate and
  // must never be simplified into being one. The in-transaction checks
  // further below are what actually serialise concurrent replaces and stay
  // the source of truth; this pre-check only short-circuits the common case
  // where the outcome is already certain, using the exact same assertions
  // (assertAccountNotSuspended, assertProfileReplaceAllowed) so a caller
  // cannot distinguish an early rejection from a late one. Do not delete
  // either half.
  assertAccountNotSuspended(await ports.readAccountData(uid));
  assertProfileReplaceAllowed(await ports.readProfileSnapshot(uid), ports.now());

  const id = ports.newAvatarId();
  const token = ports.newDownloadToken();
  const destinationPath = newAvatarObjectPath(id);
  const emulatorHost = ports.emulatorHost();
  const avatarUrl = buildAvatarDownloadUrl({
    bucket: ports.bucketName(),
    objectPath: destinationPath,
    token,
    ...(emulatorHost === undefined ? {} : { emulatorHost }),
  });

  // Promote before the transaction: the destination object must exist before
  // any Firestore document can point at it. copyCreateOnly's own contract
  // (see ProfileAvatarPorts) means this never throws for "already promoted".
  await ports.copyCreateOnly(stagingPath, destinationPath, { token, cacheControl: AVATAR_CACHE_CONTROL });

  const staleAvatarObjectPath = await ports.runProfileTransaction(uid, async (tx) => {
    // Authoritative: unlike the pre-check above, this runs inside the
    // transaction that actually performs the write, so it is what really
    // serialises two concurrent replace attempts. Never remove this in
    // favour of the pre-check — the pre-check alone is racy by design.
    await tx.assertCallerNotSuspended();
    const profile = await tx.readProfile();
    assertProfileReplaceAllowed(profile, ports.now());
    // The value ALREADY in avatarPreviousObjectPath (the generation before
    // the one still possibly live in an hourly leaderboard snapshot) is what
    // becomes safe to delete now — never the current object, which this same
    // write is about to demote into that slot.
    const staleObjectPath = profile.avatarPreviousObjectPath;
    tx.writeSetAvatar({
      avatarUrl,
      avatarObjectPath: destinationPath,
      avatarPreviousObjectPath: profile.avatarObjectPath,
    });
    return staleObjectPath;
  });

  // Best-effort, post-commit cleanup. Every path is re-validated immediately
  // before its delete call: a poisoned or foreign stored path is skipped
  // entirely rather than best-effort deleted, and neither delete is allowed
  // to fail this callable.
  await bestEffortDeleteAvatarObject(ports, staleAvatarObjectPath);
  await bestEffortDeleteStagingObject(ports, stagingPath, uid);

  return { avatarUrl };
}

export async function clearProfileAvatar(
  request: ProfileAvatarCallableRequest,
  ports: ProfileAvatarPorts,
): Promise<ClearProfileAvatarResult> {
  const uid = requireAuthUid(request);
  parseClearProfileAvatarPayload(request.data);

  const stored = await ports.runProfileTransaction(uid, async (tx) => {
    await tx.assertCallerNotSuspended();
    const profile = await tx.readProfile();
    if (!profile.exists) {
      throw new HttpsError("failed-precondition", "Profile is unavailable.");
    }
    tx.writeClearAvatar();
    return { avatarObjectPath: profile.avatarObjectPath, avatarPreviousObjectPath: profile.avatarPreviousObjectPath };
  });

  await bestEffortDeleteAvatarObject(ports, stored.avatarObjectPath);
  await bestEffortDeleteAvatarObject(ports, stored.avatarPreviousObjectPath);

  return { cleared: true };
}

// Shared by both the pre-check and the in-transaction check in
// setProfileAvatar, so the two can never throw different codes, messages, or
// details for the same underlying condition.
function assertProfileReplaceAllowed(profile: ProfileAvatarProfileSnapshot, nowMs: number): void {
  if (!profile.exists) {
    throw new HttpsError("failed-precondition", "Profile is unavailable.");
  }
  if (profile.avatarUpdatedAtMs !== undefined && nowMs - profile.avatarUpdatedAtMs < AVATAR_REPLACE_COOLDOWN_MS) {
    throw new HttpsError("failed-precondition", "Avatar was updated too recently. Try again shortly.", {
      reason: AVATAR_REPLACE_COOLDOWN_REASON,
    });
  }
}

function requireAuthUid(request: ProfileAvatarCallableRequest): string {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return uid;
}

function parseSetProfileAvatarPayload(data: unknown): { readonly stagingPath: string } {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "A payload object is required.");
  }
  const keys = Object.keys(data);
  if (keys.length !== 1 || keys[0] !== "stagingPath") {
    throw new HttpsError("invalid-argument", "Payload must contain exactly one field: stagingPath.");
  }
  const stagingPath = data["stagingPath"];
  if (typeof stagingPath !== "string" || stagingPath.length === 0) {
    throw new HttpsError("invalid-argument", "stagingPath must be a non-empty string.");
  }
  return { stagingPath };
}

function parseClearProfileAvatarPayload(data: unknown): void {
  if (data === undefined || data === null) return;
  if (!isRecord(data) || Object.keys(data).length > 0) {
    throw new HttpsError("invalid-argument", "clearProfileAvatar takes no payload fields.");
  }
}

function isSafeAvatarStagingObject(
  object: ProfileAvatarStoredObject,
  expectedPath: string,
  ownerUid: string,
): boolean {
  return (
    object.path === expectedPath &&
    object.contentType === "image/png" &&
    hasSafeAvatarStagingMetadata(object.metadata, ownerUid) &&
    validateAvatarPng(object.bytes).ok
  );
}

// Tolerates a Firebase-SDK-minted firebaseStorageDownloadTokens key exactly
// as functions/src/feed/publish/core.ts's hasSafeStagingMetadata does, so an
// uploader that let the client SDK mint its own token is not rejected.
function hasSafeAvatarStagingMetadata(metadata: Readonly<Record<string, string>>, ownerUid: string): boolean {
  const keys = Object.keys(metadata);
  const hasManagedDownloadToken =
    typeof metadata["firebaseStorageDownloadTokens"] === "string" &&
    metadata["firebaseStorageDownloadTokens"].length > 0;
  const hasExactKeys = keys.length === 1 || (keys.length === 2 && hasManagedDownloadToken);
  return hasExactKeys && metadata["ownerUid"] === ownerUid;
}

// Every delete target is re-validated immediately before the delete call —
// never trusted merely because it came from our own Firestore document. On
// mismatch, the delete is skipped entirely (not attempted, not reported as
// an error): a poisoned or foreign stored path must never be handed to a
// delete call. Never allowed to fail the callable itself.
async function bestEffortDeleteAvatarObject(ports: ProfileAvatarPorts, path: string | undefined): Promise<void> {
  if (path === undefined || !isAvatarObjectPath(path)) return;
  await bestEffortDelete(ports, path);
}

async function bestEffortDeleteStagingObject(ports: ProfileAvatarPorts, path: string, uid: string): Promise<void> {
  if (!isOwnedAvatarStagingPath(path, uid)) return;
  await bestEffortDelete(ports, path);
}

async function bestEffortDelete(ports: ProfileAvatarPorts, path: string): Promise<void> {
  try {
    await ports.deleteObject(path);
  } catch {
    // Best-effort only: a delete failure must never fail the callable. The
    // object either gets cleaned up on a later call or stays orphaned, which
    // is strictly safer than surfacing a false failure to the caller after
    // their Firestore fields already committed successfully.
  }
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
