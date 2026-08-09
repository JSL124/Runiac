// Server-owned Challenge distance system contracts.
//
// This module is pure: it declares typed unions, catalog entry shapes, state
// machine actor/result types, and the Firestore document write shapes for the
// Challenge distance system. It must never import `firebase-admin`,
// `firebase-functions`, or any Firestore SDK, and must never contain UI copy.
// All eligibility-relevant numbers are integer metres or integer durations.

// ---------------------------------------------------------------------------
// Catalog identity
// ---------------------------------------------------------------------------

export const CHALLENGE_CATALOG_VERSION = "challenge-distance-v1";

export type ChallengeCatalogVersion = typeof CHALLENGE_CATALOG_VERSION;

// Nine active launch tiers. Order is display order only; the catalog itself is
// keyed by tier id (never a positional array).
export type ChallengeTierId =
  | "10K"
  | "20K"
  | "42K"
  | "100K"
  | "200K"
  | "250K"
  | "300K"
  | "500K"
  | "1000K";

// A single immutable catalog entry. All numeric fields are integers; distances
// are metres and durations are exact (days and their millisecond equivalent).
export type ChallengeCatalogEntry = {
  readonly tierId: ChallengeTierId;
  readonly difficultyLabel: string;
  readonly durationDays: number;
  readonly durationMs: number;
  readonly maxParticipants: number;
  readonly maxInvitedFriends: number;
  readonly soloTargetMeters: number;
  readonly personalMinimumMeters: number;
};

// The rules snapshotted onto an instance at start. Immutable thereafter.
export type ChallengeRulesSnapshot = {
  readonly tierId: ChallengeTierId;
  readonly catalogVersion: ChallengeCatalogVersion;
  readonly difficultyLabel: string;
  readonly durationDays: number;
  readonly durationMs: number;
  readonly maxParticipants: number;
  readonly maxInvitedFriends: number;
  readonly targetMeters: number;
  readonly personalMinimumMeters: number;
};

// ---------------------------------------------------------------------------
// Mode and state unions
// ---------------------------------------------------------------------------

export type ChallengeMode = "SOLO" | "GROUP";

export type InstanceState =
  | "RECRUITING"
  | "ACTIVE"
  | "SETTLING"
  | "SUCCEEDED"
  | "FAILED"
  | "CANCELLED"
  | "EXPIRED";

export type InvitationState =
  | "PENDING"
  | "ACCEPTED"
  | "DECLINED"
  | "REVOKED"
  | "EXPIRED";

export type ParticipantRole = "owner" | "member";

export type ParticipantState =
  | "ACCEPTED"
  | "ACTIVE"
  | "LEFT"
  | "CANCELLED"
  | "SUCCEEDED"
  | "INELIGIBLE"
  | "FAILED";

export type RewardState = "NOT_ELIGIBLE" | "PENDING" | "ISSUED";

// Why an instance reached a terminal state. Server-authored.
export type ChallengeTerminalReason =
  | "TARGET_REACHED"
  | "DEADLINE_FAILED"
  | "OWNER_ABANDONED"
  | "LOBBY_CANCELLED"
  | "LOBBY_EXPIRED"
  // The owner's premium subscription lapsed on a premium-only tier and no
  // remaining participant was eligible to inherit the instance. Distinct from
  // OWNER_ABANDONED because the owner did not choose to end it.
  | "OWNER_PREMIUM_LAPSED"
  // The owner deleted their Runiac account and no remaining participant was
  // eligible to inherit the instance. Distinct from OWNER_ABANDONED because the
  // owner ended their account rather than this challenge, and distinct from
  // OWNER_PREMIUM_LAPSED because it can fire on any tier, not only premium-only
  // ones, and is never recoverable by re-subscribing.
  | "OWNER_ACCOUNT_DELETED";

// ---------------------------------------------------------------------------
// State machine actors, actions, and results
// ---------------------------------------------------------------------------

// Identity is resolved by the transaction layer before the pure machine runs.
// `owner` = the instance owner; `self` = the acting participant/recipient;
// `other` = any other authenticated user; `system` = trusted backend worker.
export type ChallengeActorKind = "owner" | "self" | "other" | "system";

export type ChallengeActor = {
  readonly kind: ChallengeActorKind;
};

export type ChallengeTransitionError =
  | "TERMINAL_STATE"
  | "ILLEGAL_TRANSITION"
  | "FORBIDDEN_ACTOR"
  | "MODE_ROSTER_MISMATCH"
  | "OWNER_CANNOT_LEAVE";

export type TransitionResult<TState> =
  | { readonly ok: true; readonly state: TState }
  | { readonly ok: false; readonly error: ChallengeTransitionError };

export type InstanceAction =
  | { readonly type: "START"; readonly mode: ChallengeMode; readonly rosterSize: number }
  | { readonly type: "CANCEL_LOBBY" }
  | { readonly type: "EXPIRE_LOBBY" }
  | { readonly type: "BEGIN_SETTLEMENT" }
  | { readonly type: "ABANDON" }
  | { readonly type: "SETTLE_SUCCEEDED" }
  | { readonly type: "SETTLE_FAILED" };

export type InvitationAction =
  | { readonly type: "ACCEPT" }
  | { readonly type: "DECLINE" }
  | { readonly type: "REVOKE" }
  | { readonly type: "EXPIRE" };

export type ParticipantAction =
  | { readonly type: "ACTIVATE" }
  | { readonly type: "WITHDRAW" }
  | { readonly type: "LEAVE" }
  // Server-initiated removal (premium-lapse eviction). Same destination as
  // LEAVE, but only `system` may perform it, and — like the self-exits — it
  // may never be applied to an owner, so the eviction path has to transfer
  // ownership (demoting them to `member`) or cancel the instance first.
  | { readonly type: "REMOVE" }
  | { readonly type: "CANCEL" }
  | { readonly type: "SETTLE_SUCCEEDED" }
  | { readonly type: "SETTLE_INELIGIBLE" }
  | { readonly type: "SETTLE_FAILED" };

export type ParticipantContext = {
  readonly state: ParticipantState;
  readonly role: ParticipantRole;
};

export type RewardAction = { readonly type: "ISSUE" };

// ---------------------------------------------------------------------------
// Firestore document write shapes (server-authored)
// ---------------------------------------------------------------------------

// Server-managed Firestore timestamp value. Declared as `unknown` so these pure
// contract types never depend on the firebase-admin Timestamp type.
export type ServerTimestamp = unknown;

// challengeInstances/{challengeId}
export type ChallengeInstanceDoc = {
  readonly challengeId: string;
  readonly ownerUid: string;
  readonly tierId: ChallengeTierId;
  readonly catalogVersion: ChallengeCatalogVersion;
  readonly mode: ChallengeMode;
  readonly status: InstanceState;
  readonly rules: ChallengeRulesSnapshot;
  readonly rosterUids: readonly string[];
  readonly maxParticipants: number;
  readonly teamMeters: number;
  readonly createdAt: ServerTimestamp;
  // Exactly createdAt + 24h; the lazily-enforced lobby expiry instant.
  readonly lobbyExpiresAt: ServerTimestamp;
  readonly startsAt?: ServerTimestamp;
  readonly scheduledEndsAt?: ServerTimestamp;
  readonly settledAt?: ServerTimestamp;
  readonly terminalReason?: ChallengeTerminalReason;
  // Unclamped credited total. `teamMeters` (the exposed field) clamps at
  // `rules.targetMeters` the instant the target is reached; this preserves the
  // raw sum for audit. Present once the first contribution is credited.
  readonly rawTeamMeters?: number;
  // Server receipt instant of the contribution that reached the target
  // (ACTIVE -> SETTLING). Absent until the target is reached.
  readonly completedAt?: ServerTimestamp;
};

// challengeInstances/{challengeId}/participants/{uid}
// Contains ONLY role/status, credited metres, eligibility/result, and minimal
// server-authored identity snapshots. Never routes, coordinates, run
// timestamps, or activity history.
export type ChallengeParticipantDoc = {
  readonly uid: string;
  readonly role: ParticipantRole;
  readonly status: ParticipantState;
  readonly creditedMeters: number;
  readonly reward: RewardState;
  readonly result?: ParticipantState;
  readonly displayNameSnapshot: string;
  readonly avatarInitialsSnapshot: string;
};

// challengeInvitations/{inviteId} (top-level)
export type ChallengeInvitationDoc = {
  readonly inviteId: string;
  readonly challengeId: string;
  readonly tierId: ChallengeTierId;
  readonly ownerUid: string;
  readonly recipientUid: string;
  readonly status: InvitationState;
  readonly createdAt: ServerTimestamp;
  readonly expiresAt: ServerTimestamp;
  readonly respondedAt?: ServerTimestamp;
};

// challengeSlots/{uid} — one server-owned reservation per user.
export type ChallengeSlotDoc = {
  readonly uid: string;
  readonly challengeId: string;
  readonly tierId: ChallengeTierId;
  readonly role: ParticipantRole;
  readonly reservedAt: ServerTimestamp;
};

// challengePremiumHolds/{uid} — the premium-lapse grace window.
//
// Written only by the server, denied to every client in `firestore.rules`. It
// is keyed by uid, not by challenge, because `challengeSlots/{uid}` already
// guarantees at most one live challenge per runner. It is deliberately NOT
// stored on the participant document: that subcollection is readable by every
// roster member, so a field there would broadcast one runner's subscription
// state to their whole challenge.
export type ChallengePremiumHoldDoc = {
  readonly uid: string;
  readonly challengeId: string;
  readonly tierId: string;
  readonly role: ParticipantRole;
  readonly lapsedAt: ServerTimestamp;
  readonly graceExpiresAt: ServerTimestamp;
};

// challengeRewardGrants/{challengeId_uid} — idempotent grant ledger.
export type ChallengeRewardGrantDoc = {
  readonly challengeId: string;
  readonly uid: string;
  readonly tierId: ChallengeTierId;
  readonly status: RewardState;
  readonly grantedAt?: ServerTimestamp;
};

// users/{uid}/challengeHistory/{challengeId}
export type ChallengeHistoryDoc = {
  readonly challengeId: string;
  readonly tierId: ChallengeTierId;
  readonly mode: ChallengeMode;
  readonly role: ParticipantRole;
  readonly outcome: ParticipantState;
  // Absent only on a leaver's history doc while the instance is still running;
  // settlement/abandon/deadline later merges the instance terminal reason in.
  readonly terminalReason?: ChallengeTerminalReason;
  readonly teamMeters: number;
  readonly personalMeters: number;
  readonly targetMeters: number;
  readonly personalMinimumMeters: number;
  readonly startedAt: ServerTimestamp;
  readonly endedAt: ServerTimestamp;
};

// users/{uid}/challengeBadges/{tierId} — one ownership doc per tier.
export type ChallengeBadgeDoc = {
  readonly tierId: ChallengeTierId;
  readonly catalogVersion: ChallengeCatalogVersion;
  readonly firstEarnedChallengeId: string;
  readonly earnedAt: ServerTimestamp;
};
