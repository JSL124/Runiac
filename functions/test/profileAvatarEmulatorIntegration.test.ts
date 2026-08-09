import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import {
  callEmulatorCallable,
  createEmulatorActor,
  objectPathFromEmulatorUrl,
  stageAvatarPngObject,
  stringAt,
  tokenFromEmulatorUrl,
  type CallableResult,
  type EmulatorActor,
} from "./helpers/avatarEmulatorHelpers.js";

const projectId = "demo-runiac-feed";
const environment = {
  GCLOUD_PROJECT: projectId,
  FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9099",
  FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
  FUNCTIONS_EMULATOR_HOST: "127.0.0.1:5001",
  FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9199",
} as const;
const uid = "task14-avatar-owner";
if (getApps().length === 0) initializeApp({ projectId, storageBucket: `${projectId}.appspot.com` });
const db = getFirestore();
const auth = getAuth();
const bucket = getStorage().bucket();
type Actor = EmulatorActor;

before(async () => {
  for (const [key, value] of Object.entries(environment)) assert.equal(process.env[key], value);
  await cleanup();
});

after(async () => {
  await cleanup();
});

test("promotes a staged avatar PNG to a real fetchable avatars/ object with expected metadata", async () => {
  const actor = await createActor(uid);
  await db.doc(`userProfiles/${uid}`).set({ displayName: uid, avatarInitials: "T14" });
  const stagingPath = `avatar-staging/${uid}/upload-1.png`;
  await stageAvatarPng(stagingPath);

  const result = await call(actor, "setProfileAvatar", { stagingPath });
  assert.equal(result.ok, true);
  if (!result.ok) return;
  const avatarUrl = stringAt(result.data, "avatarUrl");
  const objectPath = objectPathFromEmulatorUrl(avatarUrl);
  const token = tokenFromEmulatorUrl(avatarUrl);

  const [exists] = await bucket.file(objectPath).exists();
  assert.equal(exists, true);
  const [metadata] = await bucket.file(objectPath).getMetadata();
  assert.equal(metadata.contentType, "image/png");
  assert.equal(metadata.cacheControl, "public, max-age=3600");
  assert.equal(metadata.metadata?.["firebaseStorageDownloadTokens"], token);

  const fetched = await fetch(avatarUrl);
  assert.equal(fetched.ok, true);
  const bytes = new Uint8Array(await fetched.arrayBuffer());
  assert.equal(bytes.length > 0, true);

  assert.equal((await bucket.file(stagingPath).exists())[0], false);

  const profile = await db.doc(`userProfiles/${uid}`).get();
  assert.equal(profile.get("avatarUrl"), avatarUrl);
  assert.equal(profile.get("avatarObjectPath"), objectPath);
  assert.equal(profile.get("avatarPreviousObjectPath"), undefined);
});

test("a replace keeps exactly two generations under avatars/ and removes the third-back one, and clear leaves zero", async () => {
  const replaceUid = "task14-avatar-replace";
  const actor = await createActor(replaceUid);
  await db.doc(`userProfiles/${replaceUid}`).set({ displayName: replaceUid, avatarInitials: "T14" });

  const first = await uploadAndPromote(actor, replaceUid, "upload-a.png");
  await backdateCooldown(replaceUid);
  const second = await uploadAndPromote(actor, replaceUid, "upload-b.png");

  // After the second upload: current = second, previous = first. Nothing has
  // been deleted yet because the first generation has nothing before it.
  assert.equal((await bucket.file(first).exists())[0], true);
  assert.equal((await bucket.file(second).exists())[0], true);
  let profile = await db.doc(`userProfiles/${replaceUid}`).get();
  assert.equal(profile.get("avatarObjectPath"), second);
  assert.equal(profile.get("avatarPreviousObjectPath"), first);

  await backdateCooldown(replaceUid);
  const third = await uploadAndPromote(actor, replaceUid, "upload-c.png");

  // After the third upload: current = third, previous = second, and the
  // generation two replaces back (first) must now be gone.
  assert.equal((await bucket.file(first).exists())[0], false);
  assert.equal((await bucket.file(second).exists())[0], true);
  assert.equal((await bucket.file(third).exists())[0], true);
  profile = await db.doc(`userProfiles/${replaceUid}`).get();
  assert.equal(profile.get("avatarObjectPath"), third);
  assert.equal(profile.get("avatarPreviousObjectPath"), second);

  const cleared = await call(actor, "clearProfileAvatar", {});
  assert.equal(cleared.ok, true);
  assert.equal((await bucket.file(second).exists())[0], false);
  assert.equal((await bucket.file(third).exists())[0], false);
  profile = await db.doc(`userProfiles/${replaceUid}`).get();
  assert.equal(profile.get("avatarUrl"), undefined);
  assert.equal(profile.get("avatarObjectPath"), undefined);
  assert.equal(profile.get("avatarPreviousObjectPath"), undefined);
  assert.equal(profile.get("avatarUpdatedAt"), undefined);

  await auth.deleteUser(replaceUid).catch(() => undefined);
  await db.doc(`userProfiles/${replaceUid}`).delete();
});

async function uploadAndPromote(actor: Actor, ownerUid: string, uploadName: string): Promise<string> {
  const stagingPath = `avatar-staging/${ownerUid}/${uploadName}`;
  await stageAvatarPng(stagingPath);
  const result = await call(actor, "setProfileAvatar", { stagingPath });
  assert.equal(result.ok, true, `setProfileAvatar failed for ${uploadName}`);
  if (!result.ok) throw new Error("unreachable");
  return objectPathFromEmulatorUrl(stringAt(result.data, "avatarUrl"));
}

async function backdateCooldown(ownerUid: string): Promise<void> {
  // Real-time cooldown enforcement (60s) is exercised by the fake-port unit
  // tests; a real emulator test backdates the stored timestamp directly via
  // the Admin SDK (which bypasses Firestore Rules entirely) instead of
  // sleeping in wall-clock time.
  await db.doc(`userProfiles/${ownerUid}`).update({
    avatarUpdatedAt: Timestamp.fromMillis(Date.now() - 120_000),
  });
}

async function stageAvatarPng(path: string): Promise<void> {
  await stageAvatarPngObject(bucket, path, uidFromStagingPath(path));
}

function uidFromStagingPath(path: string): string {
  const parts = path.split("/");
  const owner = parts[1];
  assert.ok(owner !== undefined);
  return owner;
}

async function createActor(actorUid: string): Promise<Actor> {
  return createEmulatorActor(auth, actorUid, { authEmulatorOrigin: "http://127.0.0.1:9099", signInKey: "task14" });
}

async function call(actor: Actor, name: string, data: Readonly<Record<string, unknown>>): Promise<CallableResult> {
  return callEmulatorCallable({ functionsOrigin: "http://127.0.0.1:5001", projectId, region: "asia-southeast1" }, name, actor, data);
}

async function cleanup(): Promise<void> {
  for (const ownerUid of [uid, "task14-avatar-replace"]) {
    await db.doc(`userProfiles/${ownerUid}`).delete().catch(() => undefined);
    await auth.deleteUser(ownerUid).catch(() => undefined);
    const [files] = await bucket.getFiles({ prefix: `avatar-staging/${ownerUid}/` });
    await Promise.all(files.map((file) => file.delete({ ignoreNotFound: true })));
  }
}

