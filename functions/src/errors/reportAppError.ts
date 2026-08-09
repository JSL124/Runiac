import { FieldValue, Timestamp, getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { rejectUnsupportedFields } from "../run/rejectUnsupportedFields.js";
import { shouldEnforceAppCheck } from "../security/appCheck.js";
import {
  firestoreErrorGroupStore,
  type ErrorGroupDocument,
  type ExistingErrorGroup,
} from "./errorGroupStore.js";
import { buildFingerprint, deriveSeverity, sanitizeFrames, sanitizeMessage } from "./sanitize.js";

const ALLOWED_PAYLOAD_KEYS = new Set([
  "errorType",
  "message",
  "stackFrames",
  "screen",
  "appVersion",
  "osVersion",
  "platform",
  "fatal",
  "occurredAt",
]);
const PLATFORMS = new Set(["ios", "android"]);
const SCREEN_PATTERN = /^[A-Za-z0-9 /_-]{1,60}$/;

const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
const RATE_LIMIT_MAX = 30;

const MAX_ERROR_TYPE_LENGTH = 100;
const MAX_RAW_MESSAGE_LENGTH = 4000;
const MAX_VERSION_LENGTH = 40;
const MAX_RAW_STACK_FRAMES = 100;
// Bounds how many stale rate-limit ledger docs are deleted per report, so a
// long-overdue cleanup never adds unpredictable latency to ingest itself.
const RATE_LIMIT_PRUNE_BATCH = 50;

type ReportAppErrorRequest = {
  readonly auth?: { readonly uid: string };
  readonly data: unknown;
};

type ReportAppErrorResult = { readonly groupId: string };

// Re-exported for existing consumers (including the test suite): the ingest
// transaction and its document/existing-state shapes now live in
// errorGroupStore.ts, shared with reportBackendError.ts.
export type { ErrorGroupDocument, ExistingErrorGroup };

export type ReportAppErrorPort = {
  readonly now: () => Date;
  readonly serverTimestamp: () => unknown;
  readonly recentReportCount: (uid: string, since: Date) => Promise<number>;
  readonly recordReportEvent: (uid: string, at: Date) => Promise<void>;
  readonly ingestErrorGroup: (input: {
    readonly fingerprint: string;
    readonly uid: string;
    readonly buildDocument: (
      existing: ExistingErrorGroup | undefined,
      isNewReporter: boolean,
    ) => ErrorGroupDocument;
  }) => Promise<void>;
};

export const reportAppError = onCall<unknown, Promise<ReportAppErrorResult>>(
  { region: "asia-southeast1", enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => reportAppErrorForCallable(request, firebaseReportAppErrorPort()),
);

export async function reportAppErrorForCallable(
  request: ReportAppErrorRequest,
  port: ReportAppErrorPort = firebaseReportAppErrorPort(),
): Promise<ReportAppErrorResult> {
  const uid = authenticatedUid(request);
  const payload = parsePayload(request.data);

  // Best-effort, non-transactional rate limit: two concurrent reports from
  // the same caller can both observe a count below the threshold and both
  // succeed, but the query bound keeps sustained abuse (or a crash loop) in
  // check.
  const since = new Date(port.now().getTime() - RATE_LIMIT_WINDOW_MS);
  const recentCount = await port.recentReportCount(uid, since);
  if (recentCount >= RATE_LIMIT_MAX) {
    throw new HttpsError("resource-exhausted", "Too many error reports. Please try again later.");
  }
  await port.recordReportEvent(uid, port.now());

  // Sanitise before anything is persisted or logged, never after.
  const sanitizedMessage = sanitizeMessage(payload.message);
  const sanitizedFrames = sanitizeFrames(payload.stackFrames);
  const topFrame = sanitizedFrames[0] ?? "";
  const fingerprint = buildFingerprint({ errorType: payload.errorType, topFrame, screen: payload.screen });

  await port.ingestErrorGroup({
    fingerprint,
    uid,
    buildDocument: (existing, isNewReporter) => {
      const occurrences = (existing?.occurrences ?? 0) + 1;
      const affectedUserCount = (existing?.affectedUserCount ?? 0) + (isNewReporter ? 1 : 0);
      const severity = deriveSeverity({ fatal: payload.fatal, occurrences, affectedUserCount });
      return {
        title: sanitizedMessage,
        errorType: payload.errorType,
        screen: payload.screen,
        appVersion: payload.appVersion,
        os: payload.osVersion,
        platform: payload.platform,
        source: "mobile",
        occurrences,
        affectedUserCount,
        severity,
        status: existing?.status ?? "new",
        firstSeenAt: existing?.firstSeenAt ?? port.serverTimestamp(),
        lastSeenAt: port.serverTimestamp(),
        updatedAt: port.serverTimestamp(),
        stackSummary: sanitizedFrames.join("\n"),
        sanitized: true,
        note: existing?.note ?? "",
      };
    },
  });

  return { groupId: fingerprint };
}

function authenticatedUid(request: ReportAppErrorRequest): string {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return uid;
}

type ParsedPayload = {
  readonly errorType: string;
  readonly message: string;
  readonly stackFrames: readonly string[];
  readonly screen: string;
  readonly appVersion: string;
  readonly osVersion: string;
  readonly platform: string;
  readonly fatal: boolean;
};

function parsePayload(data: unknown): ParsedPayload {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "An error report payload object is required.");
  }
  // Rejects client-supplied severity/fingerprint/occurrences/affectedUserCount/
  // status outright: those keys are not in the allowlist, so they never reach
  // the derivation logic below.
  rejectUnsupportedFields(data, ALLOWED_PAYLOAD_KEYS, "Error report payload");

  const errorType = requireNonEmptyString(data["errorType"], "errorType", MAX_ERROR_TYPE_LENGTH);
  const message = requireNonEmptyString(data["message"], "message", MAX_RAW_MESSAGE_LENGTH);
  const stackFrames = requireStringArray(data["stackFrames"]);
  const screen = optionalScreen(data["screen"]);
  const appVersion = requireNonEmptyString(data["appVersion"], "appVersion", MAX_VERSION_LENGTH);
  const osVersion = requireNonEmptyString(data["osVersion"], "osVersion", MAX_VERSION_LENGTH);
  const platform = requirePlatform(data["platform"]);
  const fatal = optionalBoolean(data["fatal"]);
  validateOccurredAt(data["occurredAt"]);

  return { errorType, message, stackFrames, screen, appVersion, osVersion, platform, fatal };
}

function requireNonEmptyString(value: unknown, fieldName: string, maxLength: number): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${fieldName} must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > maxLength) {
    throw new HttpsError(
      "invalid-argument",
      `${fieldName} must be non-empty and at most ${maxLength} characters.`,
    );
  }
  return trimmed;
}

function requireStringArray(value: unknown): readonly string[] {
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "stackFrames must be an array of strings.");
  }
  if (value.length > MAX_RAW_STACK_FRAMES) {
    throw new HttpsError(
      "invalid-argument",
      `stackFrames must contain at most ${MAX_RAW_STACK_FRAMES} entries.`,
    );
  }
  return value.map((entry) => {
    if (typeof entry !== "string") {
      throw new HttpsError("invalid-argument", "stackFrames entries must be strings.");
    }
    return entry;
  });
}

function optionalScreen(value: unknown): string {
  // The client omits screen entirely when unknown, but some builds send an
  // explicit null (e.g. no named route was active yet) — treat both the
  // same so a caller can never fail ingestion just for not knowing its screen.
  if (value === undefined || value === null) {
    return "unknown";
  }
  if (typeof value !== "string" || !SCREEN_PATTERN.test(value)) {
    throw new HttpsError("invalid-argument", "screen must match ^[A-Za-z0-9 /_-]{1,60}$.");
  }
  return value;
}

function requirePlatform(value: unknown): string {
  if (typeof value !== "string" || !PLATFORMS.has(value)) {
    throw new HttpsError("invalid-argument", "platform must be one of: ios, android.");
  }
  return value;
}

function optionalBoolean(value: unknown): boolean {
  if (value === undefined) {
    return false;
  }
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", "fatal must be a boolean.");
  }
  return value;
}

function validateOccurredAt(value: unknown): void {
  // Accepted for forward-compatibility only: the group document is always
  // stamped with server timestamps, so a client-supplied occurredAt can
  // never influence firstSeenAt/lastSeenAt.
  if (value === undefined) {
    return;
  }
  if (typeof value !== "number" && typeof value !== "string") {
    throw new HttpsError("invalid-argument", "occurredAt must be a number or string timestamp.");
  }
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function firebaseReportAppErrorPort(firestore: Firestore = getFirestore()): ReportAppErrorPort {
  const store = firestoreErrorGroupStore(firestore);
  return {
    now: () => new Date(),
    serverTimestamp: () => FieldValue.serverTimestamp(),
    recentReportCount: async (uid, since) => {
      // Scoped by uid via the document path (errorReportRateLimit/{uid}/events),
      // so this single inequality filter needs no composite index. This ledger
      // holds only a timestamp per report — no error content — and is not the
      // errorGroups collection the console reads; it exists solely to bound
      // report volume per caller.
      const snapshot = await firestore
        .collection("errorReportRateLimit")
        .doc(uid)
        .collection("events")
        .where("receivedAt", ">", since)
        .limit(RATE_LIMIT_MAX)
        .get();
      return snapshot.size;
    },
    recordReportEvent: async (uid, at) => {
      const eventsRef = firestore.collection("errorReportRateLimit").doc(uid).collection("events");
      await eventsRef.add({ receivedAt: Timestamp.fromDate(at) });

      // Opportunistic, best-effort pruning: every recorded event also sweeps
      // a small bounded batch of its own uid's stale (out-of-window) events,
      // so the ledger does not grow unbounded. Bounded batch size keeps this
      // sweep's latency predictable; any remainder is picked up by a later
      // call for the same uid.
      const staleCutoff = Timestamp.fromDate(new Date(at.getTime() - RATE_LIMIT_WINDOW_MS));
      const staleSnapshot = await eventsRef
        .where("receivedAt", "<=", staleCutoff)
        .limit(RATE_LIMIT_PRUNE_BATCH)
        .get();
      if (!staleSnapshot.empty) {
        const batch = firestore.batch();
        for (const doc of staleSnapshot.docs) {
          batch.delete(doc.ref);
        }
        await batch.commit();
      }
    },
    ingestErrorGroup: (input) => store.ingestErrorGroup(input),
  };
}
