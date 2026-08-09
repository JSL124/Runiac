// Todo 6 emulator tests: leave, abandon, deadline settlement, idempotent badge
// grants, and the one-minute settlement sweep.

import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { completeRunForCallable } from "../src/run/completeRun.js";
import {
  createChallengeLobbyForCallable,
  getActiveChallengeForCallable,
  inviteChallengeFriendsForCallable,
  respondToChallengeInvitationForCallable,
  startChallengeForCallable,
  type CallableRequest,
} from "../src/challenge/challengeLobbyCore.js";
import {
  abandonChallengeForCallable,
  freezeChallengeSuccess,
  leaveChallengeForCallable,
  planSuccessSettlementAction,
  runChallengeSettlementSweep,
  settleSucceededChallenge,
} from "../src/challenge/challengeSettlementCore.js";
import { readChallengeReason, type ChallengeReason } from "../src/challenge/challengeErrors.js";

const PROJECT_ID = "demo-runiac-challenge";
const OWNER = "stl-owner";
const A = "stl-friend-a";
const B = "stl-friend-b";
const C = "stl-friend-c";
const ALL_UIDS = [OWNER, A, B, C] as const;

let firestore: Firestore;
let sessionCounter = 0;

before(() => {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  firestore = getFirestore();
});

beforeEach(async () => {
  await firestore.recursiveDelete(firestore.collection("challengeInstances"));
  await firestore.recursiveDelete(firestore.collection("users"));
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
  await Promise.all([makeFriends(OWNER, A), makeFriends(OWNER, B), makeFriends(B, C)]);
});

// ---------------------------------------------------------------------------
// Pure settlement planner
// ---------------------------------------------------------------------------

describe("planSuccessSettlementAction (pure)", () => {
  it("maps frozen eligibility onto settlement actions", () => {
    assert.equal(planSuccessSettlementAction("ACTIVE", "PENDING"), "SETTLE_SUCCEEDED");
    assert.equal(planSuccessSettlementAction("ACTIVE", "NOT_ELIGIBLE"), "SETTLE_INELIGIBLE");
    assert.equal(planSuccessSettlementAction("LEFT", "NOT_ELIGIBLE"), "PRESERVE_LEFT");
    assert.equal(planSuccessSettlementAction("SUCCEEDED", "PENDING"), "SKIP");
    assert.equal(planSuccessSettlementAction("CANCELLED", "NOT_ELIGIBLE"), "SKIP");
  });
});

// ---------------------------------------------------------------------------
// leaveChallenge
// ---------------------------------------------------------------------------

describe("leaveChallenge", () => {
  it("marks a non-owner LEFT, retains metres, releases only their slot, writes history", async () => {
    const challengeId = await startedGroup("42K");
    await run(A, 5000);
    await run(OWNER, 4000);

    const result = await leaveChallengeForCallable(req(A, { challengeId }), firestore);
    assert.equal(result.idempotent, false);

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "ACTIVE");
    assert.equal(instance.get("teamMeters"), 9000); // A's metres retained
    assert.deepEqual(instance.get("rosterUids"), [OWNER, A]); // roster locked

    const participant = await participantDoc(challengeId, A);
    assert.equal(participant.get("status"), "LEFT");
    assert.equal(participant.get("creditedMeters"), 5000);
    assert.equal(participant.get("reward"), "NOT_ELIGIBLE");

    assert.equal((await slotDoc(A)).exists, false);
    assert.equal((await slotDoc(OWNER)).exists, true); // only A's slot released

    const history = await historyDoc(A, challengeId);
    assert.equal(history.get("outcome"), "LEFT");
    assert.equal(history.get("personalMeters"), 5000);
    assert.equal(history.get("teamMeters"), 9000); // team total at exit
    assert.equal(history.get("terminalReason"), undefined); // instance still running
  });

  it("is idempotent for an already-LEFT participant", async () => {
    const challengeId = await startedGroup("42K");
    await leaveChallengeForCallable(req(A, { challengeId }), firestore);
    const replay = await leaveChallengeForCallable(req(A, { challengeId }), firestore);
    assert.equal(replay.idempotent, true);
  });

  it("rejects a suspended participant with permission-denied before recording their departure (defence-in-depth)", async () => {
    const challengeId = await startedGroup("42K");
    await firestore.doc(`users/${A}`).set({ accountStatus: "suspended" });

    await assert.rejects(
      () => leaveChallengeForCallable(req(A, { challengeId }), firestore),
      (error: unknown) => error instanceof HttpsError && error.code === "permission-denied",
    );

    const participant = await participantDoc(challengeId, A);
    assert.notEqual(participant.get("status"), "LEFT");
  });

  it("rejects the owner with OWNER_CANNOT_LEAVE", async () => {
    const challengeId = await startedGroup("42K");
    await rejectsReason(
      () => leaveChallengeForCallable(req(OWNER, { challengeId }), firestore),
      "OWNER_CANNOT_LEAVE",
    );
  });

  it("rejects non-participants and non-ACTIVE instances with stable codes", async () => {
    const challengeId = await startedGroup("42K");
    await rejectsReason(
      () => leaveChallengeForCallable(req(B, { challengeId }), firestore),
      "NOT_A_PARTICIPANT",
    );
    // A RECRUITING lobby member must withdraw, not leave.
    const { challengeId: lobbyId } = await createChallengeLobbyForCallable(
      req(B, { tierId: "42K" }),
      firestore,
    );
    await inviteChallengeFriendsForCallable(req(B, { challengeId: lobbyId, uids: [C] }), firestore);
    await respondToChallengeInvitationForCallable(
      req(C, { inviteId: `${lobbyId}__${C}`, response: "accept" }),
      firestore,
    );
    await rejectsReason(
      () => leaveChallengeForCallable(req(C, { challengeId: lobbyId }), firestore),
      "CHALLENGE_NOT_ACTIVE",
    );
    await rejectsReason(
      () => leaveChallengeForCallable(req(A, { challengeId: "missing" }), firestore),
      "CHALLENGE_NOT_FOUND",
    );
  });

  it("permits no re-entry: invitation replay re-enters nothing, but a fresh lobby may be created", async () => {
    const challengeId = await startedGroup("42K");
    await leaveChallengeForCallable(req(A, { challengeId }), firestore);

    // A's accepted invitation is terminal; replaying the response performs NO
    // writes (idempotent echo) — the participant stays LEFT and no slot returns.
    const replay = await respondToChallengeInvitationForCallable(
      req(A, { inviteId: `${challengeId}__${A}`, response: "accept" }),
      firestore,
    );
    assert.equal(replay.idempotent, true);
    const participant = await participantDoc(challengeId, A);
    assert.equal(participant.get("status"), "LEFT"); // participant doc stays LEFT
    assert.equal((await slotDoc(A)).exists, false); // no slot re-acquired

    // Slot is free: A may start a new, separate challenge.
    const fresh = await createChallengeLobbyForCallable(req(A, { tierId: "10K" }), firestore);
    assert.equal(fresh.idempotent, false);
  });
});

// ---------------------------------------------------------------------------
// abandonChallenge
// ---------------------------------------------------------------------------

describe("abandonChallenge", () => {
  it("owner cancels for everyone: participants CANCELLED, slots released, history written", async () => {
    const challengeId = await startedGroup("42K");
    await run(A, 5000);

    const result = await abandonChallengeForCallable(req(OWNER, { challengeId }), firestore);
    assert.equal(result.idempotent, false);

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "CANCELLED");
    assert.equal(instance.get("terminalReason"), "OWNER_ABANDONED");
    assert.equal((await participantDoc(challengeId, OWNER)).get("status"), "CANCELLED");
    assert.equal((await participantDoc(challengeId, A)).get("status"), "CANCELLED");
    assert.equal((await slotDoc(OWNER)).exists, false);
    assert.equal((await slotDoc(A)).exists, false);

    for (const uid of [OWNER, A]) {
      const history = await historyDoc(uid, challengeId);
      assert.equal(history.get("outcome"), "CANCELLED");
      assert.equal(history.get("terminalReason"), "OWNER_ABANDONED");
    }
    const grants = await firestore.collection("challengeRewardGrants").get();
    assert.equal(grants.size, 0);
  });

  it("preserves a leaver's LEFT history and merges the terminal reason", async () => {
    const challengeId = await startedGroup("42K");
    await run(A, 5000);
    await leaveChallengeForCallable(req(A, { challengeId }), firestore);
    await abandonChallengeForCallable(req(OWNER, { challengeId }), firestore);

    assert.equal((await participantDoc(challengeId, A)).get("status"), "LEFT"); // not CANCELLED
    const history = await historyDoc(A, challengeId);
    assert.equal(history.get("outcome"), "LEFT");
    assert.equal(history.get("terminalReason"), "OWNER_ABANDONED");
    assert.equal(history.get("personalMeters"), 5000);
  });

  it("rejects non-owners, is idempotent on replay, and rejects settling races", async () => {
    const challengeId = await startedGroup("42K");
    await rejectsReason(
      () => abandonChallengeForCallable(req(A, { challengeId }), firestore),
      "NOT_CHALLENGE_OWNER",
    );
    await abandonChallengeForCallable(req(OWNER, { challengeId }), firestore);
    const replay = await abandonChallengeForCallable(req(OWNER, { challengeId }), firestore);
    assert.equal(replay.idempotent, true);
  });

  it("rejects a suspended owner with permission-denied before cancelling the challenge (defence-in-depth)", async () => {
    const challengeId = await startedGroup("42K");
    await firestore.doc(`users/${OWNER}`).set({ accountStatus: "banned" });

    await assert.rejects(
      () => abandonChallengeForCallable(req(OWNER, { challengeId }), firestore),
      (error: unknown) => error instanceof HttpsError && error.code === "permission-denied",
    );

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "ACTIVE");
  });
});

// ---------------------------------------------------------------------------
// Success settlement + idempotent grants and badges
// ---------------------------------------------------------------------------

describe("success settlement", () => {
  it("solo success: owner eligible by reaching target; grant, badge, history, slot release", async () => {
    const challengeId = await startedSolo(OWNER, "10K");
    await run(OWNER, 10000); // -> SETTLING

    const result = await settleSucceededChallenge(firestore, challengeId);
    assert.deepEqual(result, {
      settled: true,
      finalized: true,
      granted: [OWNER],
      alreadyGranted: [],
    });

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "SUCCEEDED");
    assert.equal(instance.get("terminalReason"), "TARGET_REACHED");

    const participant = await participantDoc(challengeId, OWNER);
    assert.equal(participant.get("status"), "SUCCEEDED");
    assert.equal(participant.get("reward"), "ISSUED");

    const grant = await grantDoc(challengeId, OWNER);
    assert.equal(grant.get("status"), "ISSUED");
    assert.equal(grant.get("tierId"), "10K");
    const badge = await badgeDoc(OWNER, "10K");
    assert.equal(badge.get("firstEarnedChallengeId"), challengeId);
    assert.equal(badge.get("catalogVersion"), "challenge-distance-v1");

    const history = await historyDoc(OWNER, challengeId);
    assert.equal(history.get("outcome"), "SUCCEEDED");
    assert.equal(history.get("terminalReason"), "TARGET_REACHED");
    assert.equal(history.get("teamMeters"), 10000);

    assert.equal((await slotDoc(OWNER)).exists, false);
    const view = await getActiveChallengeForCallable(req(OWNER, {}), firestore);
    assert.equal(view.challenge, null); // result-ready: no active challenge

    console.log(
      `EVIDENCE solo-success-grant-badge ${JSON.stringify({
        grant: grant.data(),
        badge: { ...badge.data(), earnedAt: "ts" },
        instanceStatus: instance.get("status"),
      })}`,
    );
  });

  it("group success with mixed eligibility: under-minimum member is INELIGIBLE with no grant or badge", async () => {
    const challengeId = await startedGroup("42K"); // min 7000
    await run(A, 6000); // under minimum
    await run(OWNER, 36000); // total 42000 -> SETTLING

    const result = await settleSucceededChallenge(firestore, challengeId);
    assert.deepEqual(result.granted, [OWNER]);

    assert.equal((await participantDoc(challengeId, OWNER)).get("status"), "SUCCEEDED");
    assert.equal((await participantDoc(challengeId, A)).get("status"), "INELIGIBLE");
    assert.equal((await grantDoc(challengeId, OWNER)).exists, true);
    assert.equal((await grantDoc(challengeId, A)).exists, false);
    assert.equal((await badgeDoc(OWNER, "42K")).exists, true);
    assert.equal((await badgeDoc(A, "42K")).exists, false);

    const ownerHistory = await historyDoc(OWNER, challengeId);
    assert.equal(ownerHistory.get("outcome"), "SUCCEEDED");
    const aHistory = await historyDoc(A, challengeId);
    assert.equal(aHistory.get("outcome"), "INELIGIBLE");
    assert.equal(aHistory.get("personalMeters"), 6000);
    assert.equal(aHistory.get("terminalReason"), "TARGET_REACHED");

    console.log(
      `EVIDENCE group-mixed-grants ${JSON.stringify({
        grants: (await firestore.collection("challengeRewardGrants").get()).docs.map((d) => d.data()),
        ownerBadge: (await badgeDoc(OWNER, "42K")).exists,
        memberBadge: (await badgeDoc(A, "42K")).exists,
      })}`,
    );
  });

  it("LEFT before success: metres retained, no badge, LEFT history with merged reason", async () => {
    const challengeId = await startedGroup("42K");
    await run(A, 8000); // above minimum — would have been eligible
    await leaveChallengeForCallable(req(A, { challengeId }), firestore);
    await run(OWNER, 34000); // total 42000 -> SETTLING (A's metres counted)

    assert.equal((await instanceDoc(challengeId)).get("teamMeters"), 42000);
    await settleSucceededChallenge(firestore, challengeId);

    assert.equal((await participantDoc(challengeId, A)).get("status"), "LEFT");
    assert.equal((await grantDoc(challengeId, A)).exists, false);
    assert.equal((await badgeDoc(A, "42K")).exists, false);
    const history = await historyDoc(A, challengeId);
    assert.equal(history.get("outcome"), "LEFT");
    assert.equal(history.get("terminalReason"), "TARGET_REACHED");
    assert.equal((await badgeDoc(OWNER, "42K")).exists, true);
  });

  it("badge grant retry after an injected failure yields exactly one grant and one badge", async () => {
    const challengeId = await startedSolo(OWNER, "10K");
    await run(OWNER, 10000); // -> SETTLING

    // Injected failure: freeze commits (slots released, results frozen) but the
    // process "crashes" before grant issuance and finalization.
    const freeze = await freezeChallengeSuccess(firestore, challengeId, Date.now());
    assert.equal(freeze.kind, "frozen");
    assert.equal((await instanceDoc(challengeId)).get("status"), "SETTLING"); // not yet terminal
    assert.equal((await slotDoc(OWNER)).exists, false); // slot already free
    assert.equal((await grantDoc(challengeId, OWNER)).exists, false); // grant missing

    // Retry (what the sweep does): grants issue idempotently, instance finalizes.
    const first = await settleSucceededChallenge(firestore, challengeId);
    assert.deepEqual(first.granted, [OWNER]);
    assert.equal(first.finalized, true);

    // Rerun is a no-op for already-granted users and never regresses terminal.
    const rerun = await settleSucceededChallenge(firestore, challengeId);
    assert.deepEqual(rerun.granted, []);
    assert.equal(rerun.finalized, false);

    const grants = await firestore.collection("challengeRewardGrants").get();
    assert.equal(grants.size, 1);
    const badges = await firestore.collection(`users/${OWNER}/challengeBadges`).get();
    assert.equal(badges.size, 1);
    assert.equal((await instanceDoc(challengeId)).get("status"), "SUCCEEDED");
  });

  it("repeated tier success adds history but keeps exactly one badge ownership doc", async () => {
    const firstChallenge = await startedSolo(OWNER, "10K");
    await run(OWNER, 10000);
    await settleSucceededChallenge(firestore, firstChallenge);
    const firstBadge = await badgeDoc(OWNER, "10K");

    const secondChallenge = await startedSolo(OWNER, "10K");
    assert.notEqual(secondChallenge, firstChallenge);
    await run(OWNER, 10000);
    await settleSucceededChallenge(firestore, secondChallenge);

    const badges = await firestore.collection(`users/${OWNER}/challengeBadges`).get();
    assert.equal(badges.size, 1); // one ownership doc per tier forever
    const badge = await badgeDoc(OWNER, "10K");
    assert.equal(badge.get("firstEarnedChallengeId"), firstChallenge);
    assert.deepEqual(badge.data(), firstBadge.data()); // untouched by the repeat

    const history = await firestore.collection(`users/${OWNER}/challengeHistory`).get();
    assert.equal(history.size, 2); // both successes preserved
    const grants = await firestore.collection("challengeRewardGrants").get();
    assert.equal(grants.size, 2); // one grant ledger entry per challenge
  });
});

// ---------------------------------------------------------------------------
// Races around settlement
// ---------------------------------------------------------------------------

describe("settlement races", () => {
  it("leave-vs-completion: leaving a SETTLING instance fails with a stable code", async () => {
    const challengeId = await startedGroup("42K");
    await run(A, 7000);
    await run(OWNER, 35000); // -> SETTLING
    await rejectsReason(
      () => leaveChallengeForCallable(req(A, { challengeId }), firestore),
      "CHALLENGE_NOT_ACTIVE",
    );
    // No corruption: frozen snapshot intact.
    assert.equal((await participantDoc(challengeId, A)).get("reward"), "PENDING");
  });

  it("abandon-vs-settlement: abandoning a SETTLING instance fails with a stable code", async () => {
    const challengeId = await startedSolo(OWNER, "10K");
    await run(OWNER, 10000); // -> SETTLING
    await rejectsReason(
      () => abandonChallengeForCallable(req(OWNER, { challengeId }), firestore),
      "CHALLENGE_NOT_ACTIVE",
    );
    assert.equal((await instanceDoc(challengeId)).get("status"), "SETTLING");
  });

  it("deadline-vs-last-run: a run received after cutoff never credits, before or after the sweep", async () => {
    const challengeId = await startedSolo(OWNER, "10K");
    await run(OWNER, 4000);
    const nowMs = Date.now();
    await firestore.doc(`challengeInstances/${challengeId}`).update({
      startsAt: Timestamp.fromMillis(nowMs - 3_600_000),
      scheduledEndsAt: Timestamp.fromMillis(nowMs - 1_000),
    });

    // Order 1: last run arrives before the sweep.
    await run(OWNER, 9000, { completedAtMs: nowMs - 600_000 });
    assert.equal((await instanceDoc(challengeId)).get("teamMeters"), 4000);

    const sweep = await runChallengeSettlementSweep(firestore, nowMs);
    assert.equal(sweep.deadlineFailed, 1);
    assert.equal((await instanceDoc(challengeId)).get("status"), "FAILED");

    // Order 2: another run arrives after the sweep settled the failure.
    await run(OWNER, 9000, { completedAtMs: nowMs - 300_000 });
    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "FAILED");
    assert.equal(instance.get("teamMeters"), 4000);
  });
});

// ---------------------------------------------------------------------------
// Deadline settlement sweep
// ---------------------------------------------------------------------------

describe("challenge settlement sweep", () => {
  it("fails an ACTIVE instance past its deadline: no grants, no badges, history, slots released", async () => {
    const challengeId = await startedGroup("42K");
    await run(A, 8000);
    await run(OWNER, 9000);
    const nowMs = Date.now();
    await firestore.doc(`challengeInstances/${challengeId}`).update({
      scheduledEndsAt: Timestamp.fromMillis(nowMs - 1_000),
    });

    const sweep = await runChallengeSettlementSweep(firestore, nowMs);
    assert.equal(sweep.deadlineFailed, 1);

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "FAILED");
    assert.equal(instance.get("terminalReason"), "DEADLINE_FAILED");
    for (const uid of [OWNER, A]) {
      assert.equal((await participantDoc(challengeId, uid)).get("status"), "FAILED");
      assert.equal((await slotDoc(uid)).exists, false);
      const history = await historyDoc(uid, challengeId);
      assert.equal(history.get("outcome"), "FAILED");
      assert.equal(history.get("terminalReason"), "DEADLINE_FAILED");
    }
    assert.equal((await firestore.collection("challengeRewardGrants").get()).size, 0);
    assert.equal((await firestore.collection(`users/${OWNER}/challengeBadges`).get()).size, 0);
  });

  it("finishes SETTLING instances, expires overdue lobbies, and is idempotent on repeat", async () => {
    // (a) overdue ACTIVE instance owned by OWNER.
    const overdueId = await startedSolo(OWNER, "10K");
    const nowMs = Date.now();
    await firestore.doc(`challengeInstances/${overdueId}`).update({
      scheduledEndsAt: Timestamp.fromMillis(nowMs - 1_000),
    });
    // (b) SETTLING instance owned by A.
    const settlingId = await startedSolo(A, "10K");
    await run(A, 10000);
    // (c) expired RECRUITING lobby owned by B.
    const { challengeId: lobbyId } = await createChallengeLobbyForCallable(
      req(B, { tierId: "20K" }),
      firestore,
    );
    await firestore.doc(`challengeInstances/${lobbyId}`).update({
      lobbyExpiresAt: Timestamp.fromMillis(nowMs - 1_000),
    });

    const first = await runChallengeSettlementSweep(firestore, nowMs);
    assert.deepEqual(first, {
      deadlineFailed: 1,
      successSettled: 1,
      grantsIssued: 1,
      lobbiesExpired: 1,
    });
    assert.equal((await instanceDoc(overdueId)).get("status"), "FAILED");
    assert.equal((await instanceDoc(settlingId)).get("status"), "SUCCEEDED");
    assert.equal((await badgeDoc(A, "10K")).exists, true);
    assert.equal((await instanceDoc(lobbyId)).get("status"), "EXPIRED");
    assert.equal((await slotDoc(B)).exists, false);

    // Repeated scheduler invocation is provably idempotent.
    const second = await runChallengeSettlementSweep(firestore, nowMs + 60_000);
    assert.deepEqual(second, {
      deadlineFailed: 0,
      successSettled: 0,
      grantsIssued: 0,
      lobbiesExpired: 0,
    });
    assert.equal((await instanceDoc(overdueId)).get("status"), "FAILED");
    assert.equal((await instanceDoc(settlingId)).get("status"), "SUCCEEDED");
    assert.equal((await firestore.collection("challengeRewardGrants").get()).size, 1);
    assert.equal((await firestore.collection(`users/${A}/challengeBadges`).get()).size, 1);
  });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function req(uid: string, data: unknown): CallableRequest {
  return { auth: { uid }, data };
}

async function makeFriends(left: string, right: string): Promise<void> {
  await Promise.all([
    firestore.doc(`users/${left}/friends/${right}`).set({ friendUid: right }),
    firestore.doc(`users/${right}/friends/${left}`).set({ friendUid: left }),
  ]);
}

async function startedSolo(uid: string, tierId: string): Promise<string> {
  const { challengeId } = await createChallengeLobbyForCallable(req(uid, { tierId }), firestore);
  await startChallengeForCallable(req(uid, { challengeId }), firestore);
  return challengeId;
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

function runPayload(
  distanceMeters: number,
  options: { readonly completedAtMs?: number } = {},
): Record<string, unknown> {
  const paceSecondsPerKm = 300;
  const durationSeconds = Math.max(1, Math.round((distanceMeters / 1000) * paceSecondsPerKm));
  const completedAtMs = options.completedAtMs ?? Date.now();
  const startedAtMs = completedAtMs - durationSeconds * 1000;
  sessionCounter += 1;
  return {
    clientRunSessionId: `settlement-run-${sessionCounter}`,
    startedAt: new Date(startedAtMs).toISOString(),
    completedAt: new Date(completedAtMs).toISOString(),
    durationSeconds,
    distanceMeters,
    avgPaceSecondsPerKm: paceSecondsPerKm,
    source: "mobile",
    routePrivacy: "private",
  };
}

async function run(
  uid: string,
  distanceMeters: number,
  options: { readonly completedAtMs?: number } = {},
): Promise<void> {
  await completeRunForCallable({ auth: { uid }, data: runPayload(distanceMeters, options) }, firestore);
}

async function instanceDoc(challengeId: string) {
  return firestore.doc(`challengeInstances/${challengeId}`).get();
}
async function participantDoc(challengeId: string, uid: string) {
  return firestore.doc(`challengeInstances/${challengeId}/participants/${uid}`).get();
}
async function slotDoc(uid: string) {
  return firestore.doc(`challengeSlots/${uid}`).get();
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

async function rejectsReason(fn: () => Promise<unknown>, reason: ChallengeReason): Promise<void> {
  await assert.rejects(fn, (error: unknown) => {
    const actual = readChallengeReason(error);
    assert.equal(actual, reason, `expected reason ${reason} but got ${String(actual)}`);
    return true;
  });
}
