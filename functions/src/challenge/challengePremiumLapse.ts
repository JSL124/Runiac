// Premium-lapse grace window and eviction for challenge participation.
//
// The problem this closes: the premium gate used to be a single check at lobby
// creation (`createChallengeLobbyForCallable`), so a runner who dropped to
// Basic mid-challenge kept accruing metres on a premium-only tier and was still
// awarded the badge at settlement. Nothing in the contribution, settlement or
// expiry paths reads subscription state, and `firestore.rules` scopes challenge
// reads by roster membership rather than by `isPremiumUser()`.
//
// The shape of the fix, per the user's decisions of record (2026-08-04):
//
//   1. A lapse does not evict immediately. It opens a 24-hour hold, during
//      which the app warns the runner and offers the paywall. Re-subscribing
//      inside the window clears the hold with no loss at all.
//   2. When the window closes and the runner is still Basic, they are removed
//      with exactly the effects of a self-service `leaveChallenge`.
//   3. A lapsed OWNER does not destroy everyone else's challenge: ownership
//      transfers to the earliest-joined remaining member who is currently
//      premium. Only when no such member exists — every SOLO instance, and any
//      group whose other members are also lapsed — is the instance cancelled.
//
// Two callers drive this module. `syncChallengePremiumHold` runs from the
// `users/{uid}` update trigger and from the subscription-expiry sweep, and
// `runChallengePremiumLapseSweep` runs from the one-minute challenge schedule.

import { Timestamp, type Firestore, type Transaction } from "firebase-admin/firestore";
import type { DocumentData, DocumentSnapshot, QueryDocumentSnapshot } from "firebase-admin/firestore";

import { isPremiumSubscription } from "../progression/progressionAuditHelpers.js";
import { loadChallengeAccessConfig } from "../config/configLoader.js";
import {
  emitChallengeOwnerCancelledNotifications,
  emitChallengeParticipantLeftNotifications,
} from "./challengeNotifications.js";
import { isParticipantTerminal, transitionParticipant } from "./challengeStateMachine.js";
import {
  buildHistoryDoc,
  historyRef,
  instanceRef,
  loadInstanceWithRoster,
  participantRef,
  readRoster,
  readString,
  releaseSlotIfHeldHere,
  slotRef,
  timestampToMillis,
  type LoadedInstance,
} from "./challengeSettlementSupport.js";
import type { ChallengeTerminalReason, ParticipantState } from "./challengeTypes.js";

// The user-specified grace window. Deliberately a module constant rather than a
// `config/challengeAccess` field: adding one would require mirroring the
// validator into the separate `website/` admin repository and through
// `tests/cross-system/config-contract-drift.mjs`. Promoting it to config later
// is an additive change.
export const PREMIUM_LAPSE_GRACE_MS = 24 * 60 * 60 * 1000;

const HOLDS = "challengePremiumHolds";

// Upper bound on holds examined per sweep. The schedule runs every minute, so
// any backlog drains almost immediately while one run stays bounded.
const SWEEP_QUERY_LIMIT = 100;

// Only these two states can carry a hold. SETTLING is deliberately excluded:
// an instance only reaches it by hitting its target, so a runner who finished
// the challenge inside their grace window keeps the result they earned rather
// than being evicted out of a settlement that is already in flight.
const HOLDABLE_STATUSES: readonly string[] = ["RECRUITING", "ACTIVE"];

export type PremiumHoldSyncResult =
  | { readonly kind: "opened"; readonly challengeId: string; readonly graceExpiresAtMs: number }
  | { readonly kind: "unchanged"; readonly challengeId: string; readonly graceExpiresAtMs: number }
  | { readonly kind: "cleared" }
  | { readonly kind: "none" };

export type PremiumLapseSweepOptions = {
  // Test seam, mirroring runSubscriptionExpirySweep: invoked once after the
  // candidate query resolves and before any eviction transaction runs, which is
  // the exact window in which a re-subscription must be able to win.
  readonly afterCandidateQuery?: () => Promise<void>;
  readonly candidateLimit?: number;
};

export type PremiumLapseSweepResult = {
  readonly evictedCount: number;
  readonly cancelledCount: number;
  readonly clearedCount: number;
};

// ---------------------------------------------------------------------------
// Hold synchronisation
// ---------------------------------------------------------------------------

/**
 * Brings `challengePremiumHolds/{uid}` into line with the runner's current
 * subscription and challenge participation. Idempotent, and — critically —
 * NEVER extends an existing hold: `users/{uid}` is written by `completeRun` on
 * every finished run, so an extending sync would push the deadline out forever
 * and eviction would never fire for an active runner.
 */
export async function syncChallengePremiumHold(
  firestore: Firestore,
  uid: string,
  nowMs: number,
): Promise<PremiumHoldSyncResult> {
  // Read outside the transaction: the config document is not part of the
  // transactional state, and the loader falls back to defaults on any failure.
  const premiumOnlyTiers = (await loadChallengeAccessConfig(firestore)).premiumOnlyTiers;

  return firestore.runTransaction(async (transaction) => {
    const holdRef = firestore.doc(`${HOLDS}/${uid}`);
    const [userSnap, slotSnap, holdSnap] = await transaction.getAll(
      firestore.doc(`users/${uid}`),
      slotRef(firestore, uid),
      holdRef,
    );

    const gate = await readHoldGate({
      transaction,
      firestore,
      uid,
      userSnap: userSnap as DocumentSnapshot,
      slotSnap: slotSnap as DocumentSnapshot,
      premiumOnlyTiers,
      nowMs,
    });

    const holdExists = (holdSnap as DocumentSnapshot).exists;

    if (gate === undefined) {
      if (holdExists) {
        transaction.delete(holdRef);
        return { kind: "cleared" as const };
      }
      return { kind: "none" as const };
    }

    // An existing hold for the SAME challenge is left exactly as it is. A hold
    // naming a different challenge is stale (the runner left one premium-tier
    // challenge and joined another while still Basic), so the window restarts
    // against the challenge they are actually in.
    if (holdExists && readString((holdSnap as DocumentSnapshot).data(), "challengeId") === gate.challengeId) {
      return {
        kind: "unchanged" as const,
        challengeId: gate.challengeId,
        graceExpiresAtMs: timestampToMillis((holdSnap as DocumentSnapshot).data()?.["graceExpiresAt"]),
      };
    }

    const graceExpiresAtMs = nowMs + PREMIUM_LAPSE_GRACE_MS;
    transaction.set(holdRef, {
      uid,
      challengeId: gate.challengeId,
      tierId: gate.tierId,
      role: gate.role,
      lapsedAt: Timestamp.fromMillis(nowMs),
      graceExpiresAt: Timestamp.fromMillis(graceExpiresAtMs),
    });
    return { kind: "opened" as const, challengeId: gate.challengeId, graceExpiresAtMs };
  });
}

type HoldGate = {
  readonly challengeId: string;
  readonly tierId: string;
  readonly role: "owner" | "member";
};

// Returns the challenge a hold should cover, or undefined when no hold is
// warranted (premium runner, open tier, no slot, missing or terminal instance).
async function readHoldGate(args: {
  readonly transaction: Transaction;
  readonly firestore: Firestore;
  readonly uid: string;
  readonly userSnap: DocumentSnapshot;
  readonly slotSnap: DocumentSnapshot;
  readonly premiumOnlyTiers: readonly string[];
  readonly nowMs: number;
}): Promise<HoldGate | undefined> {
  if (isPremiumSubscription(args.userSnap.data(), args.nowMs)) return undefined;
  if (!args.slotSnap.exists) return undefined;

  const challengeId = readString(args.slotSnap.data(), "challengeId");
  if (challengeId.length === 0) return undefined;

  const instanceSnap = await args.transaction.get(instanceRef(args.firestore, challengeId));
  const instance = instanceSnap.data();
  if (!instanceSnap.exists || instance === undefined) return undefined;
  if (!HOLDABLE_STATUSES.includes(readString(instance, "status"))) return undefined;

  const tierId = readString(instance, "tierId");
  if (!args.premiumOnlyTiers.includes(tierId)) return undefined;

  return {
    challengeId,
    tierId,
    role: readString(args.slotSnap.data(), "role") === "owner" ? "owner" : "member",
  };
}

// ---------------------------------------------------------------------------
// Eviction sweep
// ---------------------------------------------------------------------------

type EvictionOutcome =
  | { readonly kind: "evicted"; readonly challengeId: string }
  | { readonly kind: "cancelled"; readonly challengeId: string }
  | { readonly kind: "cleared" }
  | { readonly kind: "skipped" };

/**
 * Evicts every runner whose grace window has closed and who is still not
 * premium. Each eviction runs in its own transaction that re-reads and
 * re-asserts the predicate, so a re-subscription committed between the
 * candidate query and the write wins instead of being clobbered — the same
 * discipline `runSubscriptionExpirySweep` uses.
 */
export async function runChallengePremiumLapseSweep(
  firestore: Firestore,
  nowMs: number,
  options?: PremiumLapseSweepOptions,
): Promise<PremiumLapseSweepResult> {
  const due = await firestore
    .collection(HOLDS)
    .where("graceExpiresAt", "<=", Timestamp.fromMillis(nowMs))
    .limit(options?.candidateLimit ?? SWEEP_QUERY_LIMIT)
    .get();

  if (due.empty) return { evictedCount: 0, cancelledCount: 0, clearedCount: 0 };

  if (options?.afterCandidateQuery !== undefined) {
    await options.afterCandidateQuery();
  }

  const premiumOnlyTiers = (await loadChallengeAccessConfig(firestore)).premiumOnlyTiers;

  // Owners are processed before members, so the order in which Firestore
  // happens to return the candidates cannot change the outcome. If a whole
  // group lapsed together, the owner's pass cancels the instance and resolves
  // every member's hold with it, instead of the members first being evicted
  // one by one out of an instance that was about to be cancelled anyway.
  const ordered = [...due.docs].sort(compareOwnersFirst);

  let evictedCount = 0;
  let cancelledCount = 0;
  let clearedCount = 0;
  const leftChallengeIds: string[] = [];
  const cancelledChallengeIds: string[] = [];

  for (const candidate of ordered) {
    const outcome = await applyPremiumLapseEviction(firestore, candidate.id, nowMs, premiumOnlyTiers);
    if (outcome.kind === "evicted") {
      evictedCount += 1;
      leftChallengeIds.push(outcome.challengeId);
    } else if (outcome.kind === "cancelled") {
      cancelledCount += 1;
      cancelledChallengeIds.push(outcome.challengeId);
    } else if (outcome.kind === "cleared") {
      clearedCount += 1;
    }
  }

  // Post-commit notification hooks, reusing the emitters the equivalent
  // self-service paths already use. Neither throws, so a delivery failure can
  // never roll back a committed eviction.
  for (const challengeId of new Set(leftChallengeIds)) {
    await emitChallengeParticipantLeftNotifications(firestore, challengeId, nowMs);
  }
  for (const challengeId of new Set(cancelledChallengeIds)) {
    await emitChallengeOwnerCancelledNotifications(firestore, challengeId, nowMs);
  }

  return { evictedCount, cancelledCount, clearedCount };
}

function compareOwnersFirst(left: QueryDocumentSnapshot, right: QueryDocumentSnapshot): number {
  const leftOwner = readString(left.data(), "role") === "owner" ? 0 : 1;
  const rightOwner = readString(right.data(), "role") === "owner" ? 0 : 1;
  if (leftOwner !== rightOwner) return leftOwner - rightOwner;
  return left.id.localeCompare(right.id);
}

async function applyPremiumLapseEviction(
  firestore: Firestore,
  uid: string,
  nowMs: number,
  premiumOnlyTiers: readonly string[],
): Promise<EvictionOutcome> {
  return firestore.runTransaction(async (transaction) => {
    const holdRef = firestore.doc(`${HOLDS}/${uid}`);
    const holdSnap = await transaction.get(holdRef);
    const hold = holdSnap.data();
    // The hold may have been resolved since the candidate query — most often by
    // this same sweep, when the owner's cancellation released it.
    if (!holdSnap.exists || hold === undefined) return { kind: "skipped" };
    if (timestampToMillis(hold["graceExpiresAt"]) > nowMs) return { kind: "skipped" };

    const userSnap = await transaction.get(firestore.doc(`users/${uid}`));
    if (isPremiumSubscription(userSnap.data(), nowMs)) {
      transaction.delete(holdRef);
      return { kind: "cleared" };
    }

    const challengeId = readString(hold, "challengeId");
    const loaded = await loadInstanceWithRoster(transaction, firestore, challengeId);
    if (loaded === undefined) {
      transaction.delete(holdRef);
      return { kind: "cleared" };
    }
    if (!HOLDABLE_STATUSES.includes(loaded.status)) {
      transaction.delete(holdRef);
      return { kind: "cleared" };
    }
    if (!premiumOnlyTiers.includes(readString(loaded.data, "tierId"))) {
      transaction.delete(holdRef);
      return { kind: "cleared" };
    }

    const selfDoc = loaded.participants.docs.find((doc) => doc.id === uid);
    const selfData = selfDoc?.data();
    if (selfDoc === undefined || selfData === undefined) {
      transaction.delete(holdRef);
      return { kind: "cleared" };
    }
    const selfState = readString(selfData, "status") as ParticipantState;
    if (isParticipantTerminal(selfState)) {
      transaction.delete(holdRef);
      return { kind: "cleared" };
    }

    const isOwner =
      loaded.ownerUid === uid || readString(selfData, "role") === "owner";

    if (!isOwner) {
      removeParticipantAsSystem(transaction, firestore, loaded, challengeId, uid, selfState, selfData, nowMs);
      transaction.delete(holdRef);
      return { kind: "evicted", challengeId };
    }

    const successor = await findEligibleSuccessor(transaction, firestore, loaded, uid, nowMs, true);
    if (successor === undefined) {
      // Read before writing, exactly as abandonChallenge does. A single
      // equality filter keeps this on the automatic index; the PENDING subset
      // is selected in code.
      const invitations = await transaction.get(
        firestore.collection("challengeInvitations").where("challengeId", "==", challengeId),
      );
      cancelInstanceAsSystem(
        transaction,
        firestore,
        loaded,
        challengeId,
        invitations.docs,
        nowMs,
        "OWNER_PREMIUM_LAPSED",
      );
      return { kind: "cancelled", challengeId };
    }

    // Ownership transfer is a field update, not an instance transition: the
    // instance state is unchanged and the challenge keeps running for everyone
    // who is still eligible.
    transaction.update(loaded.ref, { ownerUid: successor });
    transaction.update(participantRef(firestore, challengeId, successor), { role: "owner" });
    const successorSlot = loaded.rosterSlots.get(successor);
    if (successorSlot !== undefined && successorSlot.exists) {
      transaction.set(successorSlot.ref, { role: "owner" }, { merge: true });
    }

    // Demote before removing. `transitionParticipant` refuses REMOVE on an
    // owner, so this ordering is enforced by the state machine, not merely
    // observed by convention.
    removeParticipantAsSystem(
      transaction,
      firestore,
      loaded,
      challengeId,
      uid,
      selfState,
      { ...selfData, role: "member" },
      nowMs,
    );
    transaction.delete(holdRef);
    return { kind: "evicted", challengeId };
  });
}

// The earliest-joined remaining participant eligible to inherit the instance.
// `rosterUids` is append-ordered (owner first, then acceptance order), so it is
// the join order.
//
// `requirePremium` exists because the two callers face different tiers. Premium
// lapse only ever fires on a premium-only tier, so it always requires premium
// and decides eligibility on the CURRENT subscription rather than on the
// absence of a hold — a member who re-subscribed but whose stale hold has not
// been swept yet can still inherit. Account deletion can fire on ANY tier, so
// on an open tier it must not reject an otherwise-valid Basic successor and
// cancel a challenge that has no premium requirement at all.
export async function findEligibleSuccessor(
  transaction: Transaction,
  firestore: Firestore,
  loaded: LoadedInstance,
  departingUid: string,
  nowMs: number,
  requirePremium: boolean,
): Promise<string | undefined> {
  const candidates = readRoster(loaded.data).filter((uid) => {
    if (uid === departingUid) return false;
    const doc = loaded.participants.docs.find((participant) => participant.id === uid);
    const data = doc?.data();
    if (doc === undefined || data === undefined) return false;
    return !isParticipantTerminal(readString(data, "status") as ParticipantState);
  });

  if (candidates.length === 0) return undefined;
  if (!requirePremium) return candidates[0];

  const userSnaps = await transaction.getAll(
    ...candidates.map((uid) => firestore.doc(`users/${uid}`)),
  );
  return candidates.find((_uid, index) =>
    isPremiumSubscription(userSnaps[index]?.data(), nowMs),
  );
}

// Identical side effects to a self-service `leaveChallenge`: the participant is
// LEFT, their slot is released, a history document freezes their progress, and
// their credited metres stay in `teamMeters`. Reward eligibility is already
// NOT_ELIGIBLE for anyone who has not reached settlement, so no badge follows.
//
// Exported because account deletion needs the identical effect for a different
// reason. Both callers must agree on what "removed by the system" means to a
// challenge, so the rule lives here once rather than being reimplemented per
// caller. The self-service path in `challengeSettlementCore.ts` deliberately
// does NOT route through this: it additionally asserts the caller is not
// suspended, which is exactly the assertion a system actor must bypass.
export function removeParticipantAsSystem(
  transaction: Transaction,
  firestore: Firestore,
  loaded: LoadedInstance,
  challengeId: string,
  uid: string,
  state: ParticipantState,
  participantData: DocumentData,
  nowMs: number,
): void {
  const transition = transitionParticipant(
    { state, role: readString(participantData, "role") === "owner" ? "owner" : "member" },
    { type: "REMOVE" },
    { kind: "system" },
  );
  if (!transition.ok) return;

  transaction.update(participantRef(firestore, challengeId, uid), {
    role: "member",
    status: "LEFT",
    result: "LEFT",
  });
  releaseSlotIfHeldHere(transaction, loaded, challengeId, uid);
  transaction.set(
    historyRef(firestore, uid, challengeId),
    buildHistoryDoc({
      challengeId,
      instanceData: loaded.data,
      participantData,
      outcome: "LEFT",
      endedAtMs: nowMs,
    }),
  );
}

// Same terminal effects as an owner abandon, under a caller-supplied terminal
// reason: participants CANCELLED, slots released, PENDING invitations REVOKED,
// and every roster member's hold resolved so a later sweep has nothing to
// retry. Clearing holds is correct for every caller, not just premium lapse: a
// cancelled instance can never evict anyone, so any hold naming it is stale.
//
// Exported for account deletion, which needs identical effects under
// OWNER_ACCOUNT_DELETED. The reason is a parameter rather than a branch so the
// two callers cannot drift in what "the owner is gone" does to the instance.
export function cancelInstanceAsSystem(
  transaction: Transaction,
  firestore: Firestore,
  loaded: LoadedInstance,
  challengeId: string,
  invitations: readonly QueryDocumentSnapshot[],
  nowMs: number,
  terminalReason: ChallengeTerminalReason,
): void {
  const settledAt = Timestamp.fromMillis(nowMs);

  transaction.update(loaded.ref, {
    status: "CANCELLED",
    terminalReason,
    settledAt,
  });

  for (const doc of loaded.participants.docs) {
    const data = doc.data();
    const state = readString(data, "status") as ParticipantState;
    const role = readString(data, "role") === "owner" ? "owner" : "member";
    if (state === "LEFT") {
      // A leaver keeps their LEFT snapshot; only the terminal reason merges in.
      transaction.set(
        historyRef(firestore, doc.id, challengeId),
        { terminalReason },
        { merge: true },
      );
      continue;
    }
    const cancel = transitionParticipant({ state, role }, { type: "CANCEL" }, { kind: "system" });
    if (!cancel.ok) continue;
    transaction.update(doc.ref, { status: "CANCELLED", result: "CANCELLED" });
    transaction.set(
      historyRef(firestore, doc.id, challengeId),
      buildHistoryDoc({
        challengeId,
        instanceData: loaded.data,
        participantData: data,
        outcome: "CANCELLED",
        terminalReason,
        endedAtMs: nowMs,
      }),
    );
  }

  for (const uid of loaded.roster) {
    releaseSlotIfHeldHere(transaction, loaded, challengeId, uid);
    transaction.delete(firestore.doc(`${HOLDS}/${uid}`));
  }

  for (const doc of invitations) {
    if (readString(doc.data(), "status") === "PENDING") {
      transaction.update(doc.ref, { status: "REVOKED", respondedAt: settledAt });
    }
  }
}
