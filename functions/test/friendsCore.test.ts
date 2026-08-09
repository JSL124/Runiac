import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { buildAvatarDownloadUrl, type AvatarUrlContext } from "../src/profile/avatar/avatarPaths.js";
import { createFriendsService, type FriendsCallableRequest } from "../src/friends/friendsCore.js";
import { FRIEND_REASON, readFriendReason } from "../src/friends/friendsErrors.js";
import {
  canonicalizeNickname,
  nicknameIndexKey,
  type NicknameMigrationProfile,
  preflightNicknameClaimMigration,
  validateNicknameIndexCanonicalPairs,
} from "../src/friends/nickname.js";

const PROJECT_ID = "demo-runiac-friends";
const ALICE = "friends-alice";
const BOB = "friends-bob";
const CAROL = "friends-carol";
const ADMIN = "friends-admin";
const ADMIN_CANONICAL = "friends-admin-canonical";

const BUCKET = "runiac-fypp.appspot.com";
const AVATAR_CONTEXT: AvatarUrlContext = { bucket: BUCKET };
const AVATAR_TOKEN = "3fa85f64-5717-4562-b3fc-2c963f66afa6";
const VALID_AVATAR_URL = buildAvatarDownloadUrl({
  bucket: BUCKET,
  objectPath: "avatars/0123456789abcdef0123456789abcdef.png",
  token: AVATAR_TOKEN,
});
const FOREIGN_AVATAR_URL = buildAvatarDownloadUrl({
  bucket: "some-other-bucket.appspot.com",
  objectPath: "avatars/0123456789abcdef0123456789abcdef.png",
  token: AVATAR_TOKEN,
});

let firestore: Firestore;
let nowMs = Date.UTC(2026, 6, 13, 10, 0, 0);

before(() => {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  firestore = getFirestore();
});

beforeEach(async () => {
  nowMs = Date.UTC(2026, 6, 13, 10, 0, 0);
  await Promise.all([
    firestore.recursiveDelete(firestore.collection("users")),
    firestore.recursiveDelete(firestore.collection("userProfiles")),
    firestore.recursiveDelete(firestore.collection("nicknameClaims")),
    firestore.recursiveDelete(firestore.collection("friendCooldowns")),
    firestore.recursiveDelete(firestore.collection("friendRateLimits")),
  ]);
  await Promise.all([
    seedProfile(ALICE, "Alice"),
    seedProfile(BOB, "Bøb"),
    seedProfile(CAROL, "Carol"),
    firestore.doc(`users/${ADMIN}`).set({ userRole: "Platform Administrator" }),
    firestore.doc(`users/${ADMIN_CANONICAL}`).set({ userRole: "platformAdmin" }),
  ]);
});

describe("Friends nickname canonicalization", () => {
  it("canonicalizes Unicode idempotently and derives a path-safe claim key", () => {
    const canonical = canonicalizeNickname("  A\u030Angstro\u0308m/Runner  ");

    assert.equal(canonical, "ångström/runner");
    assert.equal(canonicalizeNickname(canonical), canonical);
    assert.match(nicknameIndexKey(canonical), /^n1_[a-f0-9]{64}$/u);
    assert.doesNotMatch(nicknameIndexKey(canonical), /\//u);
  });

  it("rejects invalid nickname inputs before they can reach an index path", () => {
    assert.throws(() => canonicalizeNickname(""));
    assert.throws(() => canonicalizeNickname("\nrunner"));
    assert.throws(() => canonicalizeNickname("1234567890123456789012345678901"));
  });
});

describe("Friends account-suspension defence-in-depth", () => {
  it("rejects a suspended caller's write-bearing friends actions with permission-denied", async () => {
    const friends = service();
    await firestore.doc(`users/${ALICE}`).set({ accountStatus: "suspended" });

    await assert.rejects(
      () => friends.sendFriendRequest(request(ALICE, { targetUid: BOB })),
      (error: unknown) => error instanceof HttpsError && error.code === "permission-denied",
    );
    await assert.rejects(
      () => friends.blockUser(request(ALICE, { targetUid: BOB })),
      (error: unknown) => error instanceof HttpsError && error.code === "permission-denied",
    );

    // No friend request or block was actually created.
    assert.equal((await firestore.doc(`users/${ALICE}/friendRequests/${BOB}`).get()).exists, false);
    assert.equal((await firestore.doc(`users/${ALICE}/blockedUsers/${BOB}`).get()).exists, false);
  });

  it("still allows an explicitly unsuspended caller to send a friend request", async () => {
    const friends = service();
    await activateNicknames(friends);
    await firestore.doc(`users/${ALICE}`).set({ accountStatus: "active" });

    assert.deepEqual(await friends.sendFriendRequest(request(ALICE, { targetUid: BOB })), {
      status: "PENDING",
      created: true,
    });
  });

  it("still allows a caller with no users/{uid} document at all to send a friend request", async () => {
    const friends = service();
    await Promise.all([
      friends.upsertNickname(request(BOB, { nickname: "Bøb" })),
      friends.upsertNickname(request(CAROL, { nickname: "Carol" })),
    ]);

    // BOB has no users/{uid} document at all in this test (the whole `users`
    // collection is cleared in beforeEach, and only ALICE gets one in the
    // sibling test above) — a missing document must not be treated as
    // suspended.
    assert.equal((await firestore.doc(`users/${BOB}`).get()).exists, false);

    assert.deepEqual(await friends.sendFriendRequest(request(BOB, { targetUid: CAROL })), {
      status: "PENDING",
      created: true,
    });
  });
});

describe("Friends discovery and social transitions", () => {
  it("rejects Firestore-reserved document identifiers as target UIDs", async () => {
    const friends = service();
    for (const targetUid of [".", "..", "__reserved__"]) {
      await rejectsReason(
        () => friends.sendFriendRequest(request(ALICE, { targetUid })),
        FRIEND_REASON.INVALID_ARGUMENT,
      );
    }
  });

  it("requires authentication and returns a neutral empty search for self, inactive, and blocked users", async () => {
    const friends = service();

    await rejectsReason(
      () => friends.search({ data: { nickname: "Alice" } }),
      FRIEND_REASON.UNAUTHENTICATED,
    );
    await friends.upsertNickname(request(ALICE, { nickname: "Alice" }));
    await friends.upsertNickname(request(BOB, { nickname: "Bøb" }));

    assert.deepEqual(await friends.search(request(ALICE, { nickname: "Alice" })), { results: [] });
    await firestore.doc(`userProfiles/${BOB}`).update({ socialDiscoveryStatus: "inactive" });
    assert.deepEqual(await friends.search(request(ALICE, { nickname: "Bøb" })), { results: [] });

    await firestore.doc(`userProfiles/${BOB}`).update({ socialDiscoveryStatus: "active" });
    await firestore.doc(`users/${BOB}/blockedUsers/${ALICE}`).set({ blockedUid: ALICE });
    assert.deepEqual(await friends.search(request(ALICE, { nickname: "Bøb" })), { results: [] });
  });

  it("returns one minimal identity for an active exact Unicode nickname", async () => {
    const friends = service();
    await friends.upsertNickname(request(ALICE, { nickname: "Alice" }));
    await friends.upsertNickname(request(BOB, { nickname: "Bøb" }));

    const result = await friends.search(request(ALICE, { nickname: "bØB" }));

    assert.deepEqual(result, {
      results: [
        {
          uid: BOB,
          nickname: "Bøb",
          displayName: "Bøb",
          avatarInitials: "BØ",
          levelLabel: "",
          levelProgressPercent: 0,
          avatarUrl: "",
        },
      ],
    });
  });

  it("enriches a search result with the target's backend-owned level display", async () => {
    const friends = service();
    await friends.upsertNickname(request(ALICE, { nickname: "Alice" }));
    await friends.upsertNickname(request(BOB, { nickname: "Bøb" }));
    await firestore.doc(`userProfiles/${BOB}`).update({ levelLabel: "Champion", levelProgressPercent: 42 });

    const result = await friends.search(request(ALICE, { nickname: "bØB" }));

    assert.deepEqual(result, {
      results: [
        {
          uid: BOB,
          nickname: "Bøb",
          displayName: "Bøb",
          avatarInitials: "BØ",
          levelLabel: "Champion",
          levelProgressPercent: 42,
          avatarUrl: "",
        },
      ],
    });
  });

  it("falls back to Lv.{level} in a search result when levelLabel is absent", async () => {
    const friends = service();
    await friends.upsertNickname(request(ALICE, { nickname: "Alice" }));
    await friends.upsertNickname(request(BOB, { nickname: "Bøb" }));
    await firestore.doc(`userProfiles/${BOB}`).update({ level: 7 });

    const result = await friends.search(request(ALICE, { nickname: "bØB" }));

    assert.equal(result.results[0]?.levelLabel, "Lv.7");
    assert.equal(result.results[0]?.levelProgressPercent, 0);
  });

  it("serves the target's avatar in a search result when the context resolves it", async () => {
    const friends = serviceWithAvatars();
    await friends.upsertNickname(request(ALICE, { nickname: "Alice" }));
    await friends.upsertNickname(request(BOB, { nickname: "Bøb" }));
    await firestore.doc(`userProfiles/${BOB}`).update({ avatarUrl: VALID_AVATAR_URL });

    const result = await friends.search(request(ALICE, { nickname: "bØB" }));

    assert.equal(result.results[0]?.avatarUrl, VALID_AVATAR_URL);
  });

  it("drops a foreign-bucket avatar from a search result rather than relaying it", async () => {
    const friends = serviceWithAvatars();
    await friends.upsertNickname(request(ALICE, { nickname: "Alice" }));
    await friends.upsertNickname(request(BOB, { nickname: "Bøb" }));
    await firestore.doc(`userProfiles/${BOB}`).update({ avatarUrl: FOREIGN_AVATAR_URL });

    const result = await friends.search(request(ALICE, { nickname: "bØB" }));

    assert.equal(result.results[0]?.avatarUrl, "");
  });

  it("fails closed to an empty avatar when no avatar context is injected", async () => {
    const friends = service();
    await friends.upsertNickname(request(ALICE, { nickname: "Alice" }));
    await friends.upsertNickname(request(BOB, { nickname: "Bøb" }));
    await firestore.doc(`userProfiles/${BOB}`).update({ avatarUrl: VALID_AVATAR_URL });

    const result = await friends.search(request(ALICE, { nickname: "bØB" }));

    assert.equal(result.results[0]?.avatarUrl, "");
  });

  it("checks availability without reserving a nickname and rolls a duplicate submit back", async () => {
    const friends = service();

    assert.deepEqual(await friends.checkNicknameAvailability(request(ALICE, { nickname: "Alice" })), {
      available: true,
    });
    assert.equal((await firestore.collection("nicknameClaims").get()).empty, true);

    await friends.upsertNickname(request(ALICE, { nickname: "Alice" }));
    assert.deepEqual(await friends.checkNicknameAvailability(request(ALICE, { nickname: "ALICE" })), {
      available: true,
    });
    assert.deepEqual(await friends.checkNicknameAvailability(request(BOB, { nickname: "ALICE" })), {
      available: false,
    });
    await rejectsReason(
      () => friends.upsertNickname(request(BOB, { nickname: "ALICE" })),
      FRIEND_REASON.NICKNAME_UNAVAILABLE,
    );

    const bob = await firestore.doc(`userProfiles/${BOB}`).get();
    assert.equal(bob.get("nicknameCanonical"), undefined);
    assert.equal((await firestore.doc(`nicknameClaims/${nicknameIndexKey("alice")}`).get()).get("ownerUid"), ALICE);
  });

  it("writes callable-owned identity fields for a fresh nickname and replaces them on rename", async () => {
    const friends = service();
    await firestore.doc(`userProfiles/${ALICE}`).set({ socialDiscoveryStatus: "active" });

    assert.deepEqual(await friends.upsertNickname(request(ALICE, { nickname: "Alice" })), {
      identity: { uid: ALICE, nickname: "Alice", displayName: "Alice", avatarInitials: "AL" },
    });
    const fresh = await firestore.doc(`userProfiles/${ALICE}`).get();
    assert.equal(fresh.get("nickname"), "Alice");
    assert.equal(fresh.get("nicknameCanonical"), "alice");
    assert.equal(fresh.get("nicknameIndexKey"), nicknameIndexKey("alice"));
    assert.equal(fresh.get("socialListSortKey"), "alice");
    assert.equal(fresh.get("displayName"), "Alice");
    assert.equal(fresh.get("avatarInitials"), "AL");
    assert.notEqual(fresh.get("updatedAt"), undefined);

    assert.deepEqual(await friends.upsertNickname(request(ALICE, { nickname: "Álice" })), {
      identity: { uid: ALICE, nickname: "Álice", displayName: "Álice", avatarInitials: "ÁL" },
    });
    const renamed = await firestore.doc(`userProfiles/${ALICE}`).get();
    assert.equal(renamed.get("displayName"), "Álice");
    assert.equal(renamed.get("avatarInitials"), "ÁL");
    assert.equal((await firestore.doc(`nicknameClaims/${nicknameIndexKey("alice")}`).get()).exists, false);
    assert.equal((await firestore.doc(`nicknameClaims/${nicknameIndexKey("álice")}`).get()).exists, true);
  });

  it("propagates a renamed identity to friend, request, and block list rows", async () => {
    const friends = service();
    await friends.upsertNickname(request(ALICE, { nickname: "Alice" }));
    const staleIdentity = {
      uid: ALICE,
      nickname: "Alice",
      displayName: "Alice",
      avatarInitials: "AL",
      listSortKey: "alice",
    };
    const friendReference = firestore.doc(`users/${BOB}/friends/${ALICE}`);
    const requestReference = firestore.doc(`users/${CAROL}/friendRequests/${ALICE}`);
    const blockReference = firestore.doc(`users/${BOB}/blockedUsers/${ALICE}`);
    const unrelatedReference = firestore.doc(`users/${ALICE}/friends/${BOB}`);
    await Promise.all([
      friendReference.set({ ...staleIdentity, friendUid: ALICE, marker: "friend" }),
      requestReference.set({ ...staleIdentity, direction: "incoming", marker: "request" }),
      blockReference.set({ ...staleIdentity, blockedUid: ALICE, marker: "block" }),
      unrelatedReference.set({
        uid: BOB,
        nickname: "Bøb",
        displayName: "Bøb",
        avatarInitials: "BØ",
        listSortKey: "bøb",
        marker: "unrelated",
      }),
    ]);

    await friends.upsertNickname(request(ALICE, { nickname: "Álice" }));

    const expectedIdentity = {
      nickname: "Álice",
      displayName: "Álice",
      avatarInitials: "ÁL",
      listSortKey: "álice",
    };
    for (const reference of [friendReference, requestReference, blockReference]) {
      const snapshot = await reference.get();
      assert.equal(snapshot.get("uid"), ALICE);
      assert.deepEqual({
        nickname: snapshot.get("nickname"),
        displayName: snapshot.get("displayName"),
        avatarInitials: snapshot.get("avatarInitials"),
        listSortKey: snapshot.get("listSortKey"),
      }, expectedIdentity);
      assert.equal(typeof snapshot.get("marker"), "string");
    }
    assert.equal((await unrelatedReference.get()).get("nickname"), "Bøb");
  });

  it("rejects a rename above the atomic fanout cap without any write", async () => {
    const friends = service();
    await friends.upsertNickname(request(ALICE, { nickname: "Alice" }));
    const batch = firestore.batch();
    for (let index = 0; index < 498; index += 1) {
      batch.set(firestore.doc(`users/fanout-owner-${index}/friends/${ALICE}`), {
        uid: ALICE,
        nickname: "Alice",
        displayName: "Alice",
        avatarInitials: "AL",
        listSortKey: "alice",
      });
    }
    await batch.commit();

    await rejectsReason(
      () => friends.upsertNickname(request(ALICE, { nickname: "Álice" })),
      FRIEND_REASON.NICKNAME_RENAME_TOO_LARGE,
    );

    const profile = await firestore.doc(`userProfiles/${ALICE}`).get();
    assert.equal(profile.get("nickname"), "Alice");
    assert.equal(profile.get("nicknameCanonical"), "alice");
    assert.equal((await firestore.doc(`nicknameClaims/${nicknameIndexKey("alice")}`).get()).exists, true);
    assert.equal((await firestore.doc(`nicknameClaims/${nicknameIndexKey("álice")}`).get()).exists, false);
    const fanoutRows = await firestore.collectionGroup("friends").where("uid", "==", ALICE).get();
    assert.equal(fanoutRows.size, 498);
    assert.equal(fanoutRows.docs.every((row) => row.get("nickname") === "Alice"), true);
  });

  it("keeps non-BMP nickname initials code-point complete", async () => {
    const friends = service();
    await firestore.doc(`userProfiles/${ALICE}`).set({ socialDiscoveryStatus: "active" });

    const result = await friends.upsertNickname(request(ALICE, { nickname: "😀🚀" }));

    assert.equal(result.identity.avatarInitials, "😀🚀");
    assert.deepEqual(Array.from(result.identity.avatarInitials), ["😀", "🚀"]);
  });

  it("does not charge a duplicate pending request and rejects a crossed request without auto-accepting", async () => {
    const friends = service();
    await activateNicknames(friends);

    assert.deepEqual(await friends.sendFriendRequest(request(ALICE, { targetUid: BOB })), {
      status: "PENDING",
      created: true,
    });
    assert.deepEqual(await friends.sendFriendRequest(request(ALICE, { targetUid: BOB })), {
      status: "PENDING",
      created: false,
    });
    await rejectsReason(
      () => friends.sendFriendRequest(request(BOB, { targetUid: ALICE })),
      FRIEND_REASON.STALE_SOCIAL_STATE,
    );

    assert.equal((await firestore.doc(`users/${ALICE}/friendRequests/${BOB}`).get()).get("direction"), "outgoing");
    assert.equal((await firestore.doc(`users/${ALICE}/friendRequests/${BOB}`).get()).get("nickname"), "Bøb");
    assert.equal((await firestore.doc(`users/${BOB}/friendRequests/${ALICE}`).get()).get("direction"), "incoming");
    assert.equal((await firestore.doc(`users/${ALICE}/friends/${BOB}`).get()).exists, false);
    assert.equal((await firestore.doc(`friendRateLimits/${ALICE}`).get()).get("requestAttemptMs").length, 1);
    assert.equal((await firestore.doc(`friendRateLimits/${BOB}`).get()).exists, false);
  });

  it("creates reciprocal friends only after explicit acceptance and clears pending rows", async () => {
    const friends = service();
    await activateNicknames(friends);
    await friends.sendFriendRequest(request(ALICE, { targetUid: BOB }));

    assert.deepEqual(
      await friends.respondToFriendRequest(request(BOB, { senderUid: ALICE, action: "accept" })),
      { status: "ACCEPTED" },
    );

    assert.equal((await firestore.doc(`users/${ALICE}/friends/${BOB}`).get()).exists, true);
    assert.equal((await firestore.doc(`users/${ALICE}/friends/${BOB}`).get()).get("nickname"), "Bøb");
    assert.equal((await firestore.doc(`users/${BOB}/friends/${ALICE}`).get()).exists, true);
    assert.equal((await firestore.doc(`users/${ALICE}/friendRequests/${BOB}`).get()).exists, false);
    assert.equal((await firestore.doc(`users/${BOB}/friendRequests/${ALICE}`).get()).exists, false);
  });

  it("hard-resets friendship and pending state on block, then restores nothing on unblock", async () => {
    const friends = service();
    await activateNicknames(friends);
    await friends.sendFriendRequest(request(ALICE, { targetUid: BOB }));
    await friends.respondToFriendRequest(request(BOB, { senderUid: ALICE, action: "accept" }));

    assert.deepEqual(await friends.blockUser(request(ALICE, { targetUid: BOB })), { blocked: true });

    assert.equal((await firestore.doc(`users/${ALICE}/blockedUsers/${BOB}`).get()).exists, true);
    assert.equal((await firestore.doc(`users/${ALICE}/blockedUsers/${BOB}`).get()).get("nickname"), "Bøb");
    assert.equal((await firestore.doc(`users/${ALICE}/friends/${BOB}`).get()).exists, false);
    assert.equal((await firestore.doc(`users/${BOB}/friends/${ALICE}`).get()).exists, false);
    assert.deepEqual(await friends.search(request(BOB, { nickname: "Alice" })), { results: [] });

    assert.deepEqual(await friends.unblockUser(request(ALICE, { targetUid: BOB })), { unblocked: true });
    assert.equal((await firestore.doc(`users/${ALICE}/blockedUsers/${BOB}`).get()).exists, false);
    assert.equal((await firestore.doc(`users/${ALICE}/friends/${BOB}`).get()).exists, false);
  });

  it("makes repeated cancel, response, remove, block, and unblock calls unchanged and quota-free", async () => {
    const friends = service();
    await activateNicknames(friends);
    await friends.sendFriendRequest(request(ALICE, { targetUid: BOB }));

    assert.deepEqual(await friends.cancelFriendRequest(request(ALICE, { targetUid: BOB })), { cancelled: true });
    assert.deepEqual(await friends.cancelFriendRequest(request(ALICE, { targetUid: BOB })), { cancelled: false });
    assert.equal((await firestore.doc(`friendRateLimits/${ALICE}`).get()).get("requestAttemptMs").length, 1);
    assert.equal((await firestore.doc(`friendRateLimits/${ALICE}`).get()).get("outstandingOutgoing"), 0);

    nowMs += 24 * 60 * 60 * 1000 + 1;
    await friends.sendFriendRequest(request(ALICE, { targetUid: BOB }));
    assert.deepEqual(
      await friends.respondToFriendRequest(request(BOB, { senderUid: ALICE, action: "accept" })),
      { status: "ACCEPTED" },
    );
    assert.deepEqual(
      await friends.respondToFriendRequest(request(BOB, { senderUid: ALICE, action: "accept" })),
      { status: "ACCEPTED" },
    );
    assert.deepEqual(await friends.removeFriend(request(ALICE, { friendUid: BOB })), { removed: true });
    assert.deepEqual(await friends.removeFriend(request(ALICE, { friendUid: BOB })), { removed: false });
    assert.deepEqual(await friends.blockUser(request(ALICE, { targetUid: BOB })), { blocked: true });
    assert.deepEqual(await friends.blockUser(request(ALICE, { targetUid: BOB })), { blocked: false });
    assert.deepEqual(await friends.unblockUser(request(ALICE, { targetUid: BOB })), { unblocked: true });
    assert.deepEqual(await friends.unblockUser(request(ALICE, { targetUid: BOB })), { unblocked: false });
  });

  it("enforces the generic per-minute search retry boundary", async () => {
    const friends = service();
    await friends.upsertNickname(request(ALICE, { nickname: "Alice" }));

    for (let count = 0; count < 10; count += 1) {
      await friends.search(request(ALICE, { nickname: "missing" }));
    }

    await rejectsReason(
      () => friends.search(request(ALICE, { nickname: "missing" })),
      FRIEND_REASON.TRY_AGAIN_LATER,
    );
  });

  it("expires search, per-minute send, and daily send attempts at their exact rolling-window boundary", async () => {
    const friends = service();
    await firestore.doc(`friendRateLimits/${ALICE}`).set({
      searchAttemptMs: Array.from({ length: 10 }, () => nowMs - 60_000),
    });
    assert.deepEqual(await friends.search(request(ALICE, { nickname: "missing" })), { results: [] });
    assert.equal((await firestore.doc(`friendRateLimits/${ALICE}`).get()).get("searchAttemptMs").length, 1);

    await activateNicknames(friends);
    await firestore.doc(`friendRateLimits/${ALICE}`).set({
      requestAttemptMs: Array.from({ length: 3 }, () => nowMs - 60_000),
      outstandingOutgoing: 0,
    });
    await friends.sendFriendRequest(request(ALICE, { targetUid: BOB }));
    assert.equal((await firestore.doc(`friendRateLimits/${ALICE}`).get()).get("requestAttemptMs").length, 4);

    await friends.cancelFriendRequest(request(ALICE, { targetUid: BOB }));
    nowMs += 24 * 60 * 60 * 1000;
    await firestore.doc(`friendRateLimits/${ALICE}`).set({
      requestAttemptMs: Array.from({ length: 10 }, () => nowMs - 24 * 60 * 60 * 1000),
      outstandingOutgoing: 0,
    });
    await friends.sendFriendRequest(request(ALICE, { targetUid: BOB }));
    assert.equal((await firestore.doc(`friendRateLimits/${ALICE}`).get()).get("requestAttemptMs").length, 1);
  });

  it("enforces 3 sends per minute, 10 sends per rolling day, and 25 outstanding requests", async () => {
    const friends = service();
    await activateNicknames(friends);
    const targets = await activateTargets(friends, 11);

    for (let index = 0; index < 10; index += 1) {
      if (index > 0 && index % 3 === 0) nowMs += 60_001;
      await friends.sendFriendRequest(request(ALICE, { targetUid: targets[index] }));
    }
    await rejectsReason(
      () => friends.sendFriendRequest(request(ALICE, { targetUid: targets[10] })),
      FRIEND_REASON.TRY_AGAIN_LATER,
    );
    const dayRate = await firestore.doc(`friendRateLimits/${ALICE}`).get();
    assert.equal(dayRate.get("requestAttemptMs").length, 10);
    assert.equal(dayRate.get("outstandingOutgoing"), 10);

    await firestore.doc(`friendRateLimits/${ALICE}`).set({
      requestAttemptMs: [],
      outstandingOutgoing: 25,
    });
    await rejectsReason(
      () => friends.sendFriendRequest(request(ALICE, { targetUid: BOB })),
      FRIEND_REASON.TRY_AGAIN_LATER,
    );
    const outstandingRate = await firestore.doc(`friendRateLimits/${ALICE}`).get();
    assert.deepEqual(outstandingRate.get("requestAttemptMs"), []);
    assert.equal(outstandingRate.get("outstandingOutgoing"), 25);
  });

  it("enforces exact resend cooldown boundaries for cancellation, decline, and removal", async () => {
    const friends = service();
    await activateNicknames(friends);

    await friends.sendFriendRequest(request(ALICE, { targetUid: BOB }));
    await friends.cancelFriendRequest(request(ALICE, { targetUid: BOB }));
    nowMs += 24 * 60 * 60 * 1000 - 1;
    await rejectsReason(
      () => friends.sendFriendRequest(request(ALICE, { targetUid: BOB })),
      FRIEND_REASON.TRY_AGAIN_LATER,
    );
    nowMs += 1;
    await friends.sendFriendRequest(request(ALICE, { targetUid: BOB }));

    await friends.respondToFriendRequest(request(BOB, { senderUid: ALICE, action: "decline" }));
    nowMs += 7 * 24 * 60 * 60 * 1000 - 1;
    await rejectsReason(
      () => friends.sendFriendRequest(request(ALICE, { targetUid: BOB })),
      FRIEND_REASON.TRY_AGAIN_LATER,
    );
    nowMs += 1;
    await friends.sendFriendRequest(request(ALICE, { targetUid: BOB }));

    await friends.respondToFriendRequest(request(BOB, { senderUid: ALICE, action: "accept" }));
    await friends.removeFriend(request(ALICE, { friendUid: BOB }));
    nowMs += 24 * 60 * 60 * 1000 - 1;
    await rejectsReason(
      () => friends.sendFriendRequest(request(ALICE, { targetUid: BOB })),
      FRIEND_REASON.TRY_AGAIN_LATER,
    );
    nowMs += 1;
    assert.deepEqual(await friends.sendFriendRequest(request(ALICE, { targetUid: BOB })), {
      status: "PENDING",
      created: true,
    });
  });

  it("keeps an already declined request idempotent after its resend cooldown expires", async () => {
    const friends = service();
    await activateNicknames(friends);
    await friends.sendFriendRequest(request(ALICE, { targetUid: BOB }));
    assert.deepEqual(
      await friends.respondToFriendRequest(request(BOB, { senderUid: ALICE, action: "decline" })),
      { status: "DECLINED" },
    );

    nowMs += 8 * 24 * 60 * 60 * 1000;
    assert.deepEqual(
      await friends.respondToFriendRequest(request(BOB, { senderUid: ALICE, action: "decline" })),
      { status: "DECLINED" },
    );
  });
});

describe("Friends nickname migration", () => {
  it("migrates valid legacy claims and reruns without duplicate index records", async () => {
    const friends = service();
    await seedLegacyMigrationProfile(ALICE, "Åsa", "legacy-asa");
    await seedLegacyMigrationProfile(BOB, "Bøb", "legacy-bob");
    await seedLegacyMigrationProfile(CAROL, "😀🚀", "legacy-emoji");

    assert.deepEqual(await friends.migrateUnicodeNicknameClaims(request(ADMIN, {})), { migrated: 3 });
    assert.equal((await firestore.doc(`nicknameClaims/legacy-asa`).get()).exists, false);
    assert.equal((await firestore.doc(`nicknameClaims/legacy-bob`).get()).exists, false);
    assert.equal((await firestore.doc(`nicknameClaims/${nicknameIndexKey("åsa")}`).get()).get("ownerUid"), ALICE);
    assert.equal((await firestore.doc(`nicknameClaims/${nicknameIndexKey("bøb")}`).get()).get("ownerUid"), BOB);
    assert.equal((await firestore.doc(`nicknameClaims/${nicknameIndexKey("😀🚀")}`).get()).get("ownerUid"), CAROL);
    const migratedAlice = await firestore.doc(`userProfiles/${ALICE}`).get();
    const migratedBob = await firestore.doc(`userProfiles/${BOB}`).get();
    assert.equal(migratedAlice.get("nicknameIndexKey"), nicknameIndexKey("åsa"));
    assert.equal(migratedAlice.get("displayName"), "Åsa");
    assert.equal(migratedAlice.get("avatarInitials"), "ÅS");
    assert.equal(migratedBob.get("displayName"), "Bøb");
    assert.equal(migratedBob.get("avatarInitials"), "BØ");
    const migratedCarol = await firestore.doc(`userProfiles/${CAROL}`).get();
    assert.equal(migratedCarol.get("avatarInitials"), "😀🚀");
    assert.deepEqual(Array.from(migratedCarol.get("avatarInitials")), ["😀", "🚀"]);

    nowMs += 1;
    assert.deepEqual(await friends.migrateUnicodeNicknameClaims(request(ADMIN, {})), { migrated: 3 });
    assert.equal((await firestore.collection("nicknameClaims").get()).size, 3);
  });

  it("aborts corrupt and colliding migration inputs before any partial write", async () => {
    const friends = service();
    await seedLegacyMigrationProfile(ALICE, "Alice", "legacy-alice");
    await firestore.doc(`userProfiles/${BOB}`).set({
      nickname: "Bøb",
      nicknameKey: "legacy-missing",
      socialDiscoveryStatus: "active",
    });

    await rejectsReason(
      () => friends.migrateUnicodeNicknameClaims(request(ADMIN, {})),
      FRIEND_REASON.NICKNAME_MIGRATION_INVALID,
    );
    assert.equal((await firestore.doc(`nicknameClaims/legacy-alice`).get()).exists, true);
    assert.equal((await firestore.doc(`nicknameClaims/${nicknameIndexKey("alice")}`).get()).exists, false);
    assert.equal((await firestore.doc(`userProfiles/${ALICE}`).get()).get("nicknameKey"), "legacy-alice");

    await firestore.recursiveDelete(firestore.collection("userProfiles"));
    await firestore.recursiveDelete(firestore.collection("nicknameClaims"));
    await seedLegacyMigrationProfile(ALICE, "Åsa", "legacy-asa");
    await seedLegacyMigrationProfile(BOB, "A\u030Asa", "legacy-asa-combining");
    await rejectsReason(
      () => friends.migrateUnicodeNicknameClaims(request(ADMIN, {})),
      FRIEND_REASON.NICKNAME_MIGRATION_INVALID,
    );
    assert.equal((await firestore.doc(`nicknameClaims/legacy-asa`).get()).exists, true);
    assert.equal((await firestore.doc(`nicknameClaims/legacy-asa-combining`).get()).exists, true);
    assert.equal((await firestore.doc(`nicknameClaims/${nicknameIndexKey("åsa")}`).get()).exists, false);
  });

  it("aborts a migration that would exceed the atomic write limit without mutation", async () => {
    const friends = service();
    const batch = firestore.batch();
    for (let index = 0; index < 167; index += 1) {
      const uid = `migration-${index}`;
      const nickname = `Runner${index}`;
      const legacyClaimId = `legacy-${index}`;
      batch.set(firestore.doc(`userProfiles/${uid}`), {
        nickname,
        nicknameKey: legacyClaimId,
        socialDiscoveryStatus: "active",
      });
      batch.set(firestore.doc(`nicknameClaims/${legacyClaimId}`), { ownerUid: uid });
    }
    await batch.commit();

    await rejectsReason(
      () => friends.migrateUnicodeNicknameClaims(request(ADMIN, {})),
      FRIEND_REASON.MIGRATION_TOO_LARGE,
    );
    assert.equal((await firestore.doc("nicknameClaims/legacy-0").get()).exists, true);
    assert.equal((await firestore.doc(`nicknameClaims/${nicknameIndexKey("runner0")}`).get()).exists, false);
    assert.equal((await firestore.doc("userProfiles/migration-0").get()).get("nicknameKey"), "legacy-0");
  });

  it("aborts a colliding Unicode migration plan without returning writes", () => {
    const profiles: readonly NicknameMigrationProfile[] = [
      { uid: ALICE, nickname: "Åsa", legacyNicknameKey: "asa" },
      { uid: BOB, nickname: "A\u030Asa", legacyNicknameKey: "asa-two" },
    ];

    const result = preflightNicknameClaimMigration(profiles, []);

    assert.deepEqual(result, { kind: "invalid", reason: "CANONICAL_COLLISION" });
  });

  it("rejects an explicit index-key collision across different canonical nicknames", () => {
    assert.equal(
      validateNicknameIndexCanonicalPairs([
        { indexKey: "n1_same", canonical: "alice" },
        { indexKey: "n1_same", canonical: "bob" },
      ]),
      false,
    );
  });

  it("requires a Platform Administrator for the trusted migration callable", async () => {
    const friends = service();

    await rejectsReason(
      () => friends.migrateUnicodeNicknameClaims(request(ALICE, {})),
      FRIEND_REASON.NOT_PLATFORM_ADMIN,
    );
  });

  it("accepts the canonical admin-console userRole value ('platformAdmin'), not just the legacy string", async () => {
    const friends = service();
    await seedLegacyMigrationProfile(ALICE, "Alice", "legacy-alice-canonical");

    assert.deepEqual(await friends.migrateUnicodeNicknameClaims(request(ADMIN_CANONICAL, {})), { migrated: 1 });
  });
});

function service() {
  return createFriendsService({ firestore, nowMs: () => nowMs });
}

/** The production wiring: `searchFriends` is the one callable given a real avatar context. */
function serviceWithAvatars() {
  return createFriendsService({ firestore, nowMs: () => nowMs, avatarContext: AVATAR_CONTEXT });
}

async function activateNicknames(friends: ReturnType<typeof service>): Promise<void> {
  await Promise.all([
    friends.upsertNickname(request(ALICE, { nickname: "Alice" })),
    friends.upsertNickname(request(BOB, { nickname: "Bøb" })),
  ]);
}

async function activateTargets(friends: ReturnType<typeof service>, count: number): Promise<string[]> {
  const targets: string[] = [];
  for (let index = 0; index < count; index += 1) {
    const uid = `friends-target-${index}`;
    const nickname = `Target${index}`;
    await seedProfile(uid, nickname);
    await friends.upsertNickname(request(uid, { nickname }));
    targets.push(uid);
  }
  return targets;
}

async function seedLegacyMigrationProfile(uid: string, nickname: string, legacyClaimId: string): Promise<void> {
  await Promise.all([
    firestore.doc(`userProfiles/${uid}`).set({
      nickname,
      nicknameKey: legacyClaimId,
      socialDiscoveryStatus: "active",
    }),
    firestore.doc(`nicknameClaims/${legacyClaimId}`).set({ ownerUid: uid }),
  ]);
}

async function seedProfile(uid: string, nickname: string): Promise<void> {
  await firestore.doc(`userProfiles/${uid}`).set({
    displayName: `Runner ${nickname}`,
    avatarInitials: `R${nickname.slice(0, 1).toUpperCase()}`,
    socialDiscoveryStatus: "active",
  });
}

function request(uid: string, data: Record<string, unknown>): FriendsCallableRequest {
  return { auth: { uid }, data };
}

async function rejectsReason(action: () => Promise<unknown>, reason: string): Promise<void> {
  await assert.rejects(action, (error: unknown) => readFriendReason(error) === reason);
}
