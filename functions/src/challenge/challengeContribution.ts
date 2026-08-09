// Idempotent validated-run Challenge contribution seam (Todo 5).
//
// `applyChallengeContribution` is invoked from INSIDE completeRun's trusted
// transaction, immediately after payload validation and replay matching and
// strictly BEFORE completeRun's first write (Firestore transactions require
// every read to precede any write; this seam reads, then writes, then
// completeRun performs its own writes — no read ever follows a write).
//
// Behavioral contract (capsule "Core Behavioral Contract"):
// - Non-participants pay at most ONE extra read (`challengeSlots/{uid}`);
//   replayed activities pay zero (early return before any read).
// - Integer `distanceMeters` is credited once per deterministic activity ID,
//   only while participant ACTIVE, instance ACTIVE, and server receipt strictly
//   before `scheduledEndsAt`. Client `completedAt` must lie within
//   [startsAt, scheduledEndsAt] and never in the future; a compliant
//   `completedAt` NEVER admits a request received after the cutoff.
// - Idempotency marker: `challengeInstances/{id}/contributions/{activityId}`
//   (bounded: one doc per credited run; race-safe: created with
//   `transaction.create` inside the same atomic transaction that persists the
//   activity, so a concurrent duplicate aborts).
// - The credit that reaches `rules.targetMeters` clamps the exposed
//   `teamMeters` at the target (raw sum preserved in `rawTeamMeters`), records
//   the server `completedAt`, transitions ACTIVE -> SETTLING through the pure
//   state machine (system actor), and snapshots per-participant reward
//   eligibility at that instant. SETTLING/terminal instances never accept
//   further credit, so simultaneous target-crossing transactions serialize on
//   the instance doc and exactly one performs the transition.
// - This seam never throws for challenge-state reasons: a valid run upload
//   always succeeds regardless of challenge state. It never touches XP,
//   streak, level, rank, or leaderboard outputs.

import { Timestamp, type Firestore, type Transaction } from "firebase-admin/firestore";
import type { DocumentData, DocumentReference } from "firebase-admin/firestore";
import { transitionInstance, transitionParticipant } from "./challengeStateMachine.js";
import type {
  ChallengeMode,
  ChallengeRulesSnapshot,
  InstanceState,
  ParticipantRole,
  ParticipantState,
} from "./challengeTypes.js";

// ---------------------------------------------------------------------------
// Public seam contract
// ---------------------------------------------------------------------------

export type ChallengeContributionInput = {
  readonly transaction: Transaction;
  readonly firestore: Firestore;
  readonly uid: string;
  // The deterministic activity ID completeRun computes for replay matching.
  readonly activityId: string;
  // True when the deterministic activity doc already exists (replayed upload).
  readonly activityAlreadyExists: boolean;
  readonly distanceMeters: number;
  // Client-declared completion instant (already validated ISO, parsed to ms).
  readonly completedAtMs: number;
  // Server receipt instant (Date.now() inside the callable).
  readonly nowMs: number;
};

export type ChallengeContributionOutcome =
  | { readonly credited: false; readonly reason: ChallengeContributionSkipReason }
  | {
      readonly credited: true;
      readonly challengeId: string;
      readonly creditedMeters: number;
      readonly teamMeters: number;
      readonly targetReached: boolean;
    };

export type ChallengeContributionSkipReason =
  | "replayed_activity"
  | "no_slot"
  | "instance_missing"
  | "instance_not_active"
  | "not_a_participant"
  | "participant_not_active"
  | "already_credited"
  | "window_unreadable"
  | "received_after_deadline"
  | "completed_outside_window"
  | "completed_in_future"
  | "no_distance";

// ---------------------------------------------------------------------------
// Local defensive readers (Firestore is schemaless at rest)
// ---------------------------------------------------------------------------

function readString(data: DocumentData | undefined, key: string): string {
  const value = data?.[key];
  return typeof value === "string" ? value : "";
}

function readNumber(data: DocumentData | undefined, key: string): number {
  const value = data?.[key];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function timestampToMillis(value: unknown): number {
  if (value instanceof Timestamp) return value.toMillis();
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return 0;
}

function readRules(data: DocumentData | undefined): ChallengeRulesSnapshot | undefined {
  const value = data?.["rules"];
  if (typeof value !== "object" || value === null) return undefined;
  return value as ChallengeRulesSnapshot;
}

function contributionMarkerRef(
  firestore: Firestore,
  challengeId: string,
  activityId: string,
): DocumentReference {
  return firestore
    .collection("challengeInstances")
    .doc(challengeId)
    .collection("contributions")
    .doc(activityId);
}

function skip(reason: ChallengeContributionSkipReason): ChallengeContributionOutcome {
  return { credited: false, reason };
}

// ---------------------------------------------------------------------------
// Seam
// ---------------------------------------------------------------------------

export async function applyChallengeContribution(
  input: ChallengeContributionInput,
): Promise<ChallengeContributionOutcome> {
  const { transaction, firestore, uid } = input;

  // A replayed deterministic activity was already offered to this seam exactly
  // once in the transaction that first persisted it. Zero reads on replay.
  if (input.activityAlreadyExists) return skip("replayed_activity");

  // -------------------- read phase (no writes yet) --------------------

  const slotSnap = await transaction.get(firestore.collection("challengeSlots").doc(uid));
  if (!slotSnap.exists) return skip("no_slot");
  const challengeId = readString(slotSnap.data(), "challengeId");
  if (challengeId.length === 0) return skip("no_slot");

  const instanceRef = firestore.collection("challengeInstances").doc(challengeId);
  const instanceSnap = await transaction.get(instanceRef);
  if (!instanceSnap.exists) return skip("instance_missing");
  const instance = instanceSnap.data() as DocumentData;
  const status = readString(instance, "status") as InstanceState;
  if (status !== "ACTIVE") return skip("instance_not_active");

  const participantRef = instanceRef.collection("participants").doc(uid);
  const participantSnap = await transaction.get(participantRef);
  if (!participantSnap.exists) return skip("not_a_participant");
  const participantStatus = readString(participantSnap.data(), "status") as ParticipantState;
  if (participantStatus !== "ACTIVE") return skip("participant_not_active");

  const markerRef = contributionMarkerRef(firestore, challengeId, input.activityId);
  const markerSnap = await transaction.get(markerRef);
  if (markerSnap.exists) return skip("already_credited");

  const rules = readRules(instance);
  const startsAtMs = timestampToMillis(instance["startsAt"]);
  const scheduledEndsAtMs = timestampToMillis(instance["scheduledEndsAt"]);
  if (rules === undefined || startsAtMs === 0 || scheduledEndsAtMs === 0) {
    return skip("window_unreadable");
  }

  // Server receipt strictly before the cutoff. No offline/late-upload grace:
  // a compliant completedAt never admits a request received after cutoff.
  if (input.nowMs >= scheduledEndsAtMs) return skip("received_after_deadline");
  if (input.completedAtMs < startsAtMs || input.completedAtMs > scheduledEndsAtMs) {
    return skip("completed_outside_window");
  }
  if (input.completedAtMs > input.nowMs) return skip("completed_in_future");

  const meters = Math.floor(input.distanceMeters);
  if (!Number.isFinite(meters) || meters <= 0) return skip("no_distance");

  const previousTeamRaw = Math.max(
    readNumber(instance, "rawTeamMeters"),
    readNumber(instance, "teamMeters"),
  );
  const newTeamRaw = previousTeamRaw + meters;
  const targetReached = newTeamRaw >= rules.targetMeters;

  // Only a completing credit needs the full roster (eligibility snapshot).
  const participantsSnap = targetReached
    ? await transaction.get(instanceRef.collection("participants"))
    : undefined;

  // -------------------- write phase --------------------

  const receivedAt = Timestamp.fromMillis(input.nowMs);
  const newCreditedMeters = readNumber(participantSnap.data(), "creditedMeters") + meters;

  // Race-safe idempotency marker: create aborts if a concurrent transaction
  // already credited this deterministic activity.
  transaction.create(markerRef, {
    activityId: input.activityId,
    challengeId,
    uid,
    meters,
    creditedAt: receivedAt,
  });
  transaction.update(participantRef, { creditedMeters: newCreditedMeters });

  if (!targetReached) {
    transaction.update(instanceRef, { teamMeters: newTeamRaw, rawTeamMeters: newTeamRaw });
    return {
      credited: true,
      challengeId,
      creditedMeters: meters,
      teamMeters: newTeamRaw,
      targetReached: false,
    };
  }

  // This credit reaches the target: exactly one transaction performs the
  // ACTIVE -> SETTLING transition (the instance doc read serializes rivals).
  const instanceTransition = transitionInstance(status, { type: "BEGIN_SETTLEMENT" }, { kind: "system" });
  if (!instanceTransition.ok) {
    // Defensive: status was re-checked ACTIVE above, so this cannot happen.
    transaction.update(instanceRef, { teamMeters: newTeamRaw, rawTeamMeters: newTeamRaw });
    return {
      credited: true,
      challengeId,
      creditedMeters: meters,
      teamMeters: newTeamRaw,
      targetReached: false,
    };
  }

  transaction.update(instanceRef, {
    status: instanceTransition.state,
    teamMeters: rules.targetMeters, // exposed field clamps at target
    rawTeamMeters: newTeamRaw,
    completedAt: receivedAt,
  });

  // Frozen per-participant eligibility snapshot at THIS instant.
  const mode = readString(instance, "mode") as ChallengeMode;
  for (const doc of participantsSnap?.docs ?? []) {
    const docStatus = readString(doc.data(), "status") as ParticipantState;
    if (docStatus !== "ACTIVE") continue; // LEFT (and any terminal) stay NOT_ELIGIBLE
    const role: ParticipantRole = readString(doc.data(), "role") === "owner" ? "owner" : "member";
    // Sanity: the pure machine must accept a future settlement edge for this
    // participant; ACTIVE always does, so this never fails in practice.
    const probe = transitionParticipant(
      { state: docStatus, role },
      { type: "SETTLE_SUCCEEDED" },
      { kind: "system" },
    );
    if (!probe.ok) continue;
    const credited = doc.id === uid ? newCreditedMeters : readNumber(doc.data(), "creditedMeters");
    // SOLO: the single owner is eligible by reaching the target — the personal
    // minimum does not apply solo. GROUP: non-LEFT ACTIVE participants at or
    // above the snapshotted personal minimum are eligible.
    const eligible = mode === "SOLO" ? true : credited >= rules.personalMinimumMeters;
    transaction.update(doc.ref, { reward: eligible ? "PENDING" : "NOT_ELIGIBLE" });
  }

  return {
    credited: true,
    challengeId,
    creditedMeters: meters,
    teamMeters: rules.targetMeters,
    targetReached: true,
  };
}
