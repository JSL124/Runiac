// Pure Challenge state machines.
//
// Four typed unions with pure transition functions, typed errors, and actor
// permission checks. No firebase imports, no Firestore access, no UI copy.
// Identity resolution (who is owner/self/other) happens in the transaction
// layer before these functions run; the pure machine only enforces which actor
// *kind* may perform each edge, plus mode/roster and owner-leave guards.
//
// State machines:
//   instance:    RECRUITING -> ACTIVE -> SETTLING -> SUCCEEDED | FAILED
//                RECRUITING -> CANCELLED | EXPIRED ; ACTIVE -> CANCELLED
//   invitation:  PENDING -> ACCEPTED | DECLINED | REVOKED | EXPIRED
//   participant: ACCEPTED -> ACTIVE | LEFT | CANCELLED ;
//                ACTIVE -> LEFT | CANCELLED | SUCCEEDED | INELIGIBLE | FAILED
//   reward:      NOT_ELIGIBLE (terminal) ; PENDING -> ISSUED

import type {
  ChallengeActor,
  ChallengeActorKind,
  ChallengeMode,
  InstanceAction,
  InstanceState,
  InvitationAction,
  InvitationState,
  ParticipantAction,
  ParticipantContext,
  ParticipantState,
  RewardAction,
  RewardState,
  TransitionResult,
} from "./challengeTypes.js";

// ---------------------------------------------------------------------------
// Terminal-state sets
// ---------------------------------------------------------------------------

const INSTANCE_TERMINAL: readonly InstanceState[] = ["SUCCEEDED", "FAILED", "CANCELLED", "EXPIRED"];
const INVITATION_TERMINAL: readonly InvitationState[] = ["ACCEPTED", "DECLINED", "REVOKED", "EXPIRED"];
const PARTICIPANT_TERMINAL: readonly ParticipantState[] = [
  "LEFT",
  "CANCELLED",
  "SUCCEEDED",
  "INELIGIBLE",
  "FAILED",
];
const REWARD_TERMINAL: readonly RewardState[] = ["NOT_ELIGIBLE", "ISSUED"];

export function isInstanceTerminal(state: InstanceState): boolean {
  return INSTANCE_TERMINAL.includes(state);
}

export function isInvitationTerminal(state: InvitationState): boolean {
  return INVITATION_TERMINAL.includes(state);
}

export function isParticipantTerminal(state: ParticipantState): boolean {
  return PARTICIPANT_TERMINAL.includes(state);
}

export function isRewardTerminal(state: RewardState): boolean {
  return REWARD_TERMINAL.includes(state);
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

type Edge<TState> = {
  readonly to: TState;
  readonly actors: readonly ChallengeActorKind[];
};

function ok<TState>(state: TState): TransitionResult<TState> {
  return { ok: true, state };
}

function fail<TState>(error: TransitionResult<TState> & { ok: false }): TransitionResult<TState> {
  return error;
}

function actorAllowed(actor: ChallengeActor, allowed: readonly ChallengeActorKind[]): boolean {
  return allowed.includes(actor.kind);
}

function startModeRosterConsistent(mode: ChallengeMode, rosterSize: number): boolean {
  if (!Number.isInteger(rosterSize) || rosterSize < 1) return false;
  if (mode === "SOLO") return rosterSize === 1;
  return rosterSize >= 2;
}

// ---------------------------------------------------------------------------
// Instance state machine
// ---------------------------------------------------------------------------

function instanceEdge(state: InstanceState, action: InstanceAction["type"]): Edge<InstanceState> | null {
  if (state === "RECRUITING") {
    if (action === "START") return { to: "ACTIVE", actors: ["owner"] };
    if (action === "CANCEL_LOBBY") return { to: "CANCELLED", actors: ["owner"] };
    if (action === "EXPIRE_LOBBY") return { to: "EXPIRED", actors: ["system"] };
    return null;
  }
  if (state === "ACTIVE") {
    if (action === "BEGIN_SETTLEMENT") return { to: "SETTLING", actors: ["system"] };
    if (action === "ABANDON") return { to: "CANCELLED", actors: ["owner"] };
    return null;
  }
  if (state === "SETTLING") {
    if (action === "SETTLE_SUCCEEDED") return { to: "SUCCEEDED", actors: ["system"] };
    if (action === "SETTLE_FAILED") return { to: "FAILED", actors: ["system"] };
    return null;
  }
  return null;
}

export function transitionInstance(
  state: InstanceState,
  action: InstanceAction,
  actor: ChallengeActor,
): TransitionResult<InstanceState> {
  if (isInstanceTerminal(state)) return fail({ ok: false, error: "TERMINAL_STATE" });
  const edge = instanceEdge(state, action.type);
  if (edge === null) return fail({ ok: false, error: "ILLEGAL_TRANSITION" });
  if (!actorAllowed(actor, edge.actors)) return fail({ ok: false, error: "FORBIDDEN_ACTOR" });
  if (action.type === "START" && !startModeRosterConsistent(action.mode, action.rosterSize)) {
    return fail({ ok: false, error: "MODE_ROSTER_MISMATCH" });
  }
  return ok(edge.to);
}

// ---------------------------------------------------------------------------
// Invitation state machine
// ---------------------------------------------------------------------------

function invitationEdge(
  state: InvitationState,
  action: InvitationAction["type"],
): Edge<InvitationState> | null {
  if (state !== "PENDING") return null;
  if (action === "ACCEPT") return { to: "ACCEPTED", actors: ["self"] };
  if (action === "DECLINE") return { to: "DECLINED", actors: ["self"] };
  if (action === "REVOKE") return { to: "REVOKED", actors: ["owner"] };
  if (action === "EXPIRE") return { to: "EXPIRED", actors: ["system"] };
  return null;
}

export function transitionInvitation(
  state: InvitationState,
  action: InvitationAction,
  actor: ChallengeActor,
): TransitionResult<InvitationState> {
  if (isInvitationTerminal(state)) return fail({ ok: false, error: "TERMINAL_STATE" });
  const edge = invitationEdge(state, action.type);
  if (edge === null) return fail({ ok: false, error: "ILLEGAL_TRANSITION" });
  if (!actorAllowed(actor, edge.actors)) return fail({ ok: false, error: "FORBIDDEN_ACTOR" });
  return ok(edge.to);
}

// ---------------------------------------------------------------------------
// Participant state machine
// ---------------------------------------------------------------------------

// Actions that may never be applied to an owner. LEAVE/WITHDRAW are the
// self-service exits (the owner abandons the whole instance instead). REMOVE is
// a system action rather than a self-exit, but it is guarded identically on
// purpose: it makes "an owner is never silently dropped out of their own
// challenge" a property of the machine, so the premium-lapse eviction path is
// forced either to transfer ownership first or to cancel the instance.
const PARTICIPANT_OWNER_BLOCKED_ACTIONS: readonly ParticipantAction["type"][] = [
  "WITHDRAW",
  "LEAVE",
  "REMOVE",
];

function participantEdge(
  state: ParticipantState,
  action: ParticipantAction["type"],
): Edge<ParticipantState> | null {
  if (state === "ACCEPTED") {
    if (action === "ACTIVATE") return { to: "ACTIVE", actors: ["system"] };
    if (action === "WITHDRAW") return { to: "LEFT", actors: ["self"] };
    if (action === "REMOVE") return { to: "LEFT", actors: ["system"] };
    if (action === "CANCEL") return { to: "CANCELLED", actors: ["system"] };
    return null;
  }
  if (state === "ACTIVE") {
    if (action === "LEAVE") return { to: "LEFT", actors: ["self"] };
    if (action === "REMOVE") return { to: "LEFT", actors: ["system"] };
    if (action === "CANCEL") return { to: "CANCELLED", actors: ["system"] };
    if (action === "SETTLE_SUCCEEDED") return { to: "SUCCEEDED", actors: ["system"] };
    if (action === "SETTLE_INELIGIBLE") return { to: "INELIGIBLE", actors: ["system"] };
    if (action === "SETTLE_FAILED") return { to: "FAILED", actors: ["system"] };
    return null;
  }
  return null;
}

export function transitionParticipant(
  context: ParticipantContext,
  action: ParticipantAction,
  actor: ChallengeActor,
): TransitionResult<ParticipantState> {
  if (isParticipantTerminal(context.state)) return fail({ ok: false, error: "TERMINAL_STATE" });
  const edge = participantEdge(context.state, action.type);
  if (edge === null) return fail({ ok: false, error: "ILLEGAL_TRANSITION" });
  if (!actorAllowed(actor, edge.actors)) return fail({ ok: false, error: "FORBIDDEN_ACTOR" });
  if (PARTICIPANT_OWNER_BLOCKED_ACTIONS.includes(action.type) && context.role === "owner") {
    return fail({ ok: false, error: "OWNER_CANNOT_LEAVE" });
  }
  return ok(edge.to);
}

// ---------------------------------------------------------------------------
// Reward state machine
// ---------------------------------------------------------------------------

function rewardEdge(state: RewardState, action: RewardAction["type"]): Edge<RewardState> | null {
  if (state === "PENDING" && action === "ISSUE") return { to: "ISSUED", actors: ["system"] };
  return null;
}

export function transitionReward(
  state: RewardState,
  action: RewardAction,
  actor: ChallengeActor,
): TransitionResult<RewardState> {
  if (isRewardTerminal(state)) return fail({ ok: false, error: "TERMINAL_STATE" });
  const edge = rewardEdge(state, action.type);
  if (edge === null) return fail({ ok: false, error: "ILLEGAL_TRANSITION" });
  if (!actorAllowed(actor, edge.actors)) return fail({ ok: false, error: "FORBIDDEN_ACTOR" });
  return ok(edge.to);
}
