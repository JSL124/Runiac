import type { Timestamp } from "firebase-admin/firestore";

import { isRecord } from "./nickname.js";

export const CANCEL_COOLDOWN_MS = 24 * 60 * 60 * 1000;
export const DECLINE_COOLDOWN_MS = 7 * 24 * 60 * 60 * 1000;
export const REMOVE_COOLDOWN_MS = 24 * 60 * 60 * 1000;

export function cooldownAllows(cooldown: Readonly<Record<string, unknown>>, uid: string, atMs: number): boolean {
  const pairUntil = numberOrZero(cooldown["pairCooldownUntilMs"]);
  return Math.max(pairUntil, directionalCooldownUntil(cooldown, uid)) <= atMs;
}

export function directionalCooldownUntil(cooldown: Readonly<Record<string, unknown>>, uid: string): number {
  const values = cooldown["directionalCooldownUntilByUid"];
  if (!isRecord(values)) return 0;
  return numberOrZero(values[uid]);
}

export function directionalCooldown(
  cooldown: Readonly<Record<string, unknown>>,
  uid: string,
  untilMs: number,
  at: Timestamp,
) {
  const existing = cooldown["directionalCooldownUntilByUid"];
  const values = isRecord(existing) ? existing : {};
  return {
    directionalCooldownUntilByUid: { ...values, [uid]: untilMs },
    lastOutcome: "DECLINED",
    lastOutcomeSenderUid: uid,
    updatedAt: at,
  };
}

export function cancellationCooldown(
  cooldown: Readonly<Record<string, unknown>>,
  uid: string,
  untilMs: number,
  at: Timestamp,
) {
  const existing = cooldown["directionalCooldownUntilByUid"];
  const values = isRecord(existing) ? existing : {};
  return { directionalCooldownUntilByUid: { ...values, [uid]: untilMs }, updatedAt: at };
}

export function isRecordedDecline(cooldown: Readonly<Record<string, unknown>>, senderUid: string): boolean {
  return cooldown["lastOutcome"] === "DECLINED" && cooldown["lastOutcomeSenderUid"] === senderUid;
}

export function clearRecordedDecline(at: Timestamp) {
  return {
    lastOutcome: null,
    lastOutcomeSenderUid: null,
    updatedAt: at,
  };
}

function numberOrZero(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 ? value : 0;
}
