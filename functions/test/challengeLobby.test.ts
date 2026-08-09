import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import {
  cancelChallengeLobbyForCallable,
  createChallengeLobbyForCallable,
  getActiveChallengeForCallable,
  getChallengeCatalogForCallable,
  getChallengeInvitationsForCallable,
  inviteChallengeFriendsForCallable,
  respondToChallengeInvitationForCallable,
  startChallengeForCallable,
  withdrawFromChallengeLobbyForCallable,
  type CallableRequest,
} from "../src/challenge/challengeLobbyCore.js";
import { readChallengeReason, type ChallengeReason } from "../src/challenge/challengeErrors.js";
import { CHALLENGE_CATALOG } from "../src/challenge/challengeCatalog.js";
import { buildAvatarDownloadUrl, type AvatarUrlContext } from "../src/profile/avatar/avatarPaths.js";
import { asRecord, callEmulatorCallable, stringAt } from "./helpers/avatarEmulatorHelpers.js";

const PROJECT_ID = "demo-runiac-challenge";
const OWNER = "ch-owner";
const A = "ch-friend-a";
const B = "ch-friend-b";
const C = "ch-friend-c";
const STRANGER = "ch-stranger";
const ALL_UIDS = [OWNER, A, B, C, STRANGER] as const;

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

// The bucket name a real `getActiveChallenge` callable, running inside this
// project's Functions emulator, actually resolves via
// `getStorage().bucket().name` — the Admin SDK's `${projectId}.appspot.com`
// default convention. No Storage emulator is running for this group (the
// URLs below are never fetched, only round-tripped as strings), so this
// exercises the production (non-emulator-host) branch of
// resolveProfileAvatarUrl/buildAvatarDownloadUrl.
const REAL_BUCKET = `${PROJECT_ID}.appspot.com`;
const REAL_AVATAR_URL = buildAvatarDownloadUrl({
  bucket: REAL_BUCKET,
  objectPath: "avatars/0123456789abcdef0123456789abcdef.png",
  token: AVATAR_TOKEN,
});
const REAL_FOREIGN_AVATAR_URL = buildAvatarDownloadUrl({
  bucket: "some-other-bucket.appspot.com",
  objectPath: "avatars/0123456789abcdef0123456789abcdef.png",
  token: AVATAR_TOKEN,
});
const FUNCTIONS_ORIGIN = "http://127.0.0.1:5001";

let firestore: Firestore;

before(() => {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  firestore = getFirestore();
});

beforeEach(async () => {
  await firestore.recursiveDelete(firestore.collection("challengeInstances"));
  await deleteCollection("challengeInvitations");
  await deleteCollection("challengeSlots");
  await deleteCollection("challengePremiumHolds");
  await firestore.doc("config/challengeAccess").delete();
  await Promise.all(ALL_UIDS.map((uid) => firestore.doc(`users/${uid}`).delete()));
  await Promise.all(
    ALL_UIDS.flatMap((uid) =>
      ALL_UIDS.filter((other) => other !== uid).flatMap((other) => [
        firestore.doc(`users/${uid}/friends/${other}`).delete(),
        firestore.doc(`users/${uid}/blockedUsers/${other}`).delete(),
      ]),
    ),
  );
  await Promise.all(
    ALL_UIDS.map((uid) =>
      firestore.doc(`userProfiles/${uid}`).set({ displayName: `Runner ${uid}`, avatarInitials: uid.slice(0, 2).toUpperCase() }),
    ),
  );
  // Owner is reciprocal friends with A, B, C (not STRANGER).
  await Promise.all([makeFriends(OWNER, A), makeFriends(OWNER, B), makeFriends(OWNER, C)]);
});

// ---------------------------------------------------------------------------
// createChallengeLobby
// ---------------------------------------------------------------------------

describe("createChallengeLobby", () => {
  it("rejects unauthenticated callers", async () => {
    await rejectsReason(() => createChallengeLobbyForCallable({ data: { tierId: "10K" } }, firestore), "UNAUTHENTICATED");
  });

  it("rejects a suspended caller with permission-denied before creating a lobby (defence-in-depth)", async () => {
    await firestore.doc(`users/${OWNER}`).set({ accountStatus: "suspended" });

    await assert.rejects(
      () => createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore),
      (error: unknown) => error instanceof HttpsError && error.code === "permission-denied",
    );

    assert.equal((await firestore.doc(`challengeSlots/${OWNER}`).get()).exists, false);
  });

  it("still creates a lobby for an explicitly unsuspended caller", async () => {
    await firestore.doc(`users/${OWNER}`).set({ accountStatus: "active" });

    const result = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore);

    assert.equal(result.idempotent, false);
  });

  it("rejects an unknown tier", async () => {
    await rejectsReason(() => createChallengeLobbyForCallable(req(OWNER, { tierId: "999K" }), firestore), "UNKNOWN_TIER");
  });

  it("creates a RECRUITING solo lobby with owner slot and 24h expiry", async () => {
    const result = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore);
    assert.equal(result.idempotent, false);

    const instance = await instanceDoc(result.challengeId);
    assert.equal(instance.get("status"), "RECRUITING");
    assert.equal(instance.get("ownerUid"), OWNER);
    assert.equal(instance.get("mode"), "SOLO");
    assert.deepEqual(instance.get("rosterUids"), [OWNER]);
    assert.equal(instance.get("rules").targetMeters, CHALLENGE_CATALOG["10K"].soloTargetMeters);
    const createdAt = instance.get("createdAt") as Timestamp;
    const expiresAt = instance.get("lobbyExpiresAt") as Timestamp;
    assert.equal(expiresAt.toMillis() - createdAt.toMillis(), 24 * 60 * 60 * 1000);

    const owner = await participantDoc(result.challengeId, OWNER);
    assert.equal(owner.get("role"), "owner");
    assert.equal(owner.get("status"), "ACCEPTED");
    assert.equal(owner.get("displayNameSnapshot"), "Runner ch-owner");

    const slot = await slotDoc(OWNER);
    assert.equal(slot.get("challengeId"), result.challengeId);
    assert.equal(slot.get("role"), "owner");
  });

  it("is idempotent for the same owner + tier (one slot, one instance)", async () => {
    const first = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore);
    const second = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore);
    assert.equal(second.idempotent, true);
    assert.equal(second.challengeId, first.challengeId);
    const instances = await firestore.collection("challengeInstances").get();
    assert.equal(instances.size, 1);
  });

  it("rejects a second lobby while the caller already holds a slot", async () => {
    await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore);
    await rejectsReason(() => createChallengeLobbyForCallable(req(OWNER, { tierId: "20K" }), firestore), "ALREADY_HOLDS_SLOT");
  });
});

// ---------------------------------------------------------------------------
// inviteChallengeFriends
// ---------------------------------------------------------------------------

describe("inviteChallengeFriends", () => {
  it("owner invites a reciprocal friend (PENDING invitation)", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    const result = await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    assert.deepEqual(result.invited, [A]);
    const invite = await invitationDoc(challengeId, A);
    assert.equal(invite.get("status"), "PENDING");
    assert.equal(invite.get("recipientUid"), A);
    assert.equal(invite.get("ownerUid"), OWNER);
  });

  it("rejects a non-owner inviter", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await rejectsReason(() => inviteChallengeFriendsForCallable(req(A, { challengeId, uids: [B] }), firestore), "NOT_LOBBY_OWNER");
  });

  it("rejects inviting a non-reciprocal (stranger) friend", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await rejectsReason(() => inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [STRANGER] }), firestore), "INVITEE_NOT_RECIPROCAL_FRIEND");
  });

  it("rejects inviting a one-way friend", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await firestore.doc(`users/${OWNER}/friends/${STRANGER}`).set({ friendUid: STRANGER }); // one direction only
    await rejectsReason(() => inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [STRANGER] }), firestore), "INVITEE_NOT_RECIPROCAL_FRIEND");
  });

  it("rejects inviting a blocked friend", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await firestore.doc(`users/${A}/blockedUsers/${OWNER}`).set({ blockedUid: OWNER });
    await rejectsReason(() => inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore), "INVITEE_BLOCKED");
  });

  it("enforces the invite capacity cap (maxInvitedFriends counting pending)", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore); // cap 1
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await rejectsReason(() => inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [B] }), firestore), "INVITE_CAPACITY_EXCEEDED");
  });

  it("treats a duplicate invite to the same uid as an idempotent no-op", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    const again = await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    assert.deepEqual(again.invited, []);
    assert.deepEqual(again.alreadyPending, [A]);
    const invitations = await firestore.collection("challengeInvitations").where("challengeId", "==", challengeId).get();
    assert.equal(invitations.size, 1);
  });

  it("rejects inviting yourself", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await rejectsReason(() => inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [OWNER] }), firestore), "CANNOT_INVITE_SELF");
  });
});

// ---------------------------------------------------------------------------
// respondToChallengeInvitation
// ---------------------------------------------------------------------------

describe("respondToChallengeInvitation", () => {
  it("accepts an invitation: roster, participant, and slot are created atomically", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    const result = await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);
    assert.equal(result.outcome, "accepted");

    const instance = await instanceDoc(challengeId);
    assert.deepEqual([...instance.get("rosterUids")].sort(), [A, OWNER].sort());
    const participant = await participantDoc(challengeId, A);
    assert.equal(participant.get("status"), "ACCEPTED");
    assert.equal(participant.get("role"), "member");
    assert.equal((await slotDoc(A)).get("challengeId"), challengeId);
    assert.equal((await invitationDoc(challengeId, A)).get("status"), "ACCEPTED");
  });

  it("rejects accepting while the recipient already holds a slot", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await createChallengeLobbyForCallable(req(A, { tierId: "10K" }), firestore); // A now holds a slot
    await rejectsReason(() => respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore), "ALREADY_HOLDS_SLOT");
  });

  it("declines an invitation and frees the invite position", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore); // cap 1
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    const declined = await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "decline" }), firestore);
    assert.equal(declined.outcome, "declined");
    assert.equal((await invitationDoc(challengeId, A)).get("status"), "DECLINED");
    // Position freed: owner can now invite B despite cap 1.
    const reinvite = await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [B] }), firestore);
    assert.deepEqual(reinvite.invited, [B]);
  });

  it("rejects a non-recipient responder", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await rejectsReason(() => respondToChallengeInvitationForCallable(req(B, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore), "NOT_INVITATION_RECIPIENT");
  });

  it("is idempotent when the same recipient accepts twice", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);
    const again = await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);
    assert.equal(again.outcome, "accepted");
    assert.equal(again.idempotent, true);
    assert.deepEqual([...(await instanceDoc(challengeId)).get("rosterUids")].sort(), [A, OWNER].sort());
  });
});

// ---------------------------------------------------------------------------
// withdrawFromChallengeLobby
// ---------------------------------------------------------------------------

describe("withdrawFromChallengeLobby", () => {
  it("lets an accepted non-owner member leave (LEFT, slot released, roster shrinks)", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);
    await withdrawFromChallengeLobbyForCallable(req(A, { challengeId }), firestore);
    assert.equal((await participantDoc(challengeId, A)).get("status"), "LEFT");
    assert.deepEqual((await instanceDoc(challengeId)).get("rosterUids"), [OWNER]);
    assert.equal((await slotDoc(A)).exists, false);
  });

  it("rejects the owner leaving alone", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await rejectsReason(() => withdrawFromChallengeLobbyForCallable(req(OWNER, { challengeId }), firestore), "OWNER_CANNOT_LEAVE");
  });

  it("rejects a non-participant withdrawing", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await rejectsReason(() => withdrawFromChallengeLobbyForCallable(req(A, { challengeId }), firestore), "NOT_A_PARTICIPANT");
  });

  it("is idempotent when the member withdraws twice", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);
    await withdrawFromChallengeLobbyForCallable(req(A, { challengeId }), firestore);
    const again = await withdrawFromChallengeLobbyForCallable(req(A, { challengeId }), firestore);
    assert.equal(again.idempotent, true);
  });
});

// ---------------------------------------------------------------------------
// cancelChallengeLobby
// ---------------------------------------------------------------------------

describe("cancelChallengeLobby", () => {
  it("owner cancels: instance CANCELLED, participants CANCELLED, slots released, invitations REVOKED", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [B] }), firestore); // B still pending

    await cancelChallengeLobbyForCallable(req(OWNER, { challengeId }), firestore);
    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "CANCELLED");
    assert.equal(instance.get("terminalReason"), "LOBBY_CANCELLED");
    assert.equal((await participantDoc(challengeId, OWNER)).get("status"), "CANCELLED");
    assert.equal((await participantDoc(challengeId, A)).get("status"), "CANCELLED");
    assert.equal((await slotDoc(OWNER)).exists, false);
    assert.equal((await slotDoc(A)).exists, false);
    assert.equal((await invitationDoc(challengeId, B)).get("status"), "REVOKED");
  });

  it("rejects a non-owner canceller", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await rejectsReason(() => cancelChallengeLobbyForCallable(req(A, { challengeId }), firestore), "NOT_LOBBY_OWNER");
  });

  it("is idempotent when the owner cancels twice", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await cancelChallengeLobbyForCallable(req(OWNER, { challengeId }), firestore);
    const again = await cancelChallengeLobbyForCallable(req(OWNER, { challengeId }), firestore);
    assert.equal(again.idempotent, true);
  });
});

// ---------------------------------------------------------------------------
// startChallenge
// ---------------------------------------------------------------------------

describe("startChallenge", () => {
  it("solo start locks mode SOLO and activates the owner", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore);
    const result = await startChallengeForCallable(req(OWNER, { challengeId }), firestore);
    assert.equal(result.mode, "SOLO");
    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "ACTIVE");
    assert.equal(instance.get("mode"), "SOLO");
    const startsAt = instance.get("startsAt") as Timestamp;
    const scheduledEndsAt = instance.get("scheduledEndsAt") as Timestamp;
    assert.equal(scheduledEndsAt.toMillis() - startsAt.toMillis(), CHALLENGE_CATALOG["10K"].durationMs);
    assert.equal((await participantDoc(challengeId, OWNER)).get("status"), "ACTIVE");
  });

  it("group start locks mode GROUP and activates every roster member", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);
    const result = await startChallengeForCallable(req(OWNER, { challengeId }), firestore);
    assert.equal(result.mode, "GROUP");
    assert.equal((await instanceDoc(challengeId)).get("mode"), "GROUP");
    assert.equal((await participantDoc(challengeId, OWNER)).get("status"), "ACTIVE");
    assert.equal((await participantDoc(challengeId, A)).get("status"), "ACTIVE");
  });

  it("rejects a non-owner starter", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);
    await rejectsReason(() => startChallengeForCallable(req(A, { challengeId }), firestore), "NOT_LOBBY_OWNER");
  });

  it("expires unanswered invitations at start and keeps the pending invitee out of the roster", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore); // never answered
    const result = await startChallengeForCallable(req(OWNER, { challengeId }), firestore);
    assert.equal(result.mode, "SOLO");
    assert.equal((await invitationDoc(challengeId, A)).get("status"), "EXPIRED");
    assert.equal((await slotDoc(A)).exists, false);
    assert.deepEqual((await instanceDoc(challengeId)).get("rosterUids"), [OWNER]);
  });

  it("is idempotent when the owner starts twice", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore);
    const first = await startChallengeForCallable(req(OWNER, { challengeId }), firestore);
    const again = await startChallengeForCallable(req(OWNER, { challengeId }), firestore);
    assert.equal(again.idempotent, true);
    assert.equal(again.startsAtMs, first.startsAtMs);
  });
});

// ---------------------------------------------------------------------------
// Lazy 24h expiry
// ---------------------------------------------------------------------------

describe("lazy lobby expiry", () => {
  it("marks a past-deadline lobby EXPIRED on start, releases slot, and rejects with LOBBY_EXPIRED", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore);
    await backdateExpiry(challengeId);
    await rejectsReason(() => startChallengeForCallable(req(OWNER, { challengeId }), firestore), "LOBBY_EXPIRED");
    assert.equal((await instanceDoc(challengeId)).get("status"), "EXPIRED");
    assert.equal((await slotDoc(OWNER)).exists, false);
  });

  it("expires pending invitations and releases slots when a recipient touches an expired lobby", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await backdateExpiry(challengeId);
    await rejectsReason(() => respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore), "LOBBY_EXPIRED");
    assert.equal((await instanceDoc(challengeId)).get("status"), "EXPIRED");
    assert.equal((await invitationDoc(challengeId, A)).get("status"), "EXPIRED");
    assert.equal((await slotDoc(OWNER)).exists, false);
    assert.equal((await slotDoc(A)).exists, false);
  });

  it("frees an expired owner slot so the owner can create a fresh lobby", async () => {
    const first = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore);
    await backdateExpiry(first.challengeId);
    const second = await createChallengeLobbyForCallable(req(OWNER, { tierId: "20K" }), firestore);
    assert.notEqual(second.challengeId, first.challengeId);
    assert.equal((await instanceDoc(first.challengeId)).get("status"), "EXPIRED");
    assert.equal((await slotDoc(OWNER)).get("challengeId"), second.challengeId);
  });
});

// ---------------------------------------------------------------------------
// Tier entitlement (config/challengeAccess)
// ---------------------------------------------------------------------------

describe("challenge tier entitlement", () => {
  it("rejects a basic caller creating a premium-only tier lobby (default config)", async () => {
    // No config doc → loader defaults: 100K+ are premium-only.
    await rejectsReason(() => createChallengeLobbyForCallable(req(OWNER, { tierId: "100K" }), firestore), "PREMIUM_REQUIRED");
    const slots = await firestore.collection("challengeSlots").get();
    assert.equal(slots.size, 0);
  });

  it("allows a premium caller to create a premium-only tier lobby", async () => {
    await firestore.doc(`users/${OWNER}`).set({ subscriptionStatus: "premium" });
    const result = await createChallengeLobbyForCallable(req(OWNER, { tierId: "100K" }), firestore);
    assert.equal(result.status, "RECRUITING");
    assert.equal((await instanceDoc(result.challengeId)).get("tierId"), "100K");
  });

  it("rejects a lapsed premium caller on a premium-only tier", async () => {
    await firestore.doc(`users/${OWNER}`).set({
      subscriptionStatus: "premium",
      subscriptionExpiresAt: Timestamp.fromMillis(Date.now() - 60_000),
    });
    await rejectsReason(() => createChallengeLobbyForCallable(req(OWNER, { tierId: "200K" }), firestore), "PREMIUM_REQUIRED");
  });

  it("keeps the first three tiers open to basic callers", async () => {
    const result = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    assert.equal(result.status, "RECRUITING");
  });

  it("honours a stored override that opens every tier", async () => {
    // A stored premiumOnlyTiers array REPLACES the default list (deepMerge
    // treats arrays as leaf values), so clearing it opens all nine tiers.
    await firestore.doc("config/challengeAccess").set({ premiumOnlyTiers: [] });
    const result = await createChallengeLobbyForCallable(req(OWNER, { tierId: "1000K" }), firestore);
    assert.equal(result.status, "RECRUITING");
  });

  it("falls back to the default premium-only list when the stored doc is invalid", async () => {
    await firestore.doc("config/challengeAccess").set({ premiumOnlyTiers: ["NOT_A_TIER"] });
    await rejectsReason(() => createChallengeLobbyForCallable(req(OWNER, { tierId: "500K" }), firestore), "PREMIUM_REQUIRED");
  });

  // The gate extends from creation to acceptance: a premium-only tier requires
  // premium of every participant, not just the runner who opened the lobby.
  it("rejects a basic recipient accepting a premium-only tier invitation", async () => {
    await firestore.doc(`users/${OWNER}`).set({ subscriptionStatus: "premium" });
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "100K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);

    await rejectsReason(
      () => respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore),
      "PREMIUM_REQUIRED",
    );

    assert.deepEqual((await instanceDoc(challengeId)).get("rosterUids"), [OWNER]);
    assert.equal((await participantDoc(challengeId, A)).exists, false);
    assert.equal((await slotDoc(A)).exists, false);
    assert.equal((await invitationDoc(challengeId, A)).get("status"), "PENDING");
  });

  it("allows a premium recipient to accept a premium-only tier invitation", async () => {
    await firestore.doc(`users/${OWNER}`).set({ subscriptionStatus: "premium" });
    await firestore.doc(`users/${A}`).set({ subscriptionStatus: "premium" });
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "100K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);

    const result = await respondToChallengeInvitationForCallable(
      req(A, { inviteId: inviteId(challengeId, A), response: "accept" }),
      firestore,
    );

    assert.equal(result.outcome, "accepted");
    assert.equal((await participantDoc(challengeId, A)).get("role"), "member");
  });

  it("still lets a basic recipient accept an open-tier invitation", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);

    const result = await respondToChallengeInvitationForCallable(
      req(A, { inviteId: inviteId(challengeId, A), response: "accept" }),
      firestore,
    );

    assert.equal(result.outcome, "accepted");
  });

  it("lets a basic recipient DECLINE a premium-only tier invitation", async () => {
    // Declining is not entitled access; gating it would strand the invitation
    // as PENDING until it expired.
    await firestore.doc(`users/${OWNER}`).set({ subscriptionStatus: "premium" });
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "100K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);

    const result = await respondToChallengeInvitationForCallable(
      req(A, { inviteId: inviteId(challengeId, A), response: "decline" }),
      firestore,
    );

    assert.equal(result.outcome, "declined");
    assert.equal((await invitationDoc(challengeId, A)).get("status"), "DECLINED");
  });

  it("does not gate the invite path, so an owner never learns a friend's tier", async () => {
    await firestore.doc(`users/${OWNER}`).set({ subscriptionStatus: "premium" });
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "100K" }), firestore);

    const invited = await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);

    assert.deepEqual(invited.invited, [A]);
    assert.equal((await invitationDoc(challengeId, A)).get("status"), "PENDING");
  });
});

// ---------------------------------------------------------------------------
// Premium-lapse grace relay
// ---------------------------------------------------------------------------

describe("getActiveChallenge premium-lapse relay", () => {
  it("returns premiumHold: null when the caller has no hold", async () => {
    await firestore.doc(`users/${OWNER}`).set({ subscriptionStatus: "premium" });
    await createChallengeLobbyForCallable(req(OWNER, { tierId: "100K" }), firestore);

    const view = await getActiveChallengeForCallable(req(OWNER, {}), firestore);

    assert.notEqual(view.challenge, null);
    assert.equal(view.premiumHold, null);
  });

  it("relays the caller's own grace deadline", async () => {
    await firestore.doc(`users/${OWNER}`).set({ subscriptionStatus: "premium" });
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "100K" }), firestore);
    const graceExpiresAtMs = Date.now() + 12 * 60 * 60 * 1000;
    await seedPremiumHold(OWNER, challengeId, graceExpiresAtMs);

    const view = await getActiveChallengeForCallable(req(OWNER, {}), firestore);

    assert.equal(view.premiumHold?.graceExpiresAtMs, graceExpiresAtMs);
  });

  it("never relays another roster member's hold", async () => {
    // Subscription state is private: a lobby-mate must not be able to tell
    // that another runner stopped paying.
    await firestore.doc(`users/${OWNER}`).set({ subscriptionStatus: "premium" });
    await firestore.doc(`users/${A}`).set({ subscriptionStatus: "premium" });
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "100K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);
    await seedPremiumHold(A, challengeId, Date.now() + 12 * 60 * 60 * 1000);

    const ownerView = await getActiveChallengeForCallable(req(OWNER, {}), firestore);

    assert.equal(ownerView.premiumHold, null);
    assert.equal(ownerView.challenge?.participants.length, 2);
  });
});

// ---------------------------------------------------------------------------
// Read models
// ---------------------------------------------------------------------------

describe("challenge read models", () => {
  it("getChallengeCatalog returns all nine tiers plus the version", async () => {
    const catalog = await getChallengeCatalogForCallable(req(OWNER, {}), firestore);
    assert.equal(catalog.tiers.length, 9);
    assert.equal(catalog.version, "challenge-distance-v1");
    // No config/challengeAccess doc seeded → the default premium-only list.
    assert.deepEqual(catalog.premiumOnlyTiers, ["100K", "200K", "250K", "300K", "500K", "1000K"]);
  });

  it("getChallengeCatalog rejects unauthenticated callers", async () => {
    await rejectsReason(async () => getChallengeCatalogForCallable({ data: {} }, firestore), "UNAUTHENTICATED");
  });

  it("getActiveChallenge returns the caller's instance + participant-safe roster", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);
    const active = await getActiveChallengeForCallable(req(OWNER, {}), firestore);
    assert.notEqual(active.challenge, null);
    assert.equal(active.challenge?.instance.challengeId, challengeId);
    assert.equal(active.challenge?.participants.length, 2);
    // Participant-safe: only whitelisted fields present.
    const keys = Object.keys(active.challenge!.participants[0]!).sort();
    assert.deepEqual(
      keys,
      [
        "avatarInitialsSnapshot",
        "avatarUrlSnapshot",
        "creditedMeters",
        "displayNameSnapshot",
        "levelLabelSnapshot",
        "levelProgressPercentSnapshot",
        "reward",
        "role",
        "status",
        "uid",
      ].sort(),
    );
  });

  it("getActiveChallenge resolves each participant's current level label live", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);

    // Profiles gain a level AFTER the roster identity was snapshotted at join.
    await firestore.doc(`userProfiles/${OWNER}`).set({ levelLabel: "Lv.9" }, { merge: true });
    await firestore.doc(`userProfiles/${A}`).set({ level: 2 }, { merge: true });

    const active = await getActiveChallengeForCallable(req(OWNER, {}), firestore);
    const byUid = new Map(active.challenge!.participants.map((p) => [p.uid, p.levelLabelSnapshot]));
    // Explicit levelLabel is read back verbatim; a bare numeric level formats as Lv.N.
    assert.equal(byUid.get(OWNER), "Lv.9");
    assert.equal(byUid.get(A), "Lv.2");
  });

  it("getActiveChallenge returns an empty level label when the profile has no level", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    const active = await getActiveChallengeForCallable(req(OWNER, {}), firestore);
    assert.equal(active.challenge?.participants[0]?.levelLabelSnapshot, "");
  });

  it("getActiveChallenge resolves each participant's current level progress live", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    await respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore);

    await firestore.doc(`userProfiles/${OWNER}`).set({ levelProgressPercent: 64 }, { merge: true });
    // Out of range and non-numeric values must not reach the client's ring.
    await firestore.doc(`userProfiles/${A}`).set({ levelProgressPercent: 140 }, { merge: true });

    const active = await getActiveChallengeForCallable(req(OWNER, {}), firestore);
    const byUid = new Map(active.challenge!.participants.map((p) => [p.uid, p.levelProgressPercentSnapshot]));
    assert.equal(byUid.get(OWNER), 64);
    assert.equal(byUid.get(A), 100);
  });

  it("getActiveChallenge returns zero level progress when the profile carries none", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    const active = await getActiveChallengeForCallable(req(OWNER, {}), firestore);
    assert.equal(active.challenge?.participants[0]?.levelProgressPercentSnapshot, 0);
  });

  describe("getActiveChallenge avatarUrlSnapshot", () => {
    it("surfaces a valid stored avatarUrl for a roster member", async () => {
      const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
      await firestore.doc(`userProfiles/${OWNER}`).set({ avatarUrl: VALID_AVATAR_URL }, { merge: true });
      const active = await getActiveChallengeForCallable(req(OWNER, {}), firestore, AVATAR_CONTEXT);
      assert.equal(active.challenge?.participants[0]?.avatarUrlSnapshot, VALID_AVATAR_URL);
    });

    it("resolves a foreign-bucket avatarUrl to empty rather than relaying it", async () => {
      const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
      await firestore.doc(`userProfiles/${OWNER}`).set({ avatarUrl: FOREIGN_AVATAR_URL }, { merge: true });
      const active = await getActiveChallengeForCallable(req(OWNER, {}), firestore, AVATAR_CONTEXT);
      assert.equal(active.challenge?.participants[0]?.avatarUrlSnapshot, "");
    });

    it("resolves a malformed avatarUrl string to empty", async () => {
      const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
      await firestore.doc(`userProfiles/${OWNER}`).set({ avatarUrl: "not a url at all" }, { merge: true });
      const active = await getActiveChallengeForCallable(req(OWNER, {}), firestore, AVATAR_CONTEXT);
      assert.equal(active.challenge?.participants[0]?.avatarUrlSnapshot, "");
    });

    it("resolves a profile with no avatar fields to empty, never undefined", async () => {
      const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
      const active = await getActiveChallengeForCallable(req(OWNER, {}), firestore, AVATAR_CONTEXT);
      assert.equal(active.challenge?.participants[0]?.avatarUrlSnapshot, "");
      assert.equal("avatarUrlSnapshot" in (active.challenge?.participants[0] ?? {}), true);
    });
  });

  /**
   * The tests above call `getActiveChallengeForCallable` — the CORE function
   * — with an explicitly hand-assembled `AVATAR_CONTEXT`, so none of them
   * prove that the deployed `getActiveChallenge` Cloud Function (in
   * challenge/callable.ts) actually injects a real AvatarUrlContext via
   * `avatarUrlContextFromEnvironment()`, or that the bucket name it resolves
   * via `getStorage().bucket().name` at read time agrees with the bucket a
   * stored avatarUrl was built against. This describe block closes that gap
   * by invoking the REAL deployed `getActiveChallenge` callable over HTTP
   * through the Functions emulator (the same real-callable-HTTP pattern
   * challengeCallableSurface.test.ts already uses for this project), with no
   * explicitly-passed avatar context at all.
   *
   * No Storage emulator runs for this project group, so the fixture
   * avatarUrl below is never fetched — only round-tripped as a string — and
   * is built against the bucket name the Admin SDK's default convention
   * (`${projectId}.appspot.com`) resolves to inside the real emulator-hosted
   * function, exercising the production HTTPS branch of
   * resolveProfileAvatarUrl rather than the emulator-host branch.
   */
  describe("getActiveChallenge avatarUrlSnapshot — real callable, no explicit context", () => {
    it("surfaces a real-bucket-shaped avatarUrl through the real getActiveChallenge callable", async () => {
      await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
      await firestore.doc(`userProfiles/${OWNER}`).set({ avatarUrl: REAL_AVATAR_URL }, { merge: true });

      const response = await callEmulatorCallable(
        { functionsOrigin: FUNCTIONS_ORIGIN, projectId: PROJECT_ID, region: "asia-southeast1" },
        "getActiveChallenge",
        { uid: OWNER, token: unsignedEmulatorJwt(OWNER) },
        {},
      );
      assert.equal(response.ok, true);
      if (!response.ok) return;
      const challenge = asRecord(response.data["challenge"]);
      const participants = challenge["participants"] as readonly Readonly<Record<string, unknown>>[];
      const ownerParticipant = participants.find((participant) => participant["uid"] === OWNER);
      assert.ok(ownerParticipant !== undefined);
      assert.notEqual(stringAt(ownerParticipant, "avatarUrlSnapshot"), "");
      assert.equal(stringAt(ownerParticipant, "avatarUrlSnapshot"), REAL_AVATAR_URL);
    });

    it("resolves a foreign-bucket avatarUrl to empty through the real callable, proving the bucket check is live", async () => {
      await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
      await firestore.doc(`userProfiles/${OWNER}`).set({ avatarUrl: REAL_FOREIGN_AVATAR_URL }, { merge: true });

      const response = await callEmulatorCallable(
        { functionsOrigin: FUNCTIONS_ORIGIN, projectId: PROJECT_ID, region: "asia-southeast1" },
        "getActiveChallenge",
        { uid: OWNER, token: unsignedEmulatorJwt(OWNER) },
        {},
      );
      assert.equal(response.ok, true);
      if (!response.ok) return;
      const challenge = asRecord(response.data["challenge"]);
      const participants = challenge["participants"] as readonly Readonly<Record<string, unknown>>[];
      const ownerParticipant = participants.find((participant) => participant["uid"] === OWNER);
      assert.ok(ownerParticipant !== undefined);
      assert.equal(stringAt(ownerParticipant, "avatarUrlSnapshot"), "");
    });
  });

  it("getActiveChallenge returns null when the caller holds no slot", async () => {
    const active = await getActiveChallengeForCallable(req(STRANGER, {}), firestore);
    assert.equal(active.challenge, null);
  });

  it("getChallengeInvitations lists the caller's pending invitations with tier rules", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
    const pending = await getChallengeInvitationsForCallable(req(A, {}), firestore);
    assert.equal(pending.invitations.length, 1);
    assert.equal(pending.invitations[0]?.challengeId, challengeId);
    assert.equal(pending.invitations[0]?.tierId, "42K");
    assert.equal(pending.invitations[0]?.rules?.targetMeters, CHALLENGE_CATALOG["42K"].soloTargetMeters);
  });
});

// ---------------------------------------------------------------------------
// Concurrency (genuine Promise.all races against the emulator)
// ---------------------------------------------------------------------------

describe("challenge concurrency", () => {
  it("create-vs-accept: the recipient ends with exactly one slot", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);

    const outcomes = await Promise.allSettled([
      respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore),
      createChallengeLobbyForCallable(req(A, { tierId: "10K" }), firestore),
    ]);
    const fulfilled = outcomes.filter((outcome) => outcome.status === "fulfilled");
    assert.equal(fulfilled.length, 1, "exactly one of accept / create-own may win A's single slot");

    const slot = await slotDoc(A);
    assert.equal(slot.exists, true);
    const ownLobbies = await firestore.collection("challengeInstances").where("ownerUid", "==", A).get();
    // A holds exactly one slot; it is either the accepted membership or A's own lobby, never both.
    if (slot.get("role") === "member") {
      assert.equal(slot.get("challengeId"), challengeId);
      assert.equal(ownLobbies.size, 0);
    } else {
      assert.equal(ownLobbies.size, 1);
    }
  });

  it("accept-vs-accept: only one wins the last seat, the loser gets no slot", async () => {
    // 20K allows owner + 1 (maxParticipants 2). Seed two PENDING invitations directly
    // to force genuine contention for the single open seat.
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "20K" }), firestore);
    await seedPendingInvitation(challengeId, "20K", A);
    await seedPendingInvitation(challengeId, "20K", B);

    const outcomes = await Promise.allSettled([
      respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore),
      respondToChallengeInvitationForCallable(req(B, { inviteId: inviteId(challengeId, B), response: "accept" }), firestore),
    ]);
    const winners = outcomes.filter((outcome) => outcome.status === "fulfilled");
    const losers = outcomes.filter((outcome) => outcome.status === "rejected") as PromiseRejectedResult[];
    assert.equal(winners.length, 1, "exactly one accept wins the last seat");
    assert.equal(losers.length, 1);
    assert.equal(readChallengeReason(losers[0]!.reason), "LOBBY_FULL");

    const roster = [...(await instanceDoc(challengeId)).get("rosterUids")];
    assert.equal(roster.length, 2);
    // Exactly one of A/B holds a slot; the other holds none.
    const slotA = (await slotDoc(A)).exists;
    const slotB = (await slotDoc(B)).exists;
    assert.equal([slotA, slotB].filter(Boolean).length, 1);
  });

  it("start-vs-accept: no orphan slot or partial roster entry results", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);

    await Promise.allSettled([
      startChallengeForCallable(req(OWNER, { challengeId }), firestore),
      respondToChallengeInvitationForCallable(req(A, { inviteId: inviteId(challengeId, A), response: "accept" }), firestore),
    ]);

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "ACTIVE");
    const roster = [...instance.get("rosterUids")];
    const participant = await participantDoc(challengeId, A);
    const slot = await slotDoc(A);
    if (roster.includes(A)) {
      // A got in before start: fully materialized (participant + slot both present).
      assert.equal(participant.exists, true);
      assert.equal(slot.exists, true);
      assert.equal(slot.get("challengeId"), challengeId);
    } else {
      // A missed the start: no slot, no active participant, invitation not left dangling ACCEPTED.
      assert.equal(slot.exists, false);
      assert.notEqual((await invitationDoc(challengeId, A)).get("status"), "ACCEPTED");
    }
  });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function req(uid: string, data: unknown): CallableRequest {
  return { auth: { uid }, data };
}

// The Functions emulator decodes an unsigned "alg: none" token's payload for
// `request.auth` without a real Auth emulator running — the same technique
// completeRunCallableSurface.test.ts and challengeCallableSurface.test.ts use
// to authenticate a real HTTP callable request in a group with no Auth
// emulator.
function unsignedEmulatorJwt(uid: string): string {
  const header = base64UrlEncode(JSON.stringify({ alg: "none", typ: "JWT" }));
  const payload = base64UrlEncode(JSON.stringify({ sub: uid, uid }));
  return `${header}.${payload}.signature`;
}

function base64UrlEncode(value: string): string {
  return Buffer.from(value).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function inviteId(challengeId: string, recipientUid: string): string {
  return `${challengeId}__${recipientUid}`;
}

async function makeFriends(left: string, right: string): Promise<void> {
  await Promise.all([
    firestore.doc(`users/${left}/friends/${right}`).set({ friendUid: right }),
    firestore.doc(`users/${right}/friends/${left}`).set({ friendUid: left }),
  ]);
}

async function seedPendingInvitation(challengeId: string, tierId: string, recipientUid: string): Promise<void> {
  const id = inviteId(challengeId, recipientUid);
  await makeFriends(OWNER, recipientUid);
  await firestore.doc(`challengeInvitations/${id}`).set({
    inviteId: id,
    challengeId,
    tierId,
    ownerUid: OWNER,
    recipientUid,
    status: "PENDING",
    createdAt: Timestamp.now(),
    expiresAt: Timestamp.fromMillis(Date.now() + 3_600_000),
  });
}

async function seedPremiumHold(uid: string, challengeId: string, graceExpiresAtMs: number): Promise<void> {
  await firestore.doc(`challengePremiumHolds/${uid}`).set({
    uid,
    challengeId,
    tierId: "100K",
    role: uid === OWNER ? "owner" : "member",
    lapsedAt: Timestamp.fromMillis(graceExpiresAtMs - 24 * 60 * 60 * 1000),
    graceExpiresAt: Timestamp.fromMillis(graceExpiresAtMs),
  });
}

async function backdateExpiry(challengeId: string): Promise<void> {
  await firestore.doc(`challengeInstances/${challengeId}`).update({
    lobbyExpiresAt: Timestamp.fromMillis(Date.now() - 1_000),
  });
}

async function instanceDoc(challengeId: string) {
  return firestore.doc(`challengeInstances/${challengeId}`).get();
}
async function participantDoc(challengeId: string, uid: string) {
  return firestore.doc(`challengeInstances/${challengeId}/participants/${uid}`).get();
}
async function invitationDoc(challengeId: string, recipientUid: string) {
  return firestore.doc(`challengeInvitations/${inviteId(challengeId, recipientUid)}`).get();
}
async function slotDoc(uid: string) {
  return firestore.doc(`challengeSlots/${uid}`).get();
}

async function deleteCollection(name: string): Promise<void> {
  const snapshot = await firestore.collection(name).get();
  await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
}

async function rejectsReason(fn: () => Promise<unknown>, reason: ChallengeReason): Promise<void> {
  await assert.rejects(fn, (error: unknown) => {
    const actual = readChallengeReason(error);
    assert.equal(actual, reason, `expected reason ${reason} but got ${String(actual)}`);
    return true;
  });
}
