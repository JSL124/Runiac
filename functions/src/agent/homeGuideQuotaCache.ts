import { randomUUID } from "node:crypto";
import { Timestamp, type Firestore } from "firebase-admin/firestore";
import { createHomeGuideContextFingerprint, singaporeDayKey } from "./homeGuideQuotaFingerprint.js";

export { createHomeGuideContextFingerprint, singaporeDayKey } from "./homeGuideQuotaFingerprint.js";

// Daily quota and result cache for the Home guide agent.
//
// Two jobs, both about not paying for the same generation twice. A generated
// guide is cached against a fingerprint of the context it was built from, so an
// unchanged day reuses it; and each runner gets a bounded number of generations
// per Singapore day.
//
// Reservation is lease-based ([LEASE_MILLIS]) rather than a plain counter
// increment: two devices opening Home at once must not both be granted the last
// generation of the day, and a request that dies mid-flight must not consume
// quota forever — the lease simply expires.

const DAILY_SCHEMA_VERSION = 1;
const MAX_ATTEMPTS = 3;
const LEASE_MILLIS = 90_000;
const DAILY_FIELD_NAMES = new Set([
  "schemaVersion",
  "ownerUid",
  "dayKey",
  "attemptCount",
  "readyFingerprint",
  "readyBundle",
  "pendingAttempt",
  "createdAt",
  "updatedAt",
]);
const BUNDLE_FIELD_NAMES = new Set(["planSummary", "runningTip", "progressionCheckIn"]);
const PENDING_FIELD_NAMES = new Set(["attemptId", "fingerprint", "leaseExpiresAt"]);

export type HomeGuideBundle = {
  readonly planSummary: string;
  readonly runningTip: string;
  readonly progressionCheckIn: string;
};

export type HomeGuideQuotaReservation = {
  readonly attemptId: string;
  readonly fingerprint: string;
};

export type HomeGuideQuotaReserveInput = {
  readonly firestore: Firestore;
  readonly uid: string;
  readonly now: Date;
  readonly fingerprint: string;
  readonly fallback: HomeGuideBundle;
};

export type HomeGuideQuotaOutcome =
  | { readonly kind: "cache"; readonly bundle: HomeGuideBundle }
  | { readonly kind: "leased"; readonly fallback: HomeGuideBundle }
  | { readonly kind: "reserved"; readonly reservation: HomeGuideQuotaReservation; readonly fallback: HomeGuideBundle }
  | { readonly kind: "fallback"; readonly fallback: HomeGuideBundle };

export type HomeGuideQuotaFinalizeInput = {
  readonly firestore: Firestore;
  readonly uid: string;
  readonly now: Date;
  readonly reservation: HomeGuideQuotaReservation;
  readonly bundle: HomeGuideBundle;
};

type HomeGuideQuotaAttemptInput = Omit<HomeGuideQuotaFinalizeInput, "bundle">;
type ReadyState = { readonly fingerprint: string; readonly bundle: HomeGuideBundle };
type PendingState = { readonly attemptId: string; readonly fingerprint: string; readonly leaseExpiresAt: Timestamp };
type ValidState = {
  readonly kind: "valid";
  readonly attemptCount: number;
  readonly ready: ReadyState | null;
  readonly pending: PendingState | null;
  readonly createdAt: Timestamp;
};
type DailyState = ValidState | { readonly kind: "missing" | "invalid" };
type DailyDocumentInput = {
  readonly ownerUid: string;
  readonly dayKey: string;
  readonly state: ValidState;
  readonly updatedAt: Timestamp;
};

export class HomeGuideQuotaInputError extends Error {
  public constructor() {
    super("Home guide quota requires a valid UID, fingerprint, and server time.");
    this.name = "HomeGuideQuotaInputError";
  }
}

export async function reserveHomeGuideQuota(input: HomeGuideQuotaReserveInput): Promise<HomeGuideQuotaOutcome> {
  const dayKey = singaporeDayKey(input.now);
  validateReservationInput(input);
  const now = Timestamp.fromDate(input.now);
  const nowMillis = now.toMillis();
  const reference = input.firestore.collection("agentGuidanceDaily").doc(`${input.uid}_${dayKey}`);
  return input.firestore.runTransaction(async (transaction) => {
    const state = readDailyState((await transaction.get(reference)).data(), input.uid, dayKey);
    if (state.kind === "invalid") return { kind: "fallback", fallback: input.fallback };
    const current = state.kind === "valid" ? state : emptyState(now);
    if (current.ready?.fingerprint === input.fingerprint) return { kind: "cache", bundle: current.ready.bundle };
    if (current.pending?.fingerprint === input.fingerprint && current.pending.leaseExpiresAt.toMillis() > nowMillis) {
      return { kind: "leased", fallback: input.fallback };
    }
    if (current.attemptCount >= MAX_ATTEMPTS) return { kind: "fallback", fallback: input.fallback };
    const reservation = { attemptId: randomUUID(), fingerprint: input.fingerprint };
    const next: ValidState = {
      ...current,
      attemptCount: current.attemptCount + 1,
      pending: { ...reservation, leaseExpiresAt: Timestamp.fromMillis(nowMillis + LEASE_MILLIS) },
    };
    transaction.set(reference, dailyDocument({ ownerUid: input.uid, dayKey, state: next, updatedAt: now }));
    return { kind: "reserved", reservation, fallback: input.fallback };
  });
}

export async function finalizeHomeGuideAttemptReady(input: HomeGuideQuotaFinalizeInput): Promise<boolean> {
  return finalizeAttempt(input, input.bundle);
}

export async function finalizeHomeGuideAttemptFailure(input: HomeGuideQuotaAttemptInput): Promise<boolean> {
  return finalizeAttempt(input, null);
}

async function finalizeAttempt(
  input: HomeGuideQuotaAttemptInput,
  bundle: HomeGuideBundle | null,
): Promise<boolean> {
  const dayKey = singaporeDayKey(input.now);
  if (input.uid.length === 0 || !isValidReservation(input.reservation)) throw new HomeGuideQuotaInputError();
  const timestamp = Timestamp.fromDate(input.now);
  const reference = input.firestore.collection("agentGuidanceDaily").doc(`${input.uid}_${dayKey}`);
  return input.firestore.runTransaction(async (transaction) => {
    const document = await transaction.get(reference);
    const state = readDailyState(document.data(), input.uid, dayKey);
    if (
      state.kind !== "valid"
      || state.pending === null
      || !matchesPendingAttempt(state.pending, input.reservation)
      || state.pending.leaseExpiresAt.toMillis() <= timestamp.toMillis()
    ) return false;
    const next: ValidState = {
      ...state,
      ready: bundle === null ? state.ready : { fingerprint: input.reservation.fingerprint, bundle },
      pending: null,
    };
    transaction.set(reference, dailyDocument({ ownerUid: input.uid, dayKey, state: next, updatedAt: timestamp }));
    return true;
  });
}

function emptyState(createdAt: Timestamp): ValidState {
  return { kind: "valid", attemptCount: 0, ready: null, pending: null, createdAt };
}

function dailyDocument(input: DailyDocumentInput): Readonly<Record<string, unknown>> {
  return {
    schemaVersion: DAILY_SCHEMA_VERSION,
    ownerUid: input.ownerUid,
    dayKey: input.dayKey,
    attemptCount: input.state.attemptCount,
    ...(input.state.ready === null ? {} : { readyFingerprint: input.state.ready.fingerprint, readyBundle: persistedBundle(input.state.ready.bundle) }),
    ...(input.state.pending === null ? {} : { pendingAttempt: input.state.pending }),
    createdAt: input.state.createdAt,
    updatedAt: input.updatedAt,
  };
}

function readDailyState(value: unknown, ownerUid: string, dayKey: string): DailyState {
  if (value === undefined) return { kind: "missing" };
  if (!isRecord(value) || !hasOnlyKnownKeys(value, DAILY_FIELD_NAMES) || value["schemaVersion"] !== DAILY_SCHEMA_VERSION || value["ownerUid"] !== ownerUid || value["dayKey"] !== dayKey) return { kind: "invalid" };
  const attemptCount = value["attemptCount"];
  const createdAt = value["createdAt"];
  const ready = readReady(value);
  const pending = readPending(value);
  if (!isAttemptCount(attemptCount) || !(createdAt instanceof Timestamp) || ready === undefined || pending === undefined) {
    return { kind: "invalid" };
  }
  return { kind: "valid", attemptCount, ready, pending, createdAt };
}

function readReady(value: Readonly<Record<string, unknown>>): ReadyState | null | undefined {
  const fingerprint = value["readyFingerprint"];
  const bundle = value["readyBundle"];
  if (fingerprint === undefined && bundle === undefined) return null;
  return typeof fingerprint === "string" && isBundle(bundle) ? { fingerprint, bundle } : undefined;
}

function readPending(value: Readonly<Record<string, unknown>>): PendingState | null | undefined {
  const pending = value["pendingAttempt"];
  if (pending === undefined) return null;
  if (!isRecord(pending) || !hasOnlyKnownKeys(pending, PENDING_FIELD_NAMES) || typeof pending["attemptId"] !== "string" || typeof pending["fingerprint"] !== "string" || !(pending["leaseExpiresAt"] instanceof Timestamp)) return undefined;
  return { attemptId: pending["attemptId"], fingerprint: pending["fingerprint"], leaseExpiresAt: pending["leaseExpiresAt"] };
}

function isBundle(value: unknown): value is HomeGuideBundle {
  return isRecord(value) && hasOnlyKnownKeys(value, BUNDLE_FIELD_NAMES) && typeof value["planSummary"] === "string" && typeof value["runningTip"] === "string" && typeof value["progressionCheckIn"] === "string";
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKnownKeys(value: Readonly<Record<string, unknown>>, allowed: ReadonlySet<string>): boolean {
  return Object.keys(value).every((key) => allowed.has(key));
}

function persistedBundle(bundle: HomeGuideBundle): HomeGuideBundle {
  return {
    planSummary: bundle.planSummary,
    runningTip: bundle.runningTip,
    progressionCheckIn: bundle.progressionCheckIn,
  };
}

function validateReservationInput(input: HomeGuideQuotaReserveInput): void {
  if (input.uid.length === 0 || !isValidReservation({ attemptId: "validation", fingerprint: input.fingerprint }) || !Number.isFinite(input.now.getTime())) throw new HomeGuideQuotaInputError();
}

function isValidReservation(reservation: HomeGuideQuotaReservation): boolean {
  return reservation.attemptId.length > 0 && /^[a-f0-9]{64}$/u.test(reservation.fingerprint);
}

function matchesPendingAttempt(pending: PendingState, reservation: HomeGuideQuotaReservation): boolean {
  return pending.attemptId === reservation.attemptId && pending.fingerprint === reservation.fingerprint;
}

function isAttemptCount(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= MAX_ATTEMPTS;
}
