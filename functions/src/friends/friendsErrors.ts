import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

export const FRIEND_REASON = {
  UNAUTHENTICATED: "UNAUTHENTICATED",
  INVALID_ARGUMENT: "INVALID_ARGUMENT",
  CANNOT_TARGET_SELF: "CANNOT_TARGET_SELF",
  TRY_AGAIN_LATER: "TRY_AGAIN_LATER",
  STALE_SOCIAL_STATE: "STALE_SOCIAL_STATE",
  NICKNAME_UNAVAILABLE: "NICKNAME_UNAVAILABLE",
  PROFILE_REQUIRED: "PROFILE_REQUIRED",
  USER_INACTIVE: "USER_INACTIVE",
  NOT_PLATFORM_ADMIN: "NOT_PLATFORM_ADMIN",
  NICKNAME_MIGRATION_INVALID: "NICKNAME_MIGRATION_INVALID",
  NICKNAME_RENAME_TOO_LARGE: "NICKNAME_RENAME_TOO_LARGE",
  MIGRATION_TOO_LARGE: "MIGRATION_TOO_LARGE",
} as const;

export type FriendReason = (typeof FRIEND_REASON)[keyof typeof FRIEND_REASON];

const TRANSPORT_BY_REASON: Readonly<Record<FriendReason, FunctionsErrorCode>> = {
  UNAUTHENTICATED: "unauthenticated",
  INVALID_ARGUMENT: "invalid-argument",
  CANNOT_TARGET_SELF: "invalid-argument",
  TRY_AGAIN_LATER: "resource-exhausted",
  STALE_SOCIAL_STATE: "failed-precondition",
  NICKNAME_UNAVAILABLE: "failed-precondition",
  PROFILE_REQUIRED: "failed-precondition",
  USER_INACTIVE: "failed-precondition",
  NOT_PLATFORM_ADMIN: "permission-denied",
  NICKNAME_MIGRATION_INVALID: "failed-precondition",
  NICKNAME_RENAME_TOO_LARGE: "failed-precondition",
  MIGRATION_TOO_LARGE: "resource-exhausted",
};

export function friendError(reason: FriendReason): HttpsError {
  return new HttpsError(TRANSPORT_BY_REASON[reason], reason, { reason });
}

export function readFriendReason(error: unknown): FriendReason | undefined {
  if (!(error instanceof HttpsError) || !isRecord(error.details)) return undefined;
  const reason = error.details["reason"];
  return typeof reason === "string" && isFriendReason(reason) ? reason : undefined;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isFriendReason(value: string): value is FriendReason {
  return Object.hasOwn(TRANSPORT_BY_REASON, value);
}
