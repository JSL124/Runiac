// Exiting a deleted runner from any challenge they are still in.
//
// This runs FIRST in the deletion fan-out, before any participation document is
// removed. Deleting `challengeInstances/{id}/participants/{uid}` directly would
// leave `rosterUids` naming a participant that no longer exists, which is the
// exact shape settlement and headcount both read, so the exit has to go through
// the challenge system's own transition rules rather than around them.
//
// It cannot reuse `leaveChallengeForCallable` / `abandonChallengeForCallable`:
// both assert `assertCallerAccountNotSuspendedInTransaction` first
// (`challengeSettlementCore.ts:118,196`), and by the time this runs the caller's
// `accountStatus` is already `deleting` — a blocking status. That assertion is
// correct for a self-service call and wrong for a system actor, so this module
// composes the same effects from the shared eviction core instead
// (`removeParticipantAsSystem`, `findEligibleSuccessor`, `cancelInstanceAsSystem`).
//
// The ownership rule is the user's decision of record and is deliberately the
// same one `challenge-premium-lapse-eviction` chose: an owner's departure
// transfers the instance to the earliest-joined remaining participant rather
// than destroying everyone else's challenge, and cancels only when no successor
// exists.

import type { Firestore } from "firebase-admin/firestore";

import { loadChallengeAccessConfig } from "../config/configLoader.js";
import {
  cancelInstanceAsSystem,
  findEligibleSuccessor,
  removeParticipantAsSystem,
} from "../challenge/challengePremiumLapse.js";
import {
  emitChallengeOwnerCancelledNotifications,
  emitChallengeParticipantLeftNotifications,
} from "../challenge/challengeNotifications.js";
import { isParticipantTerminal } from "../challenge/challengeStateMachine.js";
import {
  loadInstanceWithRoster,
  participantRef,
  readString,
  slotRef,
} from "../challenge/challengeSettlementSupport.js";
import type { ParticipantState } from "../challenge/challengeTypes.js";

// Which instance states a deleting runner is exited from.
//
// This deliberately includes SETTLING, where premium lapse deliberately stops.
// The reasoning differs because the situation does: a lapsed runner who reached
// the target inside their grace window EARNED that result and must not be
// evicted out of a settlement already in flight, whereas a runner deleting
// their account is forfeiting by their own choice, and leaving them in a
// settling instance would let the settlement sweep write a badge and a history
// document under a uid this fan-out has already erased. Exiting as LEFT makes
// them NOT_ELIGIBLE, which settlement already handles, and leaves their
// credited metres with the team.
const EXITABLE_STATUSES: readonly string[] = ["RECRUITING", "ACTIVE", "SETTLING"];

export type AccountChallengeExitResult =
  | { readonly kind: "none" }
  | { readonly kind: "left"; readonly challengeId: string }
  | { readonly kind: "transferred"; readonly challengeId: string; readonly successorUid: string }
  | { readonly kind: "cancelled"; readonly challengeId: string };

/**
 * Removes `uid` from whatever challenge their slot names. Idempotent: a replay
 * finds no slot, or finds a participant already in a terminal state, and
 * returns `none` without writing.
 */
export async function exitChallengeForAccountDeletion(
  firestore: Firestore,
  uid: string,
  nowMs: number,
): Promise<AccountChallengeExitResult> {
  // Read outside the transaction, as `syncChallengePremiumHold` does: the
  // config document is not part of the transactional state and the loader falls
  // back to defaults on any failure.
  const premiumOnlyTiers = (await loadChallengeAccessConfig(firestore)).premiumOnlyTiers;

  const outcome = await firestore.runTransaction(
    async (transaction): Promise<AccountChallengeExitResult> => {
      // `challengeSlots/{uid}` is the one-slot-per-user invariant, so it names
      // the only challenge this runner can currently be in.
      const slotSnap = await transaction.get(slotRef(firestore, uid));
      if (!slotSnap.exists) return { kind: "none" };

      const challengeId = readString(slotSnap.data(), "challengeId");
      if (challengeId.length === 0) return { kind: "none" };

      const loaded = await loadInstanceWithRoster(transaction, firestore, challengeId);
      if (loaded === undefined) return { kind: "none" };
      if (!EXITABLE_STATUSES.includes(loaded.status)) return { kind: "none" };

      const selfDoc = loaded.participants.docs.find((doc) => doc.id === uid);
      const selfData = selfDoc?.data();
      if (selfDoc === undefined || selfData === undefined) return { kind: "none" };

      const selfState = readString(selfData, "status") as ParticipantState;
      if (isParticipantTerminal(selfState)) return { kind: "none" };

      const isOwner = loaded.ownerUid === uid || readString(selfData, "role") === "owner";

      if (!isOwner) {
        removeParticipantAsSystem(
          transaction,
          firestore,
          loaded,
          challengeId,
          uid,
          selfState,
          selfData,
          nowMs,
        );
        return { kind: "left", challengeId };
      }

      // Premium is required of a successor only on a premium-only tier. On an
      // open tier every remaining participant is eligible, and demanding
      // premium there would cancel a challenge that has no premium requirement
      // in the first place.
      const requirePremium = premiumOnlyTiers.includes(readString(loaded.data, "tierId"));
      const successor = await findEligibleSuccessor(
        transaction,
        firestore,
        loaded,
        uid,
        nowMs,
        requirePremium,
      );

      if (successor === undefined) {
        // Read before writing, exactly as abandonChallenge does. A single
        // equality filter keeps this on the automatic index; the PENDING subset
        // is selected in code by cancelInstanceAsSystem.
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
          "OWNER_ACCOUNT_DELETED",
        );
        return { kind: "cancelled", challengeId };
      }

      // Ownership transfer is a field update, not an instance transition: the
      // instance state is unchanged and the challenge keeps running.
      transaction.update(loaded.ref, { ownerUid: successor });
      transaction.update(participantRef(firestore, challengeId, successor), { role: "owner" });
      const successorSlot = loaded.rosterSlots.get(successor);
      if (successorSlot !== undefined && successorSlot.exists) {
        transaction.set(successorSlot.ref, { role: "owner" }, { merge: true });
      }

      // Demote before removing. `transitionParticipant` refuses REMOVE on an
      // owner, so this ordering is enforced by the state machine rather than
      // merely observed by convention.
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
      return { kind: "transferred", challengeId, successorUid: successor };
    },
  );

  // Post-commit notification hooks, reusing the emitters the equivalent
  // self-service paths already use. Neither throws, so a delivery failure can
  // never roll back a committed exit.
  if (outcome.kind === "left" || outcome.kind === "transferred") {
    await emitChallengeParticipantLeftNotifications(firestore, outcome.challengeId, nowMs);
  } else if (outcome.kind === "cancelled") {
    await emitChallengeOwnerCancelledNotifications(firestore, outcome.challengeId, nowMs);
  }

  return outcome;
}
