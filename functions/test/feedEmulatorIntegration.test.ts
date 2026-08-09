import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { after, before, test } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, type Query } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

const projectId = "demo-runiac-feed";
const environment = {
  GCLOUD_PROJECT: projectId,
  FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9099",
  FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
  FUNCTIONS_EMULATOR_HOST: "127.0.0.1:5001",
  FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9199",
} as const;
const actorIds = ["task12-author", "task12-friend", "task12-other", "task12-nonfriend", "task12-basic"] as const;
const activityIds = ["task12-activity", "task12-cascade", "task12-basic-activity"] as const;
if (getApps().length === 0) initializeApp({ projectId, storageBucket: `${projectId}.appspot.com` });
const db = getFirestore();
const auth = getAuth();
const bucket = getStorage().bucket();
type Actor = { readonly uid: (typeof actorIds)[number]; readonly token: string };
type CallableResult = { readonly ok: true; readonly data: Readonly<Record<string, unknown>> } | { readonly ok: false; readonly status: string };

before(async () => {
  assert.deepEqual(process.env["GCLOUD_PROJECT"], environment.GCLOUD_PROJECT);
  for (const [key, value] of Object.entries(environment)) assert.equal(process.env[key], value);
  await clearFixture();
});

after(async () => {
  await clearFixture();
});

test("fails closed before a fixture process can mutate when project, Functions, or Storage guards differ", async () => {
  for (const [name, value] of [["GCLOUD_PROJECT", "runiac-fypp"], ["FUNCTIONS_EMULATOR_HOST", undefined], ["FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9198"]] as const) {
    const childEnvironment: NodeJS.ProcessEnv = { ...environment };
    if (value === undefined) delete childEnvironment[name]; else childEnvironment[name] = value;
    const result = spawnSync(process.execPath, [new URL("../src/feed/fixtures/cli.js", import.meta.url).pathname, "--scenario", "baseline"], {
      encoding: "utf8",
      env: childEnvironment,
    });
    assert.equal(result.status, 1, `${name} must terminate the fixture CLI before mutation`);
  }
  const fixtureState = await Promise.all([
    db.doc("activities/feed-fixture-activity").get(),
    db.doc("userProfiles/feed-fixture-author").get(),
    db.doc("users/feed-fixture-author/friends/feed-fixture-friend").get(),
  ]);
  assert.equal(fixtureState.every((snapshot) => !snapshot.exists), true);
});

test("publishes and protects a real Feed post across Auth, Firestore, Functions, and Storage", async () => {
  const author = await actor("task12-author");
  const friend = await actor("task12-friend");
  const other = await actor("task12-other");
  const nonfriend = await actor("task12-nonfriend");
  await setupProfiles();
  await acceptFriends(author.uid, friend.uid);
  await acceptFriends(author.uid, other.uid);
  await stageActivity(author.uid, "task12-activity");

  const published = await call(author, "publishActivityToFeed", publishData(author.uid, "task12-activity"));
  assert.equal(published.ok, true);
  if (!published.ok) return;
  const post = await db.doc("feedPosts/task12-activity").get();
  const finalPath = finalThumbnailPath(author.uid, "task12-activity");
  assert.equal(published.data["postId"], "task12-activity");
  assert.equal(post.get("status"), "published");
  assert.equal((await bucket.file(stagingPath(author.uid, "task12-activity")).exists())[0], false);
  assert.equal((await bucket.file(finalPath).exists())[0], true);

  for (const actorWithAccess of [author, friend]) {
    const thumbnail = await call(actorWithAccess, "readFeedThumbnail", { postId: "task12-activity" });
    assert.equal(thumbnail.ok, true);
    if (thumbnail.ok) assert.equal(thumbnail.data["generation"], post.get("thumbnailObjectGeneration"));
  }
  await assertDenied(nonfriend, "readFeedThumbnail", "task12-activity");

  await revokeFriends(author.uid, friend.uid);
  await assertDenied(friend, "readFeedThumbnail", "task12-activity");
  await acceptFriends(author.uid, friend.uid);
  await db.doc(`users/${friend.uid}/blockedUsers/${author.uid}`).set({ blockedUid: author.uid, createdAt: FieldValue.serverTimestamp() });
  await assertDenied(friend, "readFeedThumbnail", "task12-activity");
  await db.doc(`users/${friend.uid}/blockedUsers/${author.uid}`).delete();
  await db.doc(`users/${author.uid}/blockedUsers/${friend.uid}`).set({ blockedUid: friend.uid, createdAt: FieldValue.serverTimestamp() });
  await assertDenied(friend, "readFeedThumbnail", "task12-activity");
  await db.doc(`users/${author.uid}/blockedUsers/${friend.uid}`).delete();

  await db.doc(`feedPosts/task12-activity/likes/${friend.uid}`).set({ userUid: friend.uid, createdAt: FieldValue.serverTimestamp() });
  await db.doc("feedPosts/task12-activity/comments/task12-comment").set(comment(friend.uid));
  await waitFor(() => exactCounts("task12-activity", 1, 1));
  const reported = await call(friend, "reportFeedPost", { postId: "task12-activity" });
  assert.equal(reported.ok, true);
  await assertDenied(friend, "readFeedThumbnail", "task12-activity");
  assert.equal((await call(author, "readFeedThumbnail", { postId: "task12-activity" })).ok, true);
  assert.equal((await call(other, "readFeedThumbnail", { postId: "task12-activity" })).ok, true);

  // Suspension defence-in-depth (see accountStatus.ts): `other` is a real
  // friend of `author` and would otherwise be allowed to report this post
  // (proven by `friend`'s successful report above) — suspending the account
  // must now reject the same real callable with PERMISSION_DENIED, checked
  // in the onCall wrapper before the report-lifecycle core ever runs.
  await db.doc(`users/${other.uid}`).set({ accountStatus: "suspended" });
  const suspendedReport = await call(other, "reportFeedPost", { postId: "task12-activity" });
  assert.equal(suspendedReport.ok, false);
  if (!suspendedReport.ok) assert.equal(suspendedReport.status, "PERMISSION_DENIED");
  await db.doc(`users/${other.uid}`).delete();

  const deleted = await call(author, "deleteFeedPost", { postId: "task12-activity" });
  assert.equal(deleted.ok, true);
  await waitFor(() => postResidueAbsent(author.uid, "task12-activity"));
  assert.equal((await db.doc("activities/task12-activity").get()).exists, true);

  await stageActivity(author.uid, "task12-cascade");
  assert.equal((await call(author, "publishActivityToFeed", publishData(author.uid, "task12-cascade"))).ok, true);
  await db.doc("activities/task12-cascade").delete();
  await waitFor(() => postResidueAbsent(author.uid, "task12-cascade"));
});

test("rejects a Basic subscriber from publishing to Feed and writes nothing (premium entitlement gate)", async () => {
  const basic = await actor("task12-basic");
  await db.doc(`userProfiles/${basic.uid}`).set({ displayName: basic.uid, avatarInitials: "T12" });
  await db.doc(`users/${basic.uid}`).set({ subscriptionStatus: "basic" });
  await stageActivity(basic.uid, "task12-basic-activity");

  // The contract under test is "when shareRouteToFeed requires Premium, a
  // Basic subscriber is refused" — not whatever tier the shipped default
  // happens to carry. This test used to read the tier ambiently and so broke
  // when 4287e786 moved the default to "basic" to match production, even
  // though the gate itself never changed. Pinning the stored document keeps
  // the assertion about the mechanism and makes it survive a console flip in
  // either direction. loadFeatureAccessConfig re-reads config/featureAccess on
  // every call with no caching, so the next invocation observes this write,
  // and deepMerge over DEFAULT_FEATURE_ACCESS_CONFIG means only the one key
  // needs stating.
  await db.doc("config/featureAccess").set(
    { features: { shareRouteToFeed: { minimumTier: "premium", enabled: true } } },
    { merge: true },
  );

  try {
    const result = await call(basic, "publishActivityToFeed", publishData(basic.uid, "task12-basic-activity"));

    assert.equal(result.ok, false, "a Basic user must not be able to publish to Feed");
    if (!result.ok) assert.equal(result.status, "PERMISSION_DENIED");
    // The gate runs in the onCall wrapper before publishFeedActivity, so no post
    // document is created and the staging object is left intact (only a
    // successful publish promotes and deletes staging).
    assert.equal((await db.doc("feedPosts/task12-basic-activity").get()).exists, false);
    assert.equal((await bucket.file(stagingPath(basic.uid, "task12-basic-activity")).exists())[0], true);
  } finally {
    // In a finally block because leaving Premium pinned would silently change
    // what every later publish in this project is allowed to do.
    await db.doc("config/featureAccess").delete();
  }
});

async function actor(uid: (typeof actorIds)[number]): Promise<Actor> {
  const email = `${uid}@example.invalid`;
  await auth.createUser({ uid, email, password: "task12-password", displayName: uid });
  const response = await fetch("http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=task12", {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email, password: "task12-password", returnSecureToken: true }),
  });
  const body = asRecord(await response.json());
  assert.equal(response.ok, true);
  return { uid, token: stringAt(body, "idToken") };
}

async function setupProfiles(): Promise<void> {
  await Promise.all(actorIds.map((uid) => db.doc(`userProfiles/${uid}`).set({ displayName: uid, avatarInitials: "T12" })));
  // publishActivityToFeed enforces the shareRouteToFeed feature-access tier
  // server-side, reading users/{uid}.subscriptionStatus. That tier defaults to
  // "basic", so this Premium author document is not what makes the publish
  // path pass today — it is kept so the suite still exercises publishing if an
  // admin (or a future default) puts the key back behind Premium. The Basic
  // rejection test below does not rely on that: it pins the stored tier itself
  // rather than inheriting whichever default is current.
  await db.doc(`users/task12-author`).set({ subscriptionStatus: "premium" });
}

async function acceptFriends(left: string, right: string): Promise<void> {
  await Promise.all([db.doc(`users/${left}/friends/${right}`).set({ friendUid: right }), db.doc(`users/${right}/friends/${left}`).set({ friendUid: left })]);
}

async function revokeFriends(left: string, right: string): Promise<void> {
  await Promise.all([db.doc(`users/${left}/friends/${right}`).delete(), db.doc(`users/${right}/friends/${left}`).delete()]);
}

async function stageActivity(uid: string, activityId: string): Promise<void> {
  await db.doc(`activities/${activityId}`).set({ ownerUid: uid, status: "validated", validationStatus: "validated", endedAt: "2026-07-11T00:00:00.000Z", distanceMeters: 1000, durationSeconds: 600, averagePaceSecondsPerKm: 600 });
  await bucket.file(stagingPath(uid, activityId)).save(png(), { resumable: false, metadata: { contentType: "image/png", metadata: { ownerUid: uid, activityId, uploadId: "task12.png", firebaseStorageDownloadTokens: "managed-token" } } });
}

function publishData(uid: string, activityId: string): Readonly<Record<string, string>> { return { activityId, stagingPath: stagingPath(uid, activityId) }; }
function stagingPath(uid: string, activityId: string): string { return `feed-thumbnail-staging/${uid}/${activityId}/task12.png`; }
function finalThumbnailPath(uid: string, activityId: string): string { return `feed-thumbnails/${uid}/${activityId}/route-preview.png`; }
function comment(uid: string): Readonly<Record<string, unknown>> { return { authorUid: uid, authorDisplayName: uid, authorAvatarInitials: "T12", authorLevelLabel: "Level 3", body: "Synthetic encouragement.", createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }; }

async function call(actorValue: Actor, name: string, data: Readonly<Record<string, unknown>>): Promise<CallableResult> {
  const response = await fetch(`http://127.0.0.1:5001/${projectId}/asia-southeast1/${name}`, { method: "POST", headers: { authorization: `Bearer ${actorValue.token}`, "content-type": "application/json" }, body: JSON.stringify({ data }) });
  const body = asRecord(await response.json());
  if (response.ok) return { ok: true, data: asRecord(body["result"]) };
  return { ok: false, status: stringAt(asRecord(body["error"]), "status") };
}

async function assertDenied(actorValue: Actor, name: string, postId: string): Promise<void> {
  const result = await call(actorValue, name, { postId });
  assert.equal(result.ok, false);
  if (!result.ok) assert.equal(result.status, "PERMISSION_DENIED");
}

async function exactCounts(postId: string, likes: number, comments: number): Promise<boolean> {
  const snapshot = await db.doc(`feedPosts/${postId}`).get();
  return snapshot.get("likeCount") === likes && snapshot.get("commentCount") === comments;
}

async function postResidueAbsent(uid: string, postId: string): Promise<boolean> {
  const [post, likes, comments, reports, hidden, finalObject] = await Promise.all([
    db.doc(`feedPosts/${postId}`).get(), db.collection(`feedPosts/${postId}/likes`).get(), db.collection(`feedPosts/${postId}/comments`).get(), db.collection("reports").where("targetId", "==", postId).get(), db.doc(`users/task12-friend/hiddenFeedPosts/${postId}`).get(), bucket.file(finalThumbnailPath(uid, postId)).exists(),
  ]);
  return !post.exists && likes.empty && comments.empty && reports.empty && !hidden.exists && !finalObject[0];
}

async function waitFor(predicate: () => Promise<boolean>): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    if (await predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  assert.fail("Timed out waiting for bounded emulator convergence.");
}

async function clearFixture(): Promise<void> {
  for (const activityId of activityIds) {
    await Promise.all([
      deleteDocuments(db.collection(`feedPosts/${activityId}/likes`)),
      deleteDocuments(db.collection(`feedPosts/${activityId}/comments`)),
      deleteDocuments(db.collection("reports").where("targetId", "==", activityId)),
      ...actorIds.map((uid) => db.doc(`users/${uid}/hiddenFeedPosts/${activityId}`).delete()),
    ]);
    await Promise.all([db.doc(`feedPosts/${activityId}`).delete(), db.doc(`activities/${activityId}`).delete(), bucket.file(finalThumbnailPath("task12-author", activityId)).delete({ ignoreNotFound: true }), bucket.file(stagingPath("task12-author", activityId)).delete({ ignoreNotFound: true }), bucket.file(stagingPath("task12-basic", activityId)).delete({ ignoreNotFound: true })]);
  }
  for (const uid of actorIds) {
    await Promise.all(actorIds.filter((other) => other !== uid).flatMap((other) => [db.doc(`users/${uid}/friends/${other}`).delete(), db.doc(`users/${uid}/blockedUsers/${other}`).delete()]));
  }
  await Promise.all(actorIds.flatMap((uid) => [db.doc(`userProfiles/${uid}`).delete(), db.doc(`users/${uid}`).delete(), auth.deleteUser(uid).catch(() => undefined)]));
}

async function deleteDocuments(query: Query): Promise<void> {
  const snapshot = await query.get();
  await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
}

function asRecord(value: unknown): Readonly<Record<string, unknown>> {
  if (!isRecord(value)) assert.fail("Expected a JSON object.");
  return value;
}
function isRecord(value: unknown): value is Readonly<Record<string, unknown>> { return typeof value === "object" && value !== null && !Array.isArray(value); }
function stringAt(value: Readonly<Record<string, unknown>>, key: string): string { const result = value[key]; if (typeof result !== "string") assert.fail(`${key} must be a string.`); return result; }
function png(): Uint8Array { return Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10, ...chunk("IHDR", [0, 0, 4, 8, 0, 0, 2, 40, 16, 6, 0, 0, 0]), ...chunk("sBIT", [10, 10, 10, 10]), ...chunk("IDAT", [0]), ...chunk("IEND", [])]); }
function chunk(type: string, data: readonly number[]): number[] { const typeBytes = [...type].map((character) => character.charCodeAt(0)); return [...uint32(data.length), ...typeBytes, ...data, ...uint32(crc32([...typeBytes, ...data]))]; }
function uint32(value: number): number[] { return [(value >>> 24) & 255, (value >>> 16) & 255, (value >>> 8) & 255, value & 255]; }
function crc32(bytes: readonly number[]): number { let crc = 0xffff_ffff; for (const value of bytes) { crc ^= value; for (let bit = 0; bit < 8; bit += 1) crc = (crc & 1) === 1 ? (crc >>> 1) ^ 0xedb8_8320 : crc >>> 1; } return (crc ^ 0xffff_ffff) >>> 0; }
