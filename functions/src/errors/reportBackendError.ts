import { FieldValue, getFirestore, type Firestore } from "firebase-admin/firestore";
import { firestoreErrorGroupStore, type ErrorGroupStore } from "./errorGroupStore.js";
import { buildFingerprint, deriveSeverity, sanitizeFrames, sanitizeMessage } from "./sanitize.js";

/**
 * Backend counterpart to reportAppError: turns an unexpected Cloud Functions
 * fault (or a deliberate non-fatal degraded event, e.g. a configLoader
 * fallback) into an errorGroups/{fp} document with source: "functions".
 *
 * Contract: NEVER throws. Every path is wrapped so a reporting failure can
 * never mask or replace the original error the caller is already handling.
 * Classification (which errors are worth reporting) is the caller's job —
 * see withErrorReporting.ts — this function unconditionally reports whatever
 * it is given.
 */

const SUPPRESSION_WINDOW_MS = 60_000;
const SUPPRESSION_MAP_CAP = 50;

// In-memory per-instance suppression keyed by fingerprint. A retrying
// trigger or a crash-looping scheduled job would otherwise hammer a single
// errorGroups document past its ~1 write/sec ceiling. Capped and FIFO-evicted
// so this can never grow unbounded across a long-lived instance.
const lastReportedAtMs = new Map<string, number>();

export type ReportBackendErrorInput = {
  readonly functionName: string;
  readonly error: unknown;
  readonly uid?: string;
  readonly fatal: boolean;
};

export type ReportBackendErrorPort = {
  readonly now: () => Date;
  readonly serverTimestamp: () => unknown;
  readonly store: ErrorGroupStore;
};

export async function reportBackendError(
  input: ReportBackendErrorInput,
  port?: ReportBackendErrorPort,
): Promise<void> {
  try {
    // Resolved INSIDE the try block, deliberately. A default parameter is
    // evaluated at call time before the function body (and its try) is ever
    // entered, so `firebaseReportBackendErrorPort()` throwing (e.g.
    // getFirestore() with no default app initialised — reachable from
    // configLoader.ts, which is imported in contexts that do not always call
    // initializeApp()) would otherwise escape uncaught and replace the
    // caller's original error. Resolving here keeps that failure inside the
    // same swallow-everything boundary as the rest of this function.
    const resolved = port ?? firebaseReportBackendErrorPort();

    const nowMs = resolved.now().getTime();
    const described = describeError(input.error);
    const sanitizedMessage = sanitizeMessage(described.message);
    const sanitizedFrames = sanitizeFrames(described.frames);
    const topFrame = sanitizedFrames[0] ?? "";
    const fingerprint = buildFingerprint({
      errorType: described.errorType,
      topFrame,
      screen: input.functionName,
    });

    if (isSuppressed(fingerprint, nowMs)) {
      return;
    }
    recordReported(fingerprint, nowMs);

    await resolved.store.ingestErrorGroup({
      fingerprint,
      ...(input.uid === undefined ? {} : { uid: input.uid }),
      buildDocument: (existing, isNewReporter) => {
        const occurrences = (existing?.occurrences ?? 0) + 1;
        const affectedUserCount = (existing?.affectedUserCount ?? 0) + (isNewReporter ? 1 : 0);
        const severity = deriveSeverity({ fatal: input.fatal, occurrences, affectedUserCount });
        return {
          title: sanitizedMessage,
          errorType: described.errorType,
          screen: input.functionName,
          appVersion: process.env["K_REVISION"] ?? "unknown",
          os: "nodejs22",
          platform: "functions",
          source: "functions",
          occurrences,
          affectedUserCount,
          severity,
          status: existing?.status ?? "new",
          firstSeenAt: existing?.firstSeenAt ?? resolved.serverTimestamp(),
          lastSeenAt: resolved.serverTimestamp(),
          updatedAt: resolved.serverTimestamp(),
          stackSummary: sanitizedFrames.join("\n"),
          sanitized: true,
          note: existing?.note ?? "",
        };
      },
    });
  } catch {
    // Swallowed by design: reportBackendError must never throw, and it must
    // never change what the caller ultimately does with its own error.
  }
}

function isSuppressed(fingerprint: string, nowMs: number): boolean {
  const last = lastReportedAtMs.get(fingerprint);
  return last !== undefined && nowMs - last < SUPPRESSION_WINDOW_MS;
}

function recordReported(fingerprint: string, nowMs: number): void {
  if (!lastReportedAtMs.has(fingerprint) && lastReportedAtMs.size >= SUPPRESSION_MAP_CAP) {
    const oldestKey = lastReportedAtMs.keys().next().value;
    if (oldestKey !== undefined) {
      lastReportedAtMs.delete(oldestKey);
    }
  }
  lastReportedAtMs.set(fingerprint, nowMs);
}

type DescribedError = {
  readonly errorType: string;
  readonly message: string;
  readonly frames: readonly string[];
};

function describeError(error: unknown): DescribedError {
  if (error instanceof Error) {
    return {
      errorType: error.name.length > 0 ? error.name : error.constructor.name,
      message: error.message,
      frames: framesFromStack(error.stack),
    };
  }
  return {
    errorType: "UnknownError",
    message: describeNonError(error),
    frames: [],
  };
}

function framesFromStack(stack: string | undefined): readonly string[] {
  if (stack === undefined) {
    return [];
  }
  // The first line is "<ErrorName>: <message>", not a stack frame.
  return stack
    .split("\n")
    .slice(1)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
}

function describeNonError(error: unknown): string {
  if (typeof error === "string") {
    return error;
  }
  try {
    return JSON.stringify(error) ?? String(error);
  } catch {
    return String(error);
  }
}

export function firebaseReportBackendErrorPort(firestore: Firestore = getFirestore()): ReportBackendErrorPort {
  return {
    now: () => new Date(),
    serverTimestamp: () => FieldValue.serverTimestamp(),
    store: firestoreErrorGroupStore(firestore),
  };
}
