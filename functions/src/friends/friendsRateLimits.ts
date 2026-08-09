import type { Transaction } from "firebase-admin/firestore";

import { friendError, FRIEND_REASON } from "./friendsErrors.js";
import { rateRef } from "./friendsPaths.js";

const SEARCH_WINDOW_MS = 60_000;
const SEARCH_LIMIT = 10;
const REQUEST_MINUTE_LIMIT = 3;
const REQUEST_DAY_LIMIT = 10;
const REQUEST_DAY_MS = 24 * 60 * 60 * 1000;
export const OUTSTANDING_REQUEST_LIMIT = 25;

export function nextSearchAttemptMs(rate: Readonly<Record<string, unknown>>, atMs: number): readonly number[] {
  const attempts = timestamps(rate["searchAttemptMs"], atMs - SEARCH_WINDOW_MS);
  if (attempts.length >= SEARCH_LIMIT) throw friendError(FRIEND_REASON.TRY_AGAIN_LATER);
  return [...attempts, atMs];
}

export function nextRequestAttemptMs(rate: Readonly<Record<string, unknown>>, atMs: number): readonly number[] {
  const dayAttempts = timestamps(rate["requestAttemptMs"], atMs - REQUEST_DAY_MS);
  const minuteAttempts = dayAttempts.filter((value) => value > atMs - SEARCH_WINDOW_MS);
  if (minuteAttempts.length >= REQUEST_MINUTE_LIMIT || dayAttempts.length >= REQUEST_DAY_LIMIT) {
    throw friendError(FRIEND_REASON.TRY_AGAIN_LATER);
  }
  return [...dayAttempts, atMs];
}

export function outstandingOutgoing(rate: Readonly<Record<string, unknown>>): number {
  const value = rate["outstandingOutgoing"];
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 ? value : 0;
}

export function writeSearchRate(
  transaction: Transaction,
  reference: ReturnType<typeof rateRef>,
  attempts: readonly number[],
): void {
  transaction.set(reference, { searchAttemptMs: attempts }, { merge: true });
}

export function writeRequestRate(
  transaction: Transaction,
  reference: ReturnType<typeof rateRef>,
  rate: Readonly<Record<string, unknown>>,
  attempts: readonly number[],
  outstandingDelta: number,
): void {
  transaction.set(reference, {
    requestAttemptMs: attempts,
    outstandingOutgoing: Math.max(0, outstandingOutgoing(rate) + outstandingDelta),
  }, { merge: true });
}

export function writeOutstandingDelta(
  transaction: Transaction,
  reference: ReturnType<typeof rateRef>,
  rate: Readonly<Record<string, unknown>>,
  delta: number,
): void {
  transaction.set(reference, { outstandingOutgoing: Math.max(0, outstandingOutgoing(rate) + delta) }, { merge: true });
}

function timestamps(value: unknown, minimumMs: number): readonly number[] {
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is number => typeof entry === "number" && Number.isSafeInteger(entry) && entry > minimumMs);
}
