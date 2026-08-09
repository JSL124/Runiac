// Todo 5 emulator tests: idempotent validated-run Challenge contribution seam
// inside completeRun's trusted transaction, immediate target completion with a
// frozen eligibility snapshot, and byte-identical progression outputs.

import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore, type Firestore } from "firebase-admin/firestore";

import { completeRunForCallable } from "../src/run/completeRun.js";
import {
  createChallengeLobbyForCallable,
  getActiveChallengeForCallable,
  inviteChallengeFriendsForCallable,
  respondToChallengeInvitationForCallable,
  startChallengeForCallable,
  type CallableRequest,
} from "../src/challenge/challengeLobbyCore.js";
import { leaveChallengeForCallable } from "../src/challenge/challengeSettlementCore.js";

const PROJECT_ID = "demo-runiac-challenge";
const OWNER = "ctb-owner";
const A = "ctb-friend-a";
const STRANGER = "ctb-stranger";
const ALL_UIDS = [OWNER, A, STRANGER] as const;

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
        displayName: "Test Runner",
        nickname: "Test Runner",
        locationLabel: "Jurong East, Singapore",
      }),
    ),
  );
  await makeFriends(OWNER, A);
});

// ---------------------------------------------------------------------------
// Crediting basics
// ---------------------------------------------------------------------------

describe("challenge contribution crediting", () => {
  it("credits integer distance to participant and team while ACTIVE", async () => {
    const challengeId = await startedSolo("10K");
    await run(OWNER, 3200);

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "ACTIVE");
    assert.equal(instance.get("teamMeters"), 3200);
    assert.equal(instance.get("rawTeamMeters"), 3200);
    const participant = await participantDoc(challengeId, OWNER);
    assert.equal(participant.get("creditedMeters"), 3200);
    assert.equal(await contributionCount(challengeId), 1);
  });

  it("is a no-op with zero challenge writes for a non-participant", async () => {
    const result = await run(STRANGER, 3200);
    assert.equal(result.validationStatus, "validated");
    const instances = await firestore.collection("challengeInstances").get();
    assert.equal(instances.size, 0);
    const slots = await firestore.collection("challengeSlots").get();
    assert.equal(slots.size, 0);
  });

  it("does not credit a RECRUITING (not started) instance", async () => {
    const { challengeId } = await createChallengeLobbyForCallable(
      req(OWNER, { tierId: "10K" }),
      firestore,
    );
    await run(OWNER, 3200);
    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("teamMeters"), 0);
    assert.equal(await contributionCount(challengeId), 0);
  });
});

// ---------------------------------------------------------------------------
// Exact boundaries and clamping
// ---------------------------------------------------------------------------

describe("target completion boundaries", () => {
  it("credit reaching the target EXACTLY transitions ACTIVE -> SETTLING with clamp", async () => {
    const challengeId = await startedSolo("10K");
    await run(OWNER, 5000);
    await run(OWNER, 5000);

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "SETTLING");
    assert.equal(instance.get("teamMeters"), 10000);
    assert.equal(instance.get("rawTeamMeters"), 10000);
    assert.ok(instance.get("completedAt") instanceof Timestamp);
    const participant = await participantDoc(challengeId, OWNER);
    assert.equal(participant.get("reward"), "PENDING"); // solo owner eligible
  });

  it("overshoot clamps the exposed teamMeters at target and preserves the raw sum", async () => {
    const challengeId = await startedSolo("10K");
    await run(OWNER, 9000);
    await run(OWNER, 3000);

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "SETTLING");
    assert.equal(instance.get("teamMeters"), 10000);
    assert.equal(instance.get("rawTeamMeters"), 12000);
  });

  it("group eligibility snapshot: creditedMeters == personalMinimum passes", async () => {
    const challengeId = await startedGroup("42K"); // min 7000, target 42000
    await run(A, 7000);
    await run(OWNER, 35000); // total 42000 -> SETTLING

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "SETTLING");
    assert.equal((await participantDoc(challengeId, OWNER)).get("reward"), "PENDING");
    assert.equal((await participantDoc(challengeId, A)).get("reward"), "PENDING");
  });

  it("group eligibility snapshot: one metre under the personal minimum fails", async () => {
    const challengeId = await startedGroup("42K");
    await run(A, 6999);
    await run(OWNER, 35001); // total 42000 -> SETTLING

    assert.equal((await instanceDoc(challengeId)).get("status"), "SETTLING");
    assert.equal((await participantDoc(challengeId, OWNER)).get("reward"), "PENDING");
    assert.equal((await participantDoc(challengeId, A)).get("reward"), "NOT_ELIGIBLE");
  });

  it("exposes SETTLING through getActiveChallenge while results are pending", async () => {
    const challengeId = await startedSolo("10K");
    await run(OWNER, 10000);
    const view = await getActiveChallengeForCallable(req(OWNER, {}), firestore);
    assert.equal(view.challenge?.instance.challengeId, challengeId);
    assert.equal(view.challenge?.instance.status, "SETTLING");
    assert.equal(view.challenge?.instance.teamMeters, 10000);
  });
});

// ---------------------------------------------------------------------------
// Idempotency
// ---------------------------------------------------------------------------

describe("contribution idempotency", () => {
  it("a replayed run never double-credits", async () => {
    const challengeId = await startedSolo("10K");
    const payload = runPayload(4000);
    const first = await completeRunForCallable({ auth: { uid: OWNER }, data: payload }, firestore);
    const second = await completeRunForCallable({ auth: { uid: OWNER }, data: payload }, firestore);

    assert.deepEqual(second, first);
    assert.equal((await instanceDoc(challengeId)).get("teamMeters"), 4000);
    assert.equal((await participantDoc(challengeId, OWNER)).get("creditedMeters"), 4000);
    assert.equal(await contributionCount(challengeId), 1);
  });

  it("a same-session different-payload upload is rejected and never credits", async () => {
    const challengeId = await startedSolo("10K");
    const payload = runPayload(4000);
    await completeRunForCallable({ auth: { uid: OWNER }, data: payload }, firestore);

    await assert.rejects(
      () =>
        completeRunForCallable(
          {
            auth: { uid: OWNER },
            data: {
              ...payload,
              distanceMeters: 5000,
              // Implied pace at durationSeconds 1200 / distanceMeters 5000 is
              // 1200 * 1000 / 5000 = 240; keep the fixture internally
              // consistent so the payload reaches replay detection instead of
              // being turned away by the pace-consistency check first.
              avgPaceSecondsPerKm: 240,
            },
          },
          firestore,
        ),
      (error: { code?: string }) => error.code === "already-exists",
    );
    assert.equal((await instanceDoc(challengeId)).get("teamMeters"), 4000);
    assert.equal(await contributionCount(challengeId), 1);
  });
});

// ---------------------------------------------------------------------------
// Credit-window enforcement (no offline/late grace)
// ---------------------------------------------------------------------------

describe("credit windows", () => {
  it("never credits a request received after the cutoff, even with compliant completedAt", async () => {
    const challengeId = await startedSolo("10K");
    const nowMs = Date.now();
    await firestore.doc(`challengeInstances/${challengeId}`).update({
      startsAt: Timestamp.fromMillis(nowMs - 3_600_000),
      scheduledEndsAt: Timestamp.fromMillis(nowMs - 1_000),
    });
    // completedAt is INSIDE [startsAt, scheduledEndsAt] but receipt is late.
    await run(OWNER, 3000, { completedAtMs: nowMs - 1_800_000 });

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("teamMeters"), 0);
    assert.equal(instance.get("status"), "ACTIVE");
    assert.equal(await contributionCount(challengeId), 0);
  });

  it("never credits a completedAt before the challenge started", async () => {
    const challengeId = await startedSolo("10K");
    const startsAtMs = timestampMs(await instanceDoc(challengeId), "startsAt");
    await run(OWNER, 3000, { completedAtMs: startsAtMs - 60_000 });
    assert.equal((await instanceDoc(challengeId)).get("teamMeters"), 0);
  });

  it("never credits a completedAt in the future", async () => {
    const challengeId = await startedSolo("10K");
    await run(OWNER, 3000, { completedAtMs: Date.now() + 120_000 });
    assert.equal((await instanceDoc(challengeId)).get("teamMeters"), 0);
  });

  it("never credits after a participant left; LEFT metres stay in the team total", async () => {
    const challengeId = await startedGroup("42K");
    await run(A, 5000);
    await leaveChallengeForCallable(req(A, { challengeId }), firestore);
    await run(A, 5000); // post-leave upload

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("teamMeters"), 5000); // retained, not increased
    const participant = await participantDoc(challengeId, A);
    assert.equal(participant.get("status"), "LEFT");
    assert.equal(participant.get("creditedMeters"), 5000);
    assert.equal(await contributionCount(challengeId), 1);
  });

  it("never credits once the instance is SETTLING", async () => {
    const challengeId = await startedSolo("10K");
    await run(OWNER, 10000); // -> SETTLING
    await run(OWNER, 3000);

    const instance = await instanceDoc(challengeId);
    assert.equal(instance.get("status"), "SETTLING");
    assert.equal(instance.get("teamMeters"), 10000);
    assert.equal(instance.get("rawTeamMeters"), 10000);
    assert.equal(await contributionCount(challengeId), 1);
  });
});

// ---------------------------------------------------------------------------
// Concurrency: simultaneous target-crossing runs serialize
// ---------------------------------------------------------------------------

describe("concurrent target crossing", () => {
  it("exactly one transaction performs ACTIVE -> SETTLING; team total clamps; snapshot freezes", async () => {
    const challengeId = await startedSolo("10K");
    await run(OWNER, 4000);

    const beforeInstance = await instanceDoc(challengeId);
    console.log(
      `EVIDENCE concurrent-overshoot-before ${JSON.stringify({
        status: beforeInstance.get("status"),
        teamMeters: beforeInstance.get("teamMeters"),
        rawTeamMeters: beforeInstance.get("rawTeamMeters"),
        contributions: await contributionCount(challengeId),
      })}`,
    );

    // Two runs whose sum overshoots; EACH alone crosses the remaining target.
    const [first, second] = await Promise.all([
      completeRunForCallable({ auth: { uid: OWNER }, data: runPayload(6000) }, firestore),
      completeRunForCallable({ auth: { uid: OWNER }, data: runPayload(7000) }, firestore),
    ]);
    assert.equal(first.validationStatus, "validated");
    assert.equal(second.validationStatus, "validated");

    const instance = await instanceDoc(challengeId);
    const participant = await participantDoc(challengeId, OWNER);
    const contributions = await contributionCount(challengeId);
    console.log(
      `EVIDENCE concurrent-overshoot-after ${JSON.stringify({
        status: instance.get("status"),
        teamMeters: instance.get("teamMeters"),
        rawTeamMeters: instance.get("rawTeamMeters"),
        creditedMeters: participant.get("creditedMeters"),
        reward: participant.get("reward"),
        contributions,
      })}`,
    );

    // Exactly one of the two concurrent runs credited (initial run + 1 winner).
    assert.equal(contributions, 2);
    assert.equal(instance.get("status"), "SETTLING");
    assert.equal(instance.get("teamMeters"), 10000); // clamped at target
    const raw = instance.get("rawTeamMeters") as number;
    assert.ok(raw === 10000 || raw === 11000, `raw ${raw} must match exactly one credit`);
    assert.equal(participant.get("creditedMeters"), raw);
    assert.equal(participant.get("reward"), "PENDING"); // frozen eligibility snapshot
  });
});

// ---------------------------------------------------------------------------
// Progression isolation: challenge participation never changes run outputs
// ---------------------------------------------------------------------------

describe("progression isolation", () => {
  it("XP/streak outputs are byte-equal for a participant vs a non-participant run", async () => {
    await startedSolo("10K");
    const payload = runPayload(3200);

    const participantResult = await completeRunForCallable(
      { auth: { uid: OWNER }, data: payload },
      firestore,
    );
    const nonParticipantResult = await completeRunForCallable(
      { auth: { uid: STRANGER }, data: payload },
      firestore,
    );

    assert.deepEqual(participantResult.progressionDisplay, nonParticipantResult.progressionDisplay);

    const participantEvent = await firestore
      .doc(`progressionEvents/${participantResult.progressionEventId}`)
      .get();
    const nonParticipantEvent = await firestore
      .doc(`progressionEvents/${nonParticipantResult.progressionEventId}`)
      .get();
    const strip = (data: Record<string, unknown> | undefined) => {
      const copy = { ...(data ?? {}) };
      delete copy["ownerUid"];
      delete copy["activityId"];
      delete copy["summaryId"];
      delete copy["progressionEventId"];
      return copy;
    };
    assert.deepEqual(strip(participantEvent.data()), strip(nonParticipantEvent.data()));

    const participantActivity = await firestore
      .doc(`activities/${participantResult.activityId}`)
      .get();
    const nonParticipantActivity = await firestore
      .doc(`activities/${nonParticipantResult.activityId}`)
      .get();
    assert.equal(
      participantActivity.get("validatedActivityContributionState"),
      nonParticipantActivity.get("validatedActivityContributionState"),
    );
    assert.equal(
      participantActivity.get("countsTowardProgression"),
      nonParticipantActivity.get("countsTowardProgression"),
    );
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

async function startedSolo(tierId: string): Promise<string> {
  const { challengeId } = await createChallengeLobbyForCallable(req(OWNER, { tierId }), firestore);
  await startChallengeForCallable(req(OWNER, { challengeId }), firestore);
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

// Validated-run payload with consistent duration/pace/timestamps. completedAt
// defaults to "now" (just after the challenge started, never in the future).
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
    clientRunSessionId: `challenge-run-${sessionCounter}`,
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
): Promise<{ readonly validationStatus: string }> {
  return completeRunForCallable(
    { auth: { uid }, data: runPayload(distanceMeters, options) },
    firestore,
  );
}

async function instanceDoc(challengeId: string) {
  return firestore.doc(`challengeInstances/${challengeId}`).get();
}
async function participantDoc(challengeId: string, uid: string) {
  return firestore.doc(`challengeInstances/${challengeId}/participants/${uid}`).get();
}
async function contributionCount(challengeId: string): Promise<number> {
  const snapshot = await firestore
    .collection(`challengeInstances/${challengeId}/contributions`)
    .get();
  return snapshot.size;
}

function timestampMs(doc: FirebaseFirestore.DocumentSnapshot, field: string): number {
  const value = doc.get(field) as Timestamp;
  return value.toMillis();
}

async function deleteCollection(name: string): Promise<void> {
  const snapshot = await firestore.collection(name).get();
  await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
}
