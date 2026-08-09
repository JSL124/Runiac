import { friendError, FRIEND_REASON } from "./friendsErrors.js";
import { NicknameInputError, canonicalizeNickname, isRecord } from "./nickname.js";
import type { FriendsCallableRequest, RequestAction } from "./friendsTypes.js";

export function requireAuthUid(request: FriendsCallableRequest): string {
  const uid = request.auth?.uid;
  if (uid === undefined || !validUid(uid)) throw friendError(FRIEND_REASON.UNAUTHENTICATED);
  return uid;
}

export function readNickname(data: unknown): { readonly display: string; readonly canonical: string } {
  const raw = readString(data, "nickname");
  try {
    const display = raw.trim().normalize("NFC");
    return { display, canonical: canonicalizeNickname(display) };
  } catch (error: unknown) {
    if (error instanceof NicknameInputError) throw friendError(FRIEND_REASON.INVALID_ARGUMENT);
    throw error;
  }
}

export function readUid(data: unknown, field: string): string {
  const value = readString(data, field);
  if (!validUid(value)) throw friendError(FRIEND_REASON.INVALID_ARGUMENT);
  return value;
}

export function readAction(data: unknown): RequestAction {
  const value = recordOf(data)["action"];
  if (value === "accept" || value === "decline") return value;
  throw friendError(FRIEND_REASON.INVALID_ARGUMENT);
}

export function recordOf(value: unknown): Readonly<Record<string, unknown>> {
  if (!isRecord(value)) throw friendError(FRIEND_REASON.INVALID_ARGUMENT);
  return value;
}

export function dataOf(snapshot: { readonly data: () => unknown }): Readonly<Record<string, unknown>> {
  const data = snapshot.data();
  return isRecord(data) ? data : {};
}

export function stringOrUndefined(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function readString(data: unknown, field: string): string {
  const value = recordOf(data)[field];
  if (typeof value !== "string") throw friendError(FRIEND_REASON.INVALID_ARGUMENT);
  return value;
}

function validUid(value: string): boolean {
  return value.length > 0 &&
    value.length <= 128 &&
    value !== "." &&
    value !== ".." &&
    !/^__.*__$/u.test(value) &&
    !/[\/\u0000-\u001F\u007F]/u.test(value);
}
