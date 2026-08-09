// Challenge leave / abandon / settlement transaction cores (Todo 6).
//
// Owns four server-authored operations on started (post-lobby) instances:
//   - leaveChallenge: non-owner self-exit from an ACTIVE instance.
//   - abandonChallenge: owner cancels an ACTIVE instance for everyone.
//   - settleSucceededChallenge: SETTLING -> SUCCEEDED with idempotent reward
//     grants and one-badge-per-tier ownership.
//   - settleFailedChallenge: ACTIVE past scheduledEndsAt -> FAILED (no grants).
// plus the scheduled sweep (`runChallengeSettlementSweep`) that drives deadline
// failure, grant retry, and lazy lobby expiry.
//
// Every state transition goes through the pure state machine; every failure
// path throws a stable CHALLENGE_REASON code. Success settlement is split into
// three idempotent phases so that slots release and participant results freeze
// even if a grant write later fails:
//   Phase A (freeze): participant terminal states, history docs, slot release.
//     Instance STAYS SETTLING (clients keep seeing "calculating"), users are
//     already free to start a new challenge.
//   Phase B (grants): per-user transactions; `transaction.create` on
//     challengeRewardGrants/{challengeId_uid} is the idempotency record, badge
//     ownership users/{uid}/challengeBadges/{tierId} is exists-checked so
//     repeat tier successes never duplicate ownership.
//   Phase C (finalize): SETTLING -> SUCCEEDED. Never regresses a terminal
//     instance; rerunning the whole settlement is a no-op for already-granted
//     users. A grant failure leaves the instance SETTLING, so the next sweep
//     retries phases B/C idempotently.

import { Timestamp, type Firestore, type Transaction } from "firebase-admin/firestore";
import type {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  QuerySnapshot,
} from "firebase-admin/firestore";
import { challengeError } from "./challengeErrors.js";
import { assertCallerAccountNotSuspendedInTransaction } from "../security/accountStatus.js";
import { shouldExpireLobby } from "./challengeExpiry.js";
import {
  emitChallengeBadgeIssuedNotifications,
  emitChallengeOwnerCancelledNotifications,
  emitChallengeParticipantLeftNotifications,
  emitChallengeResultReadyNotifications,
} from "./challengeNotifications.js";
import { expireChallengeLobbyById, type CallableRequest } from "./challengeLobbyCore.js";
import {
  transitionInstance,
  transitionParticipant,
  transitionReward,
} from "./challengeStateMachine.js";
import type {
  ChallengeTerminalReason,
  InstanceState,
  ParticipantState,
  RewardState,
} from "./challengeTypes.js";

import {
  badgeRef,
  buildHistoryDoc,
  grantRef,
  historyRef,
  instanceRef,
  loadInstanceWithRoster,
  participantRef,
  readNumber,
  readString,
  releaseSlotIfHeldHere,
  requireAuthUid,
  requireChallengeId,
  slotRef,
  timestampToMillis,
  type LoadedInstance,
} from "./challengeSettlementSupport.js";

// Upper bound per sweep query; repeated one-minute invocations drain backlogs.
const SWEEP_QUERY_LIMIT = 50;

// ---------------------------------------------------------------------------
// Pure settlement planner
// ---------------------------------------------------------------------------

export type ParticipantSettlementAction =
  | "SETTLE_SUCCEEDED"
  | "SETTLE_INELIGIBLE"
  | "PRESERVE_LEFT"
  | "SKIP";

// Pure decision for one participant when a SETTLING instance settles as
// SUCCEEDED. Eligibility was frozen at target-reach time as reward=PENDING.
export function planSuccessSettlementAction(
  status: ParticipantState,
  reward: RewardState,
): ParticipantSettlementAction {
  if (status === "LEFT") return "PRESERVE_LEFT";
  if (status !== "ACTIVE") return "SKIP"; // already settled or cancelled
  return reward === "PENDING" ? "SETTLE_SUCCEEDED" : "SETTLE_INELIGIBLE";
}

// ---------------------------------------------------------------------------
// leaveChallenge (non-owner, ACTIVE instance)
// ---------------------------------------------------------------------------

export type LeaveChallengeResult = {
  readonly challengeId: string;
  readonly outcome: "left";
  readonly idempotent: boolean;
};

export async function leaveChallengeForCallable(
  request: CallableRequest,
  firestore: Firestore,
): Promise<LeaveChallengeResult> {
  const uid = requireAuthUid(request);
  const challengeId = requireChallengeId(request.data);

  const idempotent = await firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, firestore, uid);
    const nowMs = Date.now();
    const ref = instanceRef(firestore, challengeId);
    const instanceSnap = await transaction.get(ref);
    if (!instanceSnap.exists) throw challengeError("CHALLENGE_NOT_FOUND");
    const instance = instanceSnap.data() as DocumentData;

    const participantSnap = await transaction.get(participantRef(firestore, challengeId, uid));
    const slotSnap = await transaction.get(slotRef(firestore, uid));
    if (!participantSnap.exists) throw challengeError("NOT_A_PARTICIPANT");
    const participant = participantSnap.data() as DocumentData;
    const role = readString(participant, "role") === "owner" ? "owner" : "member";
    if (role === "owner") throw challengeError("OWNER_CANNOT_LEAVE");
    const participantStatus = readString(participant, "status") as ParticipantState;
    if (participantStatus === "LEFT") return true; // idempotent replay

    const status = readString(instance, "status") as InstanceState;
    if (status !== "ACTIVE") throw challengeError("CHALLENGE_NOT_ACTIVE");

    const transition = transitionParticipant(
      { state: participantStatus, role },
      { type: "LEAVE" },
      { kind: "self" },
    );
    if (!transition.ok) {
      if (transition.error === "OWNER_CANNOT_LEAVE") throw challengeError("OWNER_CANNOT_LEAVE");
      throw challengeError("ILLEGAL_STATE");
    }

    // Metres stay in teamMeters; roster stays locked (mode snapshot immutable
    // after start); permanent reward ineligibility; only THIS user's slot frees.
    transaction.update(participantSnap.ref, { status: "LEFT", result: "LEFT" });
    if (slotSnap.exists && readString(slotSnap.data(), "challengeId") === challengeId) {
      transaction.delete(slotSnap.ref);
    }
    transaction.set(
      historyRef(firestore, uid, challengeId),
      buildHistoryDoc({
        challengeId,
        instanceData: instance,
        participantData: participant,
        outcome: "LEFT",
        endedAtMs: nowMs,
      }),
    );
    return false;
  });

  // Post-commit notification hook. Fires only on a real departure (idempotent
  // replays skip it); never throws, so a delivery failure cannot roll back the
  // committed LEFT state / history.
  if (!idempotent) {
    await emitChallengeParticipantLeftNotifications(firestore, challengeId);
  }

  return { challengeId, outcome: "left", idempotent };
}

// ---------------------------------------------------------------------------
// abandonChallenge (owner only, ACTIVE instance)
// ---------------------------------------------------------------------------

export type AbandonChallengeResult = {
  readonly challengeId: string;
  readonly outcome: "abandoned";
  readonly idempotent: boolean;
};

export async function abandonChallengeForCallable(
  request: CallableRequest,
  firestore: Firestore,
): Promise<AbandonChallengeResult> {
  const uid = requireAuthUid(request);
  const challengeId = requireChallengeId(request.data);

  const idempotent = await firestore.runTransaction(async (transaction) => {
    // Defence-in-depth (see accountStatus.ts): this callable never otherwise
    // reads the caller's own users/{uid} doc, so add the one read needed to
    // reject a suspended caller before any write in this transaction.
    await assertCallerAccountNotSuspendedInTransaction(transaction, firestore, uid);
    const nowMs = Date.now();
    const loaded = await loadInstanceWithRoster(transaction, firestore, challengeId);
    if (loaded === undefined) throw challengeError("CHALLENGE_NOT_FOUND");
    if (loaded.ownerUid !== uid) throw challengeError("NOT_CHALLENGE_OWNER");
    if (loaded.status === "CANCELLED") return true; // idempotent replay
    if (loaded.status !== "ACTIVE") throw challengeError("CHALLENGE_NOT_ACTIVE");

    // No reward grant may exist for a still-ACTIVE instance — assert.
    const invitations = await transaction.get(
      firestore.collection("challengeInvitations").where("challengeId", "==", challengeId),
    );
    const grantSnaps = await Promise.all(
      loaded.roster.map((rosterUid) =>
        transaction.get(grantRef(firestore, challengeId, rosterUid)),
      ),
    );
    if (grantSnaps.some((snap) => snap.exists)) throw challengeError("ILLEGAL_STATE");

    const transition = transitionInstance(loaded.status, { type: "ABANDON" }, { kind: "owner" });
    if (!transition.ok) throw challengeError("CHALLENGE_NOT_ACTIVE");

    transaction.update(loaded.ref, {
      status: "CANCELLED",
      terminalReason: "OWNER_ABANDONED",
      settledAt: Timestamp.fromMillis(nowMs),
    });
    for (const doc of loaded.participants.docs) {
      const data = doc.data();
      const participantStatus = readString(data, "status") as ParticipantState;
      const role = readString(data, "role") === "owner" ? "owner" : "member";
      if (participantStatus === "LEFT") {
        // Leaver keeps their LEFT snapshot; only the terminal reason merges in.
        transaction.set(
          historyRef(firestore, doc.id, challengeId),
          { terminalReason: "OWNER_ABANDONED" },
          { merge: true },
        );
        continue;
      }
      const cancel = transitionParticipant(
        { state: participantStatus, role },
        { type: "CANCEL" },
        { kind: "system" },
      );
      if (!cancel.ok) continue; // already terminal
      transaction.update(doc.ref, { status: "CANCELLED", result: "CANCELLED" });
      transaction.set(
        historyRef(firestore, doc.id, challengeId),
        buildHistoryDoc({
          challengeId,
          instanceData: loaded.data,
          participantData: data,
          outcome: "CANCELLED",
          terminalReason: "OWNER_ABANDONED",
          endedAtMs: nowMs,
        }),
      );
    }
    for (const rosterUid of loaded.roster) {
      releaseSlotIfHeldHere(transaction, loaded, challengeId, rosterUid);
    }
    for (const doc of invitations.docs) {
      if (readString(doc.data(), "status") === "PENDING") {
        transaction.update(doc.ref, { status: "REVOKED", respondedAt: Timestamp.fromMillis(nowMs) });
      }
    }
    return false;
  });

  // Post-commit notification hook. Fires only on the first abandon; never throws.
  if (!idempotent) {
    await emitChallengeOwnerCancelledNotifications(firestore, challengeId);
  }

  return { challengeId, outcome: "abandoned", idempotent };
}

// ---------------------------------------------------------------------------
// Success settlement — Phase A: freeze results + release slots
// ---------------------------------------------------------------------------

export type SuccessFreezeResult =
  | { readonly kind: "not_found" }
  | { readonly kind: "not_settling"; readonly status: InstanceState }
  | {
      readonly kind: "frozen" | "already_terminal";
      readonly tierId: string;
      readonly catalogVersion: string;
      readonly grantPendingUids: readonly string[];
    };

// Exported separately so tests can simulate a crash between freezing results
// and issuing grants (the "injected grant failure" scenario).
export async function freezeChallengeSuccess(
  firestore: Firestore,
  challengeId: string,
  nowMs: number,
): Promise<SuccessFreezeResult> {
  return firestore.runTransaction(async (transaction) => {
    const loaded = await loadInstanceWithRoster(transaction, firestore, challengeId);
    if (loaded === undefined) return { kind: "not_found" };
    const tierId = readString(loaded.data, "tierId");
    const catalogVersion = readString(loaded.data, "catalogVersion");

    // Grant-pending set: eligibility frozen at target-reach as reward=PENDING;
    // grant issuance flips it to ISSUED, so PENDING == not yet granted.
    const grantPendingUids = loaded.participants.docs
      .filter((doc) => readString(doc.data(), "reward") === "PENDING")
      .map((doc) => doc.id);

    if (loaded.status === "SUCCEEDED") {
      // Rerun on a terminal instance: nothing to freeze, grants may self-heal.
      return { kind: "already_terminal", tierId, catalogVersion, grantPendingUids };
    }
    if (loaded.status !== "SETTLING") return { kind: "not_settling", status: loaded.status };

    const endedAtMs = timestampToMillis(loaded.data["completedAt"]) || nowMs;
    for (const doc of loaded.participants.docs) {
      const data = doc.data();
      const participantStatus = readString(data, "status") as ParticipantState;
      const reward = readString(data, "reward") as RewardState;
      const role = readString(data, "role") === "owner" ? "owner" : "member";
      const action = planSuccessSettlementAction(participantStatus, reward);
      if (action === "PRESERVE_LEFT") {
        transaction.set(
          historyRef(firestore, doc.id, challengeId),
          { terminalReason: "TARGET_REACHED" },
          { merge: true },
        );
        continue;
      }
      if (action === "SKIP") continue; // already settled on a previous attempt
      const edge = action === "SETTLE_SUCCEEDED" ? "SETTLE_SUCCEEDED" : "SETTLE_INELIGIBLE";
      const outcome: ParticipantState = action === "SETTLE_SUCCEEDED" ? "SUCCEEDED" : "INELIGIBLE";
      const transition = transitionParticipant(
        { state: participantStatus, role },
        { type: edge },
        { kind: "system" },
      );
      if (!transition.ok) continue;
      transaction.update(doc.ref, { status: outcome, result: outcome });
      transaction.set(
        historyRef(firestore, doc.id, challengeId),
        buildHistoryDoc({
          challengeId,
          instanceData: loaded.data,
          participantData: data,
          outcome,
          terminalReason: "TARGET_REACHED",
          endedAtMs,
        }),
      );
    }
    // CRITICAL ORDERING: slots release here, before (and independent of) grant
    // issuance, so a failed grant never blocks starting a new challenge.
    for (const rosterUid of loaded.roster) {
      releaseSlotIfHeldHere(transaction, loaded, challengeId, rosterUid);
    }
    return { kind: "frozen", tierId, catalogVersion, grantPendingUids };
  });
}

// ---------------------------------------------------------------------------
// Success settlement — Phase B: idempotent grant + badge issuance
// ---------------------------------------------------------------------------

export type GrantIssueResult = {
  readonly granted: readonly string[];
  readonly alreadyGranted: readonly string[];
};

export async function issueChallengeRewardGrants(
  firestore: Firestore,
  challengeId: string,
  tierId: string,
  catalogVersion: string,
  uids: readonly string[],
  nowMs: number,
): Promise<GrantIssueResult> {
  const granted: string[] = [];
  const alreadyGranted: string[] = [];
  for (const uid of uids) {
    const wasGranted = await firestore.runTransaction(async (transaction) => {
      const grantDocRef = grantRef(firestore, challengeId, uid);
      const badgeDocRef = badgeRef(firestore, uid, tierId);
      const participantDocRef = participantRef(firestore, challengeId, uid);
      const [grantSnap, badgeSnap, participantSnap] = await Promise.all([
        transaction.get(grantDocRef),
        transaction.get(badgeDocRef),
        transaction.get(participantDocRef),
      ]);

      let issuedNow = false;
      if (!grantSnap.exists) {
        // The idempotency record: `create` collides if a concurrent retry won.
        transaction.create(grantDocRef, {
          challengeId,
          uid,
          tierId,
          status: "ISSUED",
          grantedAt: Timestamp.fromMillis(nowMs),
        });
        issuedNow = true;
      }
      if (!badgeSnap.exists) {
        // One ownership doc per tier forever; repeat successes never duplicate.
        transaction.create(badgeDocRef, {
          tierId,
          catalogVersion,
          firstEarnedChallengeId: challengeId,
          earnedAt: Timestamp.fromMillis(nowMs),
        });
      }
      const reward = readString(participantSnap.data(), "reward") as RewardState;
      if (reward === "PENDING") {
        const transition = transitionReward(reward, { type: "ISSUE" }, { kind: "system" });
        if (transition.ok) transaction.update(participantDocRef, { reward: "ISSUED" });
      }
      return issuedNow;
    });
    if (wasGranted) granted.push(uid);
    else alreadyGranted.push(uid);
  }
  return { granted, alreadyGranted };
}

// ---------------------------------------------------------------------------
// Success settlement — Phase C: finalize instance (never regress terminal)
// ---------------------------------------------------------------------------

export async function finalizeChallengeSuccess(
  firestore: Firestore,
  challengeId: string,
  nowMs: number,
): Promise<{ readonly finalized: boolean }> {
  return firestore.runTransaction(async (transaction) => {
    const ref = instanceRef(firestore, challengeId);
    const snap = await transaction.get(ref);
    if (!snap.exists) return { finalized: false };
    const status = readString(snap.data(), "status") as InstanceState;
    const transition = transitionInstance(status, { type: "SETTLE_SUCCEEDED" }, { kind: "system" });
    if (!transition.ok) return { finalized: false };
    transaction.update(ref, {
      status: "SUCCEEDED",
      terminalReason: "TARGET_REACHED",
      settledAt: Timestamp.fromMillis(nowMs),
    });
    return { finalized: true };
  });
}

// ---------------------------------------------------------------------------
// Success settlement — full idempotent flow
// ---------------------------------------------------------------------------

export type SettleSucceededResult = {
  readonly settled: boolean;
  readonly finalized: boolean;
  readonly granted: readonly string[];
  readonly alreadyGranted: readonly string[];
};

export async function settleSucceededChallenge(
  firestore: Firestore,
  challengeId: string,
  nowMs: number = Date.now(),
): Promise<SettleSucceededResult> {
  const freeze = await freezeChallengeSuccess(firestore, challengeId, nowMs);
  if (freeze.kind === "not_found" || freeze.kind === "not_settling") {
    return { settled: false, finalized: false, granted: [], alreadyGranted: [] };
  }
  const grants = await issueChallengeRewardGrants(
    firestore,
    challengeId,
    freeze.tierId,
    freeze.catalogVersion,
    freeze.grantPendingUids,
    nowMs,
  );
  const finalize =
    freeze.kind === "frozen"
      ? await finalizeChallengeSuccess(firestore, challengeId, nowMs)
      : { finalized: false };

  // Post-commit notification hook. Emits result-ready + badge-issued exactly
  // once, gated on the first SETTLING -> SUCCEEDED finalize; the deterministic
  // delivery key dedupes any sweep replay. Never throws, so a delivery failure
  // cannot regress the terminal SUCCEEDED state or the issued grants.
  if (finalize.finalized) {
    await emitChallengeResultReadyNotifications(firestore, challengeId, nowMs);
    await emitChallengeBadgeIssuedNotifications(firestore, challengeId, nowMs);
  }

  return {
    settled: true,
    finalized: finalize.finalized,
    granted: grants.granted,
    alreadyGranted: grants.alreadyGranted,
  };
}

// ---------------------------------------------------------------------------
// Deadline failure settlement (single transaction, no grants, no badges)
// ---------------------------------------------------------------------------

export type SettleFailedResult = { readonly settled: boolean };

export async function settleFailedChallenge(
  firestore: Firestore,
  challengeId: string,
  nowMs: number = Date.now(),
): Promise<SettleFailedResult> {
  const result = await firestore.runTransaction(async (transaction) => {
    const loaded = await loadInstanceWithRoster(transaction, firestore, challengeId);
    if (loaded === undefined) return { settled: false };
    // Only an ACTIVE instance past its deadline fails; SETTLING means the
    // target was reached first, terminal states never regress.
    if (loaded.status !== "ACTIVE") return { settled: false };
    const scheduledEndsAtMs = timestampToMillis(loaded.data["scheduledEndsAt"]);
    if (scheduledEndsAtMs === 0 || nowMs < scheduledEndsAtMs) return { settled: false };

    const begin = transitionInstance(loaded.status, { type: "BEGIN_SETTLEMENT" }, { kind: "system" });
    if (!begin.ok) return { settled: false };
    const fail = transitionInstance(begin.state, { type: "SETTLE_FAILED" }, { kind: "system" });
    if (!fail.ok) return { settled: false };

    transaction.update(loaded.ref, {
      status: "FAILED",
      terminalReason: "DEADLINE_FAILED",
      settledAt: Timestamp.fromMillis(nowMs),
    });
    for (const doc of loaded.participants.docs) {
      const data = doc.data();
      const participantStatus = readString(data, "status") as ParticipantState;
      const role = readString(data, "role") === "owner" ? "owner" : "member";
      if (participantStatus === "LEFT") {
        transaction.set(
          historyRef(firestore, doc.id, challengeId),
          { terminalReason: "DEADLINE_FAILED" },
          { merge: true },
        );
        continue;
      }
      const transition = transitionParticipant(
        { state: participantStatus, role },
        { type: "SETTLE_FAILED" },
        { kind: "system" },
      );
      if (!transition.ok) continue;
      transaction.update(doc.ref, { status: "FAILED", result: "FAILED" });
      transaction.set(
        historyRef(firestore, doc.id, challengeId),
        buildHistoryDoc({
          challengeId,
          instanceData: loaded.data,
          participantData: data,
          outcome: "FAILED",
          terminalReason: "DEADLINE_FAILED",
          endedAtMs: scheduledEndsAtMs,
        }),
      );
    }
    for (const rosterUid of loaded.roster) {
      releaseSlotIfHeldHere(transaction, loaded, challengeId, rosterUid);
    }
    return { settled: true };
  });

  // Post-commit notification hook. Emits result-ready once on the first
  // deadline failure; the deterministic delivery key dedupes any sweep replay.
  // Never throws, so a delivery failure cannot regress the terminal FAILED state.
  if (result.settled) {
    await emitChallengeResultReadyNotifications(firestore, challengeId, nowMs);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Scheduled settlement sweep (one-minute cadence; provably idempotent)
// ---------------------------------------------------------------------------

export type ChallengeSettlementSweepResult = {
  readonly deadlineFailed: number;
  readonly successSettled: number;
  readonly grantsIssued: number;
  readonly lobbiesExpired: number;
};

export async function runChallengeSettlementSweep(
  firestore: Firestore,
  nowMs: number = Date.now(),
): Promise<ChallengeSettlementSweepResult> {
  const now = Timestamp.fromMillis(nowMs);
  const instances = firestore.collection("challengeInstances");

  // (a) ACTIVE instances past scheduledEndsAt -> FAILED. Uses the existing
  // composite index (status ASC, scheduledEndsAt ASC).
  const overdue = await instances
    .where("status", "==", "ACTIVE")
    .where("scheduledEndsAt", "<=", now)
    .limit(SWEEP_QUERY_LIMIT)
    .get();
  let deadlineFailed = 0;
  for (const doc of overdue.docs) {
    const result = await settleFailedChallenge(firestore, doc.id, nowMs);
    if (result.settled) deadlineFailed += 1;
  }

  // (b) SETTLING instances -> finish success settlement / retry grant issuance
  // idempotently. Equality-only query (automatic single-field index).
  const settling = await instances
    .where("status", "==", "SETTLING")
    .limit(SWEEP_QUERY_LIMIT)
    .get();
  let successSettled = 0;
  let grantsIssued = 0;
  for (const doc of settling.docs) {
    const result = await settleSucceededChallenge(firestore, doc.id, nowMs);
    if (result.finalized) successSettled += 1;
    grantsIssued += result.granted.length;
  }

  // (c) RECRUITING lobbies past lobbyExpiresAt -> lazy expiry. Equality-only
  // query; the expiry instant is filtered in code via the pure seam because no
  // status+lobbyExpiresAt composite index exists (bounded by SWEEP_QUERY_LIMIT).
  const recruiting = await instances
    .where("status", "==", "RECRUITING")
    .limit(SWEEP_QUERY_LIMIT)
    .get();
  let lobbiesExpired = 0;
  for (const doc of recruiting.docs) {
    const lobbyExpiresAtMs = timestampToMillis(doc.get("lobbyExpiresAt"));
    if (!shouldExpireLobby({ status: "RECRUITING", lobbyExpiresAtMs, nowMs })) continue;
    const result = await expireChallengeLobbyById(firestore, doc.id, nowMs);
    if (result.expired) lobbiesExpired += 1;
  }

  return { deadlineFailed, successSettled, grantsIssued, lobbiesExpired };
}
