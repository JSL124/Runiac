// Stable, machine-readable Challenge failure reason codes.
//
// Every Challenge callable failure path throws through `challengeError`, which
// maps a stable reason string onto the coarse callable transport code and
// carries the reason both as the HttpsError message and inside `details.reason`.
// Tests assert reason codes by value (never by prose), so these constants are
// the single source of truth for the callable failure contract.

import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

export const CHALLENGE_REASON = {
  // Auth / arguments
  UNAUTHENTICATED: "UNAUTHENTICATED",
  INVALID_ARGUMENT: "INVALID_ARGUMENT",
  UNKNOWN_TIER: "UNKNOWN_TIER",
  CANNOT_INVITE_SELF: "CANNOT_INVITE_SELF",
  // Entitlement (config/challengeAccess): the tier requires a premium
  // subscription to create a lobby for.
  PREMIUM_REQUIRED: "PREMIUM_REQUIRED",
  // Slot ownership
  ALREADY_HOLDS_SLOT: "ALREADY_HOLDS_SLOT",
  // Instance lookup / ownership / state
  CHALLENGE_NOT_FOUND: "CHALLENGE_NOT_FOUND",
  NOT_LOBBY_OWNER: "NOT_LOBBY_OWNER",
  NOT_CHALLENGE_OWNER: "NOT_CHALLENGE_OWNER",
  NOT_A_PARTICIPANT: "NOT_A_PARTICIPANT",
  OWNER_CANNOT_LEAVE: "OWNER_CANNOT_LEAVE",
  CHALLENGE_NOT_ACTIVE: "CHALLENGE_NOT_ACTIVE",
  LOBBY_NOT_RECRUITING: "LOBBY_NOT_RECRUITING",
  LOBBY_EXPIRED: "LOBBY_EXPIRED",
  LOBBY_FULL: "LOBBY_FULL",
  // Invitations
  INVITE_CAPACITY_EXCEEDED: "INVITE_CAPACITY_EXCEEDED",
  INVITEE_ALREADY_PARTICIPANT: "INVITEE_ALREADY_PARTICIPANT",
  INVITEE_NOT_RECIPROCAL_FRIEND: "INVITEE_NOT_RECIPROCAL_FRIEND",
  INVITEE_BLOCKED: "INVITEE_BLOCKED",
  INVITATION_NOT_FOUND: "INVITATION_NOT_FOUND",
  NOT_INVITATION_RECIPIENT: "NOT_INVITATION_RECIPIENT",
  INVITATION_NOT_PENDING: "INVITATION_NOT_PENDING",
  NOT_RECIPROCAL_FRIEND: "NOT_RECIPROCAL_FRIEND",
  // State-machine denial fallback (should not surface in normal flows)
  ILLEGAL_STATE: "ILLEGAL_STATE",
} as const;

export type ChallengeReason = (typeof CHALLENGE_REASON)[keyof typeof CHALLENGE_REASON];

// Maps each stable reason onto the callable transport code. Anything not listed
// defaults to `failed-precondition` (a state/precondition conflict).
const REASON_TRANSPORT: Readonly<Record<ChallengeReason, FunctionsErrorCode>> = {
  UNAUTHENTICATED: "unauthenticated",
  INVALID_ARGUMENT: "invalid-argument",
  UNKNOWN_TIER: "invalid-argument",
  CANNOT_INVITE_SELF: "invalid-argument",
  PREMIUM_REQUIRED: "permission-denied",
  ALREADY_HOLDS_SLOT: "failed-precondition",
  CHALLENGE_NOT_FOUND: "not-found",
  NOT_LOBBY_OWNER: "permission-denied",
  NOT_CHALLENGE_OWNER: "permission-denied",
  NOT_A_PARTICIPANT: "permission-denied",
  OWNER_CANNOT_LEAVE: "failed-precondition",
  CHALLENGE_NOT_ACTIVE: "failed-precondition",
  LOBBY_NOT_RECRUITING: "failed-precondition",
  LOBBY_EXPIRED: "failed-precondition",
  LOBBY_FULL: "failed-precondition",
  INVITE_CAPACITY_EXCEEDED: "failed-precondition",
  INVITEE_ALREADY_PARTICIPANT: "failed-precondition",
  INVITEE_NOT_RECIPROCAL_FRIEND: "failed-precondition",
  INVITEE_BLOCKED: "failed-precondition",
  INVITATION_NOT_FOUND: "not-found",
  NOT_INVITATION_RECIPIENT: "permission-denied",
  INVITATION_NOT_PENDING: "failed-precondition",
  NOT_RECIPROCAL_FRIEND: "failed-precondition",
  ILLEGAL_STATE: "failed-precondition",
};

// Build a callable error carrying a stable reason. The reason is both the
// message and `details.reason` so HTTP callers and direct-core callers can each
// read it deterministically.
export function challengeError(reason: ChallengeReason): HttpsError {
  return new HttpsError(REASON_TRANSPORT[reason], reason, { reason });
}

// Read a stable reason from a caught error, or undefined if it is not a
// Challenge error. Used by tests and by nothing in production.
export function readChallengeReason(error: unknown): ChallengeReason | undefined {
  if (typeof error !== "object" || error === null) return undefined;
  const details = (error as { readonly details?: unknown }).details;
  if (typeof details === "object" && details !== null) {
    const reason = (details as { readonly reason?: unknown }).reason;
    if (typeof reason === "string" && isChallengeReason(reason)) return reason;
  }
  return undefined;
}

function isChallengeReason(value: string): value is ChallengeReason {
  return Object.prototype.hasOwnProperty.call(REASON_TRANSPORT, value);
}
