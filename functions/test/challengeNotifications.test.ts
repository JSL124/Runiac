// Todo 7 emulator + pure tests: privacy-safe Challenge notifications, inbox
// payloads, deterministic-key dedup, terminal-state independence, and the
// allowlisted payload surface.

import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore, type QueryDocumentSnapshot } from "firebase-admin/firestore";

import { completeRunForCallable } from "../src/run/completeRun.js";
import {
  createChallengeLobbyForCallable,
  inviteChallengeFriendsForCallable,
  respondToChallengeInvitationForCallable,
  startChallengeForCallable,
  type CallableRequest,
} from "../src/challenge/challengeLobbyCore.js";
import {
  abandonChallengeForCallable,
  leaveChallengeForCallable,
  runChallengeSettlementSweep,
  settleFailedChallenge,
  settleSucceededChallenge,
} from "../src/challenge/challengeSettlementCore.js";
import {
  ALLOWED_CHALLENGE_PAYLOAD_KEYS,
  challengeDeliveryKey,
  emitChallengeResultReadyNotifications,
  firestoreChallengeNotificationWriter,
  planChallengeNotifications,
  type ChallengeNotificationWriter,
} from "../src/challenge/challengeNotifications.js";

const PROJECT_ID = "demo-runiac-challenge";
const OWNER = "ntf-owner";
const A = "ntf-friend-a";
const B = "ntf-friend-b";
const ALL_UIDS = [OWNER, A, B] as const;
const FAR_FUTURE_MS = Date.parse("2027-12-31T00:00:00.000Z");

// Envelope keys permitted at the inbox doc top level (everything else is the
// client-visible `data` payload, which is separately allowlisted).
const ALLOWED_ENVELOPE_KEYS = [
  "ownerUid",
  "deliveryKey",
  "title",
  "body",
  "createdAt",
  "readAt",
  "data",
  "updatedAt",
] as const;

let firestore: Firestore;
let sessionCounter = 0;

before(() => {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  firestore = getFirestore();
});

beforeEach(async () => {
  await firestore.recursiveDelete(firestore.collection("challengeInstances"));
  await firestore.recursiveDelete(firestore.collection("users"));
  await firestore.recursiveDelete(firestore.collection("notificationInbox"));
  await Promise.all(
    [
      "challengeInvitations",
      "challengeSlots",
      "challengeRewardGrants",
      "activities",
      "runSummaries",
      "progressionEvents",
      "userProfiles",
      "generatedPlans",
      "planProgress",
      "adaptivePlanEstimates",
      "leaderboardContributions",
    ].map(deleteCollection),
  );
  await Promise.all(
    ALL_UIDS.map((uid) =>
      firestore.doc(`userProfiles/${uid}`).set({
        displayName: `Runner ${uid}`,
        nickname: `Runner ${uid}`,
        locationLabel: "Jurong East, Singapore",
      }),
    ),
  );
  await Promise.all([makeFriends(OWNER, A), makeFriends(OWNER, B)]);
});

// ---------------------------------------------------------------------------
// Pure planner + allowlist
// ---------------------------------------------------------------------------

describe("planChallengeNotifications (pure)", () => {
  it("builds a deterministic delivery key and an allowlisted payload only", () => {
    const [notification] = planChallengeNotifications({
      notificationKind: "challenge_result_ready",
      route: "challengeResult",
      title: "Challenge result ready",
      body: "Your challenge result is ready to view.",
      challengeId: "cid-1",
      tierId: "10K",
      version: "TARGET_REACHED",
      recipients: [{ uid: A, outcome: "SUCCEEDED", creditedMeters: 4200 }],
    });
    assert.ok(notification);
    assert.equal(
      notification.deliveryKey,
      challengeDeliveryKey("cid-1", "challenge_result_ready", A, "TARGET_REACHED"),
    );
    assert.equal(notification.deliveryKey, "cid-1:challenge_result_ready:ntf-friend-a:TARGET_REACHED");
    assertPayloadAllowlisted(notification.payload as Record<string, unknown>);
    assert.deepEqual(notification.payload, {
      challengeId: "cid-1",
      tierId: "10K",
      kind: "challenge_result_ready",
      route: "challengeResult",
      outcome: "SUCCEEDED",
      creditedMeters: 4200,
    });
  });

  it("omits optional keys when absent and dedupes repeated recipient uids", () => {
    const notifications = planChallengeNotifications({
      notificationKind: "challenge_started",
      route: "challengeProgress",
      title: "Challenge started",
      body: "Your distance challenge is now underway.",
      challengeId: "cid-2",
      tierId: "42K",
      version: "start",
      recipients: [{ uid: A }, { uid: A }, { uid: "" }],
    });
    assert.equal(notifications.length, 1);
    assert.deepEqual(Object.keys(notifications[0]!.payload).sort(), [
      "challengeId",
      "kind",
      "route",
      "tierId",
    ]);
  });
});

// ---------------------------------------------------------------------------
// Deterministic-key dedup (create-collision guard)
// ---------------------------------------------------------------------------

describe("firestoreChallengeNotificationWriter dedup", () => {
  it("writes once and reports a duplicate on replay of the same delivery key", async () => {
    const writer = firestoreChallengeNotificationWriter(firestore);
    const [notification] = planChallengeNotifications({
      notificationKind: "challenge_badge_issued",
      route: "challengeResult",
      title: "Badge earned",
      body: "You earned a challenge badge.",
      challengeId: "cid-dedup",
      tierId: "10K",
      version: "TARGET_REACHED",
      recipients: [{ uid: A, outcome: "SUCCEEDED" }],
    });
    assert.ok(notification);

    const first = await writer.persist(notification, Date.parse("2026-07-13T00:00:00.000Z"));
    const second = await writer.persist(notification, Date.parse("2026-07-13T01:00:00.000Z"));

    assert.equal(first, "written");
    assert.equal(second, "duplicate");
    const items = await inboxItems(A);
    const matching = items.filter((doc) => doc.id === notification.deliveryKey);
    assert.equal(matching.length, 1);
    assert.equal(matching[0]!.get("createdAt").toMillis(), Date.parse("2026-07-13T00:00:00.000Z"));
  });
});

// ---------------------------------------------------------------------------
// Recipient targeting per event kind
// ---------------------------------------------------------------------------

describe("recipient targeting", () => {
  it("invitation received targets only the invited recipient", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);

    assert.deepEqual(await recipientsFor(challengeId, "challenge_invitation_received"), [A]);
  });

  it("challenge started targets the whole roster except the owner", async () => {
    const challengeId = await startedGroup("10K");
    assert.deepEqual(await recipientsFor(challengeId, "challenge_started"), [A]);
  });

  it("participant left targets the remaining active roster, not the leaver", async () => {
    const challengeId = await startedGroup("10K");
    await leaveChallengeForCallable(req(A, { challengeId }), firestore);

    // Only the still-active owner is pinged; the leaver A is not.
    assert.deepEqual(await recipientsFor(challengeId, "challenge_participant_left"), [OWNER]);
  });

  it("owner cancelled targets non-owner participants only", async () => {
    const challengeId = await startedGroup("10K");
    await abandonChallengeForCallable(req(OWNER, { challengeId }), firestore);

    assert.deepEqual(await recipientsFor(challengeId, "challenge_owner_cancelled"), [A]);
  });

  it("result ready + badge issued target settled participants; badge only the earner", async () => {
    // Mixed eligibility: OWNER clears the 3km personal minimum, A does not.
    const challengeId = await startedGroup("10K");
    await run(OWNER, 8000);
    await run(A, 2000); // team = 10000 -> SETTLING; A below personal minimum

    const result = await settleSucceededChallenge(firestore, challengeId);
    assert.equal(result.finalized, true);

    assert.deepEqual(await recipientsFor(challengeId, "challenge_result_ready"), [A, OWNER].sort());
    assert.deepEqual(await recipientsFor(challengeId, "challenge_badge_issued"), [OWNER]);

    // Each recipient sees ONLY their own outcome + metres.
    const ownerResult = await notificationData(OWNER, challengeId, "challenge_result_ready");
    const aResult = await notificationData(A, challengeId, "challenge_result_ready");
    assert.equal(ownerResult["outcome"], "SUCCEEDED");
    assert.equal(ownerResult["creditedMeters"], 8000);
    assert.equal(aResult["outcome"], "INELIGIBLE");
    assert.equal(aResult["creditedMeters"], 2000);
  });

  it("deadline failure result ready targets all participants with FAILED outcome", async () => {
    const challengeId = await startedGroup("10K");
    await run(OWNER, 1000);

    const settled = await settleFailedChallenge(firestore, challengeId, FAR_FUTURE_MS);
    assert.equal(settled.settled, true);

    assert.deepEqual(await recipientsFor(challengeId, "challenge_result_ready"), [A, OWNER].sort());
    const ownerResult = await notificationData(OWNER, challengeId, "challenge_result_ready");
    assert.equal(ownerResult["outcome"], "FAILED");
    // A deadline failure grants no badges, so nobody is badge-notified.
    assert.deepEqual(await recipientsFor(challengeId, "challenge_badge_issued"), []);
  });
});

// ---------------------------------------------------------------------------
// Idempotent delivery across settlement / sweep reruns
// ---------------------------------------------------------------------------

describe("idempotent delivery", () => {
  it("delivers result ready + badge exactly once across repeated sweeps", async () => {
    const challengeId = await startedGroup("10K");
    await run(OWNER, 7000);
    await run(A, 3000); // team = 10000 -> SETTLING; both eligible

    // First sweep finalizes success and emits; further sweeps are no-ops.
    await runChallengeSettlementSweep(firestore, Date.now());
    await runChallengeSettlementSweep(firestore, Date.now());
    await settleSucceededChallenge(firestore, challengeId); // explicit terminal replay

    for (const uid of [OWNER, A]) {
      assert.equal(await countFor(uid, challengeId, "challenge_result_ready"), 1);
      assert.equal(await countFor(uid, challengeId, "challenge_badge_issued"), 1);
    }
  });

  it("does not re-notify a leave replay", async () => {
    const challengeId = await startedGroup("10K");
    await leaveChallengeForCallable(req(A, { challengeId }), firestore);
    await leaveChallengeForCallable(req(A, { challengeId }), firestore); // idempotent replay

    assert.equal(await countFor(OWNER, challengeId, "challenge_participant_left"), 1);
  });
});

// ---------------------------------------------------------------------------
// Terminal-state independence
// ---------------------------------------------------------------------------

describe("terminal-state independence", () => {
  it("a dispatch failure never throws and never mutates committed terminal state", async () => {
    const challengeId = await startedGroup("10K");
    await run(OWNER, 1000);
    await settleFailedChallenge(firestore, challengeId, FAR_FUTURE_MS);

    const before = await instanceDoc(challengeId);
    assert.equal(before.get("status"), "FAILED");

    const throwingWriter: ChallengeNotificationWriter = {
      persist: async () => {
        throw new Error("simulated dispatch/persist failure");
      },
    };

    // The emitter must swallow the failure: it neither rejects...
    await assert.doesNotReject(() =>
      emitChallengeResultReadyNotifications(firestore, challengeId, Date.now(), {
        writer: throwingWriter,
      }),
    );

    // ...nor perturbs the committed terminal instance / participant / history.
    const after = await instanceDoc(challengeId);
    assert.equal(after.get("status"), "FAILED");
    assert.equal(after.get("terminalReason"), "DEADLINE_FAILED");
    assert.equal((await participantDoc(challengeId, OWNER)).get("status"), "FAILED");
    assert.equal((await historyDoc(OWNER, challengeId)).get("outcome"), "FAILED");
  });

  it("settlement commits its terminal state even though notifications ride alongside", async () => {
    const challengeId = await startedGroup("10K");
    await run(OWNER, 7000);
    await run(A, 3000);
    const result = await settleSucceededChallenge(firestore, challengeId);

    assert.equal(result.finalized, true);
    assert.equal((await instanceDoc(challengeId)).get("status"), "SUCCEEDED");
    assert.equal((await grantDoc(challengeId, OWNER)).get("status"), "ISSUED");
    assert.equal((await badgeDoc(OWNER, "10K")).exists, true);
  });
});

// ---------------------------------------------------------------------------
// Payload allowlist + terminal history linkage
// ---------------------------------------------------------------------------

describe("payload allowlist and history linkage", () => {
  it("persists only allowlisted payload keys across every event kind", async () => {
    // (1) Success flow → invitation_received, challenge_started, result_ready,
    // badge_issued. Settlement releases the owner's slot for the next flow.
    const invited = await createChallengeLobbyForCallable(req(OWNER, { tierId: "10K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId: invited.challengeId, uids: [A] }), firestore);
    await respondToChallengeInvitationForCallable(
      req(A, { inviteId: `${invited.challengeId}__${A}`, response: "accept" }),
      firestore,
    );
    await startChallengeForCallable(req(OWNER, { challengeId: invited.challengeId }), firestore);
    await run(OWNER, 7000);
    await run(A, 3000);
    await settleSucceededChallenge(firestore, invited.challengeId);

    // (2) A three-person challenge → participant_left (A leaves) then
    // owner_cancelled (B is still active when the owner abandons).
    const social = await createChallengeLobbyForCallable(req(OWNER, { tierId: "42K" }), firestore);
    await inviteChallengeFriendsForCallable(req(OWNER, { challengeId: social.challengeId, uids: [A, B] }), firestore);
    await respondToChallengeInvitationForCallable(
      req(A, { inviteId: `${social.challengeId}__${A}`, response: "accept" }),
      firestore,
    );
    await respondToChallengeInvitationForCallable(
      req(B, { inviteId: `${social.challengeId}__${B}`, response: "accept" }),
      firestore,
    );
    await startChallengeForCallable(req(OWNER, { challengeId: social.challengeId }), firestore);
    await leaveChallengeForCallable(req(A, { challengeId: social.challengeId }), firestore);
    await abandonChallengeForCallable(req(OWNER, { challengeId: social.challengeId }), firestore);

    let inspected = 0;
    for (const uid of ALL_UIDS) {
      for (const doc of await inboxItems(uid)) {
        inspected += 1;
        const topLevel = Object.keys(doc.data());
        for (const key of topLevel) {
          assert.ok(
            (ALLOWED_ENVELOPE_KEYS as readonly string[]).includes(key),
            `unexpected top-level inbox key: ${key}`,
          );
        }
        assertPayloadAllowlisted(doc.get("data") as Record<string, unknown>);
        // Privacy: never any other user's identity / metres / route geometry.
        const data = doc.get("data") as Record<string, unknown>;
        for (const forbidden of ["uid", "rosterUids", "friends", "route_geometry", "activityId", "displayName"]) {
          assert.equal(data[forbidden], undefined, `payload leaked forbidden key: ${forbidden}`);
        }
      }
    }
    assert.ok(inspected >= 5, `expected several notifications, inspected ${inspected}`);
  });

  it("terminal history states match the enum exactly with the correct destination hint", async () => {
    // SUCCEEDED + INELIGIBLE (mixed group success)
    const successCid = await startedGroup("10K");
    await run(OWNER, 8000);
    await run(A, 2000);
    await settleSucceededChallenge(firestore, successCid);
    assert.equal((await historyDoc(OWNER, successCid)).get("outcome"), "SUCCEEDED");
    assert.equal((await historyDoc(A, successCid)).get("outcome"), "INELIGIBLE");
    assert.equal(
      (await notificationData(OWNER, successCid, "challenge_result_ready"))["route"],
      "challengeResult",
    );

    // FAILED (deadline)
    const failCid = await startedGroup("10K");
    await run(OWNER, 500);
    await settleFailedChallenge(firestore, failCid, FAR_FUTURE_MS);
    assert.equal((await historyDoc(OWNER, failCid)).get("outcome"), "FAILED");

    // CANCELLED (owner abandon)
    const cancelCid = await startedGroup("20K");
    await abandonChallengeForCallable(req(OWNER, { challengeId: cancelCid }), firestore);
    assert.equal((await historyDoc(A, cancelCid)).get("outcome"), "CANCELLED");
    assert.equal(
      (await notificationData(A, cancelCid, "challenge_owner_cancelled"))["route"],
      "challengeResult",
    );

    // LEFT (non-owner leave)
    const leftCid = await startedGroup("42K");
    await leaveChallengeForCallable(req(A, { challengeId: leftCid }), firestore);
    assert.equal((await historyDoc(A, leftCid)).get("outcome"), "LEFT");
    assert.equal(
      (await notificationData(OWNER, leftCid, "challenge_participant_left"))["route"],
      "challengeProgress",
    );
  });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function req(uid: string, data: unknown): CallableRequest {
  return { auth: { uid }, data };
}

function assertPayloadAllowlisted(payload: Record<string, unknown>): void {
  for (const key of Object.keys(payload)) {
    assert.ok(
      (ALLOWED_CHALLENGE_PAYLOAD_KEYS as readonly string[]).includes(key),
      `unexpected payload key: ${key}`,
    );
  }
}

async function makeFriends(left: string, right: string): Promise<void> {
  await Promise.all([
    firestore.doc(`users/${left}/friends/${right}`).set({ friendUid: right }),
    firestore.doc(`users/${right}/friends/${left}`).set({ friendUid: left }),
  ]);
}

async function startedGroup(tierId: string): Promise<string> {
  const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId }), firestore);
  await inviteChallengeFriendsForCallable(req(OWNER, { challengeId, uids: [A] }), firestore);
  await respondToChallengeInvitationForCallable(
    req(A, { inviteId: `${challengeId}__${A}`, response: "accept" }),
    firestore,
  );
  await startChallengeForCallable(req(OWNER, { challengeId }), firestore);
  return challengeId;
}

function runPayload(distanceMeters: number): Record<string, unknown> {
  const paceSecondsPerKm = 300;
  const durationSeconds = Math.max(1, Math.round((distanceMeters / 1000) * paceSecondsPerKm));
  const completedAtMs = Date.now();
  const startedAtMs = completedAtMs - durationSeconds * 1000;
  sessionCounter += 1;
  return {
    clientRunSessionId: `notification-run-${sessionCounter}`,
    startedAt: new Date(startedAtMs).toISOString(),
    completedAt: new Date(completedAtMs).toISOString(),
    durationSeconds,
    distanceMeters,
    avgPaceSecondsPerKm: paceSecondsPerKm,
    source: "mobile",
    routePrivacy: "private",
  };
}

async function run(uid: string, distanceMeters: number): Promise<void> {
  await completeRunForCallable({ auth: { uid }, data: runPayload(distanceMeters) }, firestore);
}

async function inboxItems(uid: string) {
  return (await firestore.collection("notificationInbox").doc(uid).collection("items").get()).docs;
}

function matches(doc: QueryDocumentSnapshot, challengeId: string, kind: string): boolean {
  const data = doc.get("data") as Record<string, unknown> | undefined;
  return data?.["challengeId"] === challengeId && data?.["kind"] === kind;
}

async function recipientsFor(challengeId: string, kind: string): Promise<string[]> {
  const recipients: string[] = [];
  for (const uid of ALL_UIDS) {
    const items = await inboxItems(uid);
    if (items.some((doc) => matches(doc, challengeId, kind))) recipients.push(uid);
  }
  return recipients.sort();
}

async function countFor(uid: string, challengeId: string, kind: string): Promise<number> {
  return (await inboxItems(uid)).filter((doc) => matches(doc, challengeId, kind)).length;
}

async function notificationData(
  uid: string,
  challengeId: string,
  kind: string,
): Promise<Record<string, unknown>> {
  const items = await inboxItems(uid);
  const match = items.find((doc) => matches(doc, challengeId, kind));
  assert.ok(match, `no ${kind} notification for ${uid} on ${challengeId}`);
  return match.get("data") as Record<string, unknown>;
}

async function instanceDoc(challengeId: string) {
  return firestore.doc(`challengeInstances/${challengeId}`).get();
}
async function participantDoc(challengeId: string, uid: string) {
  return firestore.doc(`challengeInstances/${challengeId}/participants/${uid}`).get();
}
async function grantDoc(challengeId: string, uid: string) {
  return firestore.doc(`challengeRewardGrants/${challengeId}_${uid}`).get();
}
async function badgeDoc(uid: string, tierId: string) {
  return firestore.doc(`users/${uid}/challengeBadges/${tierId}`).get();
}
async function historyDoc(uid: string, challengeId: string) {
  return firestore.doc(`users/${uid}/challengeHistory/${challengeId}`).get();
}

async function deleteCollection(name: string): Promise<void> {
  const snapshot = await firestore.collection(name).get();
  await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
}
