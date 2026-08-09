import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth, type DecodedIdToken } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import type { CallableRequest } from "firebase-functions/v2/https";
import {
  createRunnerPublicProfilePorts,
  getRunnerPublicProfile as getRunnerPublicProfileCallable,
} from "../src/profile/publicProfile/callable.js";
import { getRunnerPublicProfile } from "../src/profile/publicProfile/core.js";
import { canonicalizeNickname, nicknameIndexKey } from "../src/friends/nickname.js";
import { buildAvatarDownloadUrl } from "../src/profile/avatar/avatarPaths.js";
import {
  callEmulatorCallable,
  createEmulatorActor,
  stageAvatarPngObject,
  stringAt,
  type EmulatorActor,
} from "./helpers/avatarEmulatorHelpers.js";

const PROJECT_ID = "runiac-functions-test";
const FUNCTIONS_ORIGIN = "http://127.0.0.1:5001";
const AUTH_EMULATOR_ORIGIN = "http://127.0.0.1:9099";

/**
 * Integration coverage for `getRunnerPublicProfile` against the Firestore
 * emulator, through the REAL ports the deployed callable uses.
 *
 * The core unit test fakes the ports, so it can only prove the decision
 * rules. This proves the wiring the unit test cannot: that the ports read
 * `userProfiles/{uid}`, `users/{uid}`, `users/{uid}/challengeBadges`, and
 * `users/{a}/blockedUsers/{b}` — the exact paths the rest of the app writes.
 */
const viewer = "rpp-viewer";
const runner = "rpp-runner";
const blocker = "rpp-blocker";
const suspended = "rpp-suspended";
// The uid-addressed form's fixture cast: a friend, a pending friend request,
// a search-discoverable stranger, a challenge lobby co-member, and a plain
// stranger with none of the above.
const friendUid = "rpp-friend";
const requestedUid = "rpp-requested";
const discoverableUid = "rpp-discoverable";
const comemberUid = "rpp-comember";
const strangerUid = "rpp-stranger";
const uidFormUids = [friendUid, requestedUid, discoverableUid, comemberUid, strangerUid] as const;
const seededUids = [viewer, runner, blocker, suspended, ...uidFormUids] as const;
const snapshotId = "monthly_jurong-east_tier_03_2026-07";
const buildId = "build-2026-07-26T09";
const entry = (rankLabel: string, build: string = buildId) => ({ snapshotId, rankLabel, buildId: build });
const rankIds = ["rpp-rank-runner", "rpp-rank-blocker", "rpp-rank-suspended", "rpp-rank-viewer", "rpp-rank-duplicate"] as const;
const challengeId = "rpp-challenge";
// The discoverable stranger's nickname triple, computed the same way the
// nickname claim pipeline computes it — never hand-written, so the fixture
// can never drift from what `socialProfile()` actually recomputes.
const discoverableNickname = "Sprinter_disco";
const discoverableCanonical = canonicalizeNickname(discoverableNickname);
const discoverableIndexKey = nicknameIndexKey(discoverableCanonical);

if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID, storageBucket: `${PROJECT_ID}.appspot.com` });
const db = getFirestore();
const ports = createRunnerPublicProfilePorts(db);
const bucket = getStorage().bucket();

before(async () => {
  // Fail closed: this suite writes real documents, so it must never run
  // against anything but the emulator.
  assert.notEqual(process.env["FIRESTORE_EMULATOR_HOST"], undefined, "FIRESTORE_EMULATOR_HOST must be set");
  await clearFixture();
  await db.doc(`userProfiles/${runner}`).set({
    displayName: "Jinseo",
    nickname: "Jinseo_main",
    avatarInitials: "JI",
    locationLabel: "Jurong East, Singapore",
    levelLabel: "Level 8",
    level: 8,
    levelProgressPercent: 97.5,
    totalXp: 780,
    nextLevelXp: 800,
    xpToNextLevel: 20,
    divisionKey: "tier_03",
    divisionLabel: "Silver League",
    longestStreakLabel: "4 days",
    totalDistanceLabel: "69.8 km",
    // Private half of the same document; must never reach a viewer.
    fullName: "Jinseo Lee",
    dateOfBirth: "2000-01-01",
    ageYears: 26,
    weightKg: 68.5,
  });
  await db.doc(`users/${runner}`).set({ subscriptionStatus: "premium" });
  await db.doc(`users/${runner}/challengeBadges/10K`).set({ tierId: "10K" });
  await db.doc(`users/${runner}/challengeBadges/250K`).set({ tierId: "250K" });
  await db.doc(`userProfiles/${viewer}`).set({ displayName: "Viewer", avatarInitials: "VI", locationLabel: "Bedok, Singapore" });
  await db.doc(`userProfiles/${blocker}`).set({ displayName: "Blocker", avatarInitials: "BL", locationLabel: "Bedok, Singapore" });
  await db.doc(`users/${blocker}/blockedUsers/${viewer}`).set({ createdAt: new Date(0) });
  await db.doc(`userProfiles/${suspended}`).set({ displayName: "Suspended", avatarInitials: "SU", locationLabel: "Bedok, Singapore" });
  await db.doc(`users/${suspended}`).set({ accountStatus: "suspended" });
  // The backend-written rank projection: the only place a leaderboard entry
  // maps back to a uid. Shaped exactly like `monthlyLeaderboardWriter` writes it.
  await db.doc("leaderboardUserRanks/rpp-rank-runner").set({ ownerUid: runner, snapshotId, buildId, rankLabel: "#3", periodKey: "2026-07", regionId: "jurong-east", divisionKey: "tier_03" });
  await db.doc("leaderboardUserRanks/rpp-rank-blocker").set({ ownerUid: blocker, snapshotId, buildId, rankLabel: "#4", periodKey: "2026-07", regionId: "jurong-east", divisionKey: "tier_03" });
  await db.doc("leaderboardUserRanks/rpp-rank-suspended").set({ ownerUid: suspended, snapshotId, buildId, rankLabel: "#5", periodKey: "2026-07", regionId: "jurong-east", divisionKey: "tier_03" });
  await db.doc("leaderboardUserRanks/rpp-rank-viewer").set({ ownerUid: viewer, snapshotId, buildId, rankLabel: "#6", periodKey: "2026-07", regionId: "jurong-east", divisionKey: "tier_03" });

  // Fixtures for the uid-addressed request form: a friend, a pending friend
  // request, a search-discoverable stranger, a challenge co-member, and a
  // plain stranger with no edge, roster membership, or discovery flag.
  await db.doc(`userProfiles/${friendUid}`).set({ displayName: "Friend Runner", avatarInitials: "FR", locationLabel: "Bedok, Singapore" });
  await db.doc(`userProfiles/${requestedUid}`).set({ displayName: "Requested Runner", avatarInitials: "RQ", locationLabel: "Bedok, Singapore" });
  await db.doc(`userProfiles/${discoverableUid}`).set({
    displayName: "Discoverable Runner",
    avatarInitials: "DI",
    locationLabel: "Bedok, Singapore",
    socialDiscoveryStatus: "active",
    nickname: discoverableNickname,
    nicknameCanonical: discoverableCanonical,
    nicknameIndexKey: discoverableIndexKey,
  });
  await db.doc(`userProfiles/${comemberUid}`).set({ displayName: "Co-member Runner", avatarInitials: "CM", locationLabel: "Bedok, Singapore" });
  await db.doc(`userProfiles/${strangerUid}`).set({ displayName: "Stranger Runner", avatarInitials: "ST", locationLabel: "Bedok, Singapore" });

  await db.doc(`users/${viewer}/friends/${friendUid}`).set({ createdAt: new Date(0) });
  await db.doc(`users/${viewer}/friendRequests/${requestedUid}`).set({ createdAt: new Date(0) });

  await db.doc(`challengeSlots/${viewer}`).set({ challengeId });
  await db.doc(`challengeInstances/${challengeId}`).set({ rosterUids: [viewer, comemberUid] });
});

after(async () => {
  await clearFixture();
});

describe("Runner public profile emulator integration", () => {
  it("projects a real runner document, account tier, and earned badges", async () => {
    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#3") }, ports);

    assert.equal(profile.displayName, "Jinseo_main");
    assert.equal(profile.avatarInitials, "JI");
    assert.equal(profile.regionLabel, "Jurong East, Singapore");
    assert.equal(profile.level, 8);
    assert.equal(profile.levelProgressPercent, 97.5);
    assert.equal(profile.xpToNextLevel, 20);
    assert.equal(profile.longestStreakLabel, "4 days");
    assert.equal(profile.totalDistanceLabel, "69.8 km");
    assert.equal(profile.subscriptionStatusLabel, "Premium");
    assert.deepEqual([...profile.ownedBadgeTierIds].sort(), ["10K", "250K"]);
  });

  it("leaves the private half of the stored document behind", async () => {
    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#3") }, ports);
    const serialized = JSON.stringify(profile);

    for (const privateValue of ["Jinseo Lee", "2000-01-01", "68.5", "26"]) {
      assert.equal(serialized.includes(privateValue), false, `${privateValue} must not be projected`);
    }
    for (const privateKey of ["fullName", "dateOfBirth", "ageYears", "weightKg"]) {
      assert.equal(privateKey in profile, false, `${privateKey} must not be projected`);
    }
  });

  it("serves a runner with no badge documents as owning none", async () => {
    const profile = await getRunnerPublicProfile({ auth: { uid: runner }, data: entry("#6") }, ports);

    assert.deepEqual(profile.ownedBadgeTierIds, []);
    assert.equal(profile.subscriptionStatusLabel, "Basic");
  });

  it("withholds a private record from the real stored document", async () => {
    // The runner is seeded with real figures AND two earned badge documents,
    // so this proves the projection withholds values that genuinely exist in
    // Firestore rather than merely passing through absent ones.
    await db.doc(`userProfiles/${runner}`).set({ publicStatsHidden: true }, { merge: true });
    try {
      const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#3") }, ports);
      const serialized = JSON.stringify(profile);

      assert.equal(profile.statsHidden, true);
      for (const withheld of ["4 days", "69.8 km", "97.5", "250K", "10K"]) {
        assert.equal(serialized.includes(withheld), false, `${withheld} must not be projected`);
      }
      assert.equal(profile.totalXp, null);
      assert.deepEqual(profile.ownedBadgeTierIds, []);
      // Identity is untouched — it is already on the public board.
      assert.equal(profile.displayName, "Jinseo_main");
      assert.equal(profile.regionLabel, "Jurong East, Singapore");
      assert.equal(profile.subscriptionStatusLabel, "Premium");
    } finally {
      await db.doc(`userProfiles/${runner}`).set({ publicStatsHidden: false }, { merge: true });
    }
  });

  it("hides a runner who blocked the viewer", async () => {
    await assertRejects(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#4") }, ports), "permission-denied");
  });

  it("hides a suspended runner", async () => {
    await assertRejects(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#5") }, ports), "permission-denied");
  });

  it("resolves a leaderboard entry through the real rank projection", async () => {
    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#3") }, ports);

    assert.equal(profile.displayName, "Jinseo_main");
    assert.equal(profile.totalDistanceLabel, "69.8 km");
    assert.deepEqual([...profile.ownedBadgeTierIds].sort(), ["10K", "250K"]);
  });

  it("hides a leaderboard entry whose owner blocked the viewer", async () => {
    await assertRejects(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#4") }, ports), "permission-denied");
  });

  it("fails closed when two rank projections claim the same rank", async () => {
    await db.doc("leaderboardUserRanks/rpp-rank-duplicate").set({ ownerUid: suspended, snapshotId, buildId, rankLabel: "#3", periodKey: "2026-07" });
    try {
      await assertRejects(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#3") }, ports), "not-found");
    } finally {
      await db.doc("leaderboardUserRanks/rpp-rank-duplicate").delete();
    }
  });

  it("reports an unranked position as not found", async () => {
    await assertRejects(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#99") }, ports), "not-found");
  });

  it("refuses an entry from a superseded board build", async () => {
    // The refresh job reuses the monthly snapshot id and reassigns ranks, so a
    // stale row must never resolve to whoever holds that rank now.
    await assertRejects(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#3", "build-older") }, ports), "not-found");
  });

  it("reports an unknown entry as not found", async () => {
    await assertRejects(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: entry("#404") }, ports), "not-found");
  });
});

describe("Runner public profile emulator integration — uid-addressed form", () => {
  it("resolves a uid the viewer is friends with", async () => {
    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: friendUid } }, ports);

    assert.equal(profile.displayName, "Friend Runner");
  });

  it("resolves a uid the viewer has a pending friend request with", async () => {
    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: requestedUid } }, ports);

    assert.equal(profile.displayName, "Requested Runner");
  });

  it("resolves a discoverable stranger, the search-result path", async () => {
    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: discoverableUid } }, ports);

    assert.equal(profile.displayName, discoverableNickname);
  });

  it("resolves a challenge lobby co-member", async () => {
    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: comemberUid } }, ports);

    assert.equal(profile.displayName, "Co-member Runner");
  });

  it("resolves the viewer's own uid", async () => {
    const profile = await getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: viewer } }, ports);

    assert.equal(profile.displayName, "Viewer");
  });

  it("rejects a plain stranger uid with no edge, roster membership, or discovery flag", async () => {
    await assertRejects(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: strangerUid } }, ports), "not-found");
  });

  it("rejects a discoverable profile whose nicknameIndexKey does not match its canonical nickname", async () => {
    // Proves `socialProfile()` really recomputes and compares the index key
    // in this path, rather than trusting `socialDiscoveryStatus` alone.
    await db.doc(`userProfiles/${discoverableUid}`).update({ nicknameIndexKey: "n1_corrupted" });
    try {
      await assertRejects(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: discoverableUid } }, ports), "not-found");
    } finally {
      await db.doc(`userProfiles/${discoverableUid}`).update({ nicknameIndexKey: discoverableIndexKey });
    }
  });

  it("rejects a runner who blocked the viewer via uid with not-found, not permission-denied", async () => {
    // The uid path unifies every denial into `not-found` — a block edge must
    // not read as `permission-denied` here the way the leaderboard path does.
    await assertRejects(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: blocker } }, ports), "not-found");
  });

  it("rejects a suspended runner via uid with not-found", async () => {
    await assertRejects(() => getRunnerPublicProfile({ auth: { uid: viewer }, data: { uid: suspended } }, ports), "not-found");
  });
});

/**
 * The gap this closes: every test above calls `getRunnerPublicProfile` the
 * CORE function directly with fake or hand-assembled ports, so nothing in
 * this suite (or the fake-port unit test) ever proved that the deployed
 * callable in publicProfile/callable.ts actually injects a real
 * AvatarUrlContext at read time, or that the bucket name it resolves via
 * `getStorage().bucket().name` agrees with the bucket a real
 * `setProfileAvatar` promotion embedded in the stored avatarUrl. A caller
 * could drop the `avatarUrlContextFromEnvironment()` argument from the
 * callable, or the two bucket names could silently diverge, and every other
 * test here would stay green — the only symptom would be avatars silently
 * never appearing.
 *
 * This describe block closes that gap by going through the REAL exported
 * `getRunnerPublicProfile` callable (not the core function) with no
 * explicitly-passed avatar context — the callable resolves its own context
 * internally — against a real avatar staged and promoted through the real
 * `setProfileAvatar` callable, invoked over HTTP through the Functions
 * emulator exactly like profileAvatarEmulatorIntegration.test.ts does.
 */
describe("Runner public profile emulator integration — avatarUrl end-to-end via the real callable", () => {
  const avatarRunner = "rpp-avatar-runner";
  const avatarViewer = "rpp-avatar-viewer";
  let actor: EmulatorActor;

  before(async () => {
    assert.notEqual(process.env["FIREBASE_STORAGE_EMULATOR_HOST"], undefined, "FIREBASE_STORAGE_EMULATOR_HOST must be set");
    assert.notEqual(process.env["FIREBASE_AUTH_EMULATOR_HOST"], undefined, "FIREBASE_AUTH_EMULATOR_HOST must be set");
    await avatarFixtureCleanup();
    actor = await createEmulatorActor(getAuth(), avatarRunner, { authEmulatorOrigin: AUTH_EMULATOR_ORIGIN, signInKey: "rpp-avatar" });
    await db.doc(`userProfiles/${avatarRunner}`).set({ displayName: "Avatar Runner", avatarInitials: "AR", locationLabel: "Bedok, Singapore" });
    await db.doc(`userProfiles/${avatarViewer}`).set({ displayName: "Avatar Viewer", avatarInitials: "AV", locationLabel: "Bedok, Singapore" });
    // Visibility: the same accepted-friend edge the uid-addressed describe
    // block above already relies on to grant a view — no new gate is
    // introduced for this suite.
    await db.doc(`users/${avatarViewer}/friends/${avatarRunner}`).set({ createdAt: new Date(0) });
  });

  after(async () => {
    await avatarFixtureCleanup();
  });

  it("surfaces a real promoted avatar's exact URL through the real callable, with no explicitly-passed avatar context", async () => {
    const stagingPath = `avatar-staging/${avatarRunner}/upload-rpp-avatar.png`;
    await stageAvatarPngObject(bucket, stagingPath, avatarRunner);

    const promoted = await callEmulatorCallable(
      { functionsOrigin: FUNCTIONS_ORIGIN, projectId: PROJECT_ID, region: "asia-southeast1" },
      "setProfileAvatar",
      actor,
      { stagingPath },
    );
    assert.equal(promoted.ok, true);
    if (!promoted.ok) return;
    const writtenAvatarUrl = stringAt(promoted.data, "avatarUrl");
    assert.notEqual(writtenAvatarUrl, "");

    const storedProfile = await db.doc(`userProfiles/${avatarRunner}`).get();
    assert.equal(storedProfile.get("avatarUrl"), writtenAvatarUrl);

    // The real callable, called with NO explicitly-passed avatar context —
    // it must resolve its own via avatarUrlContextFromEnvironment() and use
    // the exact same bucket setProfileAvatar just promoted into.
    const profile = await getRunnerPublicProfileCallable.run(realCallableRequest(avatarViewer, { uid: avatarRunner }));
    assert.notEqual(profile.avatarUrl, "");
    assert.equal(profile.avatarUrl, writtenAvatarUrl);
  });

  it("resolves a foreign-bucket avatarUrl to empty through the real callable, proving the bucket check is live", async () => {
    const foreignUrl = buildAvatarDownloadUrl({
      bucket: "some-other-bucket.appspot.com",
      objectPath: "avatars/0123456789abcdef0123456789abcdef.png",
      token: "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      emulatorHost: "127.0.0.1:9199",
    });
    await db.doc(`userProfiles/${avatarRunner}`).set({ avatarUrl: foreignUrl }, { merge: true });

    const profile = await getRunnerPublicProfileCallable.run(realCallableRequest(avatarViewer, { uid: avatarRunner }));
    assert.equal(profile.avatarUrl, "");
  });

  async function avatarFixtureCleanup(): Promise<void> {
    await Promise.all([
      db.doc(`userProfiles/${avatarRunner}`).delete().catch(() => undefined),
      db.doc(`userProfiles/${avatarViewer}`).delete().catch(() => undefined),
      db.doc(`users/${avatarViewer}/friends/${avatarRunner}`).delete().catch(() => undefined),
      getAuth().deleteUser(avatarRunner).catch(() => undefined),
    ]);
    const [stagingFiles] = await bucket.getFiles({ prefix: `avatar-staging/${avatarRunner}/` });
    await Promise.all(stagingFiles.map((file) => file.delete({ ignoreNotFound: true })));
  }
});

/**
 * Builds the real `CallableRequest` shape `getRunnerPublicProfileCallable.run`
 * requires — unlike the simplified `{ auth?: { uid }, data }` shape the core
 * function accepts, firebase-functions' own type requires a full `AuthData`
 * (including a `DecodedIdToken`). Only `auth.uid` is ever read by the
 * callable's own request-normalisation, so the token fields are irrelevant
 * filler — this is exactly what `.run()`'s own doc comment describes it for
 * ("Used for unit testing").
 */
function realCallableRequest(uid: string, data: unknown): CallableRequest<unknown> {
  return {
    auth: { uid, token: {} as DecodedIdToken },
    data,
  } as CallableRequest<unknown>;
}

async function assertRejects(run: () => Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(run, (error: unknown) => typeof error === "object" && error !== null && "code" in error && error["code"] === code);
}

async function clearFixture(): Promise<void> {
  await Promise.all(rankIds.map((rankId) => db.doc(`leaderboardUserRanks/${rankId}`).delete()));
  for (const uid of seededUids) {
    const badges = await db.collection(`users/${uid}/challengeBadges`).get();
    const blocks = await db.collection(`users/${uid}/blockedUsers`).get();
    await Promise.all([...badges.docs, ...blocks.docs].map((document) => document.ref.delete()));
    await Promise.all([db.doc(`users/${uid}`).delete(), db.doc(`userProfiles/${uid}`).delete()]);
  }
  await Promise.all([
    db.doc(`users/${viewer}/friends/${friendUid}`).delete(),
    db.doc(`users/${viewer}/friendRequests/${requestedUid}`).delete(),
    db.doc(`challengeSlots/${viewer}`).delete(),
    db.doc(`challengeInstances/${challengeId}`).delete(),
  ]);
}
