// Stale report escalation sweep (admin-automation-policy-control-plane,
// enforcement point 2). Runs once a day and writes ONE digest notification
// listing how many `reports` documents have been pending longer than
// `config/automation.staleReportEscalation.pendingDays` — never one document
// per stale report, and never any adjudication of the reports themselves.
// A human admin still makes every moderation decision; this sweep only ever
// escalates for their attention.
//
// Same wrapper shape as `subscriptionExpirySchedule.ts` /
// `subscriptionExpiryCore.ts`: a thin `onSchedule` registration delegating to
// a testable, dependency-injected, Date.now()-parameterised core.

import { getApps, initializeApp } from "firebase-admin/app";
import {
  FieldValue,
  Timestamp,
  getFirestore,
  type DocumentData,
  type DocumentReference,
  type Firestore,
} from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { loadAutomationConfig } from "../config/configLoader.js";
import { withScheduledErrorReporting } from "../errors/withErrorReporting.js";

const REPORTS_COLLECTION = "reports";
const ADMIN_NOTIFICATIONS_COLLECTION = "adminNotifications";
const ADMIN_AUDIT_LOGS_COLLECTION = "adminAuditLogs";

const DAY_MS = 24 * 60 * 60 * 1000;

// `resolutionStatus` is a backend-owned key (see firestore.rules
// backendOwnedKeys()) written only by the admin console's Exception Queue.
// The console's own contract (website/src/lib/firebase/types.ts:17-21) is
// `ReportResolutionStatus = "pending" | "reviewing" | "resolved" |
// "dismissed"`, and the console treats a missing field as "pending". Only
// "resolved" and "dismissed" are terminal — a report "reviewing" is still
// actively unresolved and must keep aging toward escalation, not be treated
// as handled. So staleness here is defined by exclusion: unresolved iff
// `resolutionStatus` is NOT "resolved" and NOT "dismissed". Missing,
// "pending", "reviewing", and any future/unrecognised value all count as
// unresolved — an unknown value failing toward alerting a human is the safe
// direction for an escalation sweep.
const TERMINAL_RESOLUTION_STATUSES: ReadonlySet<string> = new Set(["resolved", "dismissed"]);

export type StaleReportEscalationResult = {
  // Count of currently-pending reports older than `pendingDays`, computed on
  // every run regardless of whether a new digest notification was actually
  // written (a same-day re-run still reports the true count; only the
  // notification write itself is deduplicated).
  readonly escalated: number;
};

export async function escalateStaleReportsNow(
  firestore: Firestore,
  nowMs: number,
): Promise<StaleReportEscalationResult> {
  const config = await loadAutomationConfig(firestore);

  if (!config.staleReportEscalation.enabled) {
    console.log(
      "escalateStaleReports: skipped — staleReportEscalation.enabled is false in config/automation",
    );
    return { escalated: 0 };
  }

  const pendingDays = config.staleReportEscalation.pendingDays;
  const staleCutoffMs = nowMs - pendingDays * DAY_MS;

  // Full collection scan, deliberately unfiltered. `createdAt` is written by
  // multiple call sites (feed-post report, report-a-user, and any
  // hand-written legacy document) across Timestamp, number, and string
  // shapes, and — unlike `activities` or `feedPosts` — `reports` is
  // console-scale, not user-activity-scale. An in-memory scan avoids both a
  // composite index and the cross-type Firestore inequality-filter pitfall
  // documented in subscriptionExpiryCore.ts's EARLIEST_TIMESTAMP comment,
  // where a `where(">", ...)` bound only reliably selects one of several
  // value shapes present in one collection.
  const snapshot = await firestore.collection(REPORTS_COLLECTION).get();

  let staleCount = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (!isPendingReport(data)) {
      continue;
    }
    const createdAtMs = parseCreatedAtMs(data["createdAt"]);
    // Unparseable createdAt (absent, or a shape none of the three known
    // writers produce) is deliberately treated as NOT stale rather than
    // thrown on: a malformed single document must never abort the whole
    // sweep, and silently under-counting one bad document is far safer than
    // crashing the daily digest for every report behind it.
    if (createdAtMs === null) {
      continue;
    }
    // Strictly older than pendingDays — a report aged exactly pendingDays is
    // not yet stale per the "longer than" contract.
    if (createdAtMs < staleCutoffMs) {
      staleCount += 1;
    }
  }

  if (staleCount === 0) {
    return { escalated: 0 };
  }

  const dayKey = singaporeDayKey(nowMs);
  const notificationRef = firestore
    .collection(ADMIN_NOTIFICATIONS_COLLECTION)
    .doc(`staleReports_${dayKey}`);

  // One digest per calendar day, replay-safe: a retried or re-run sweep on
  // the same Singapore day finds the doc already created and skips both the
  // notification and the audit entry below. Known narrow window: if the
  // instance dies after this create() but before the audit set() below, the
  // replay skips the audit entry too, leaving that day's digest unaudited.
  // Accepted: the notification itself is the user-facing record, and the
  // alternative (audit-first) would risk audit rows for digests never written.
  const created = await createIfAbsent(notificationRef, {
    kind: "stale-reports",
    severity: "medium",
    title: "Reports pending review",
    detail: `${staleCount} report(s) have been pending longer than ${pendingDays} day(s).`,
    href: "/admin/exceptions",
    createdAt: FieldValue.serverTimestamp(),
    status: "unread",
  });

  if (created) {
    const nowTimestamp = Timestamp.fromMillis(nowMs);
    await firestore.collection(ADMIN_AUDIT_LOGS_COLLECTION).doc().set({
      actor: "system",
      action: "moderation.stale-reports.escalate",
      targetType: "adminNotification",
      targetId: notificationRef.id,
      detail: `Escalated ${staleCount} report(s) pending longer than ${pendingDays} day(s) to admin review.`,
      changedFields: ["adminNotifications"],
      before: null,
      after: { staleCount, pendingDays },
      createdAt: nowTimestamp,
    });
  }

  return { escalated: staleCount };
}

function isPendingReport(data: DocumentData): boolean {
  const status = data["resolutionStatus"];
  if (status === undefined || status === null) {
    return true;
  }
  return typeof status !== "string" || !TERMINAL_RESOLUTION_STATUSES.has(status);
}

function parseCreatedAtMs(value: unknown): number | null {
  // Firestore Timestamp instances expose toMillis(); duck-typed rather than
  // an `instanceof Timestamp` check so this also accepts the emulator's own
  // Timestamp construction path.
  if (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { toMillis?: unknown }).toMillis === "function"
  ) {
    return (value as { toMillis: () => number }).toMillis();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

// Fixed +8h offset from epoch millis, deliberately never routed through
// Date.prototype's server-locale-dependent formatting (toLocaleDateString,
// Intl without an explicit timeZone, etc.). Singapore has no DST, so a
// constant offset is exact for every instant, not an approximation — the
// same technique `monthlyLeaderboardPeriod.ts`'s currentSingaporeMonthKey()
// already uses for its own Singapore-anchored key.
function singaporeDayKey(nowMs: number): string {
  return new Date(nowMs + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

async function createIfAbsent(
  ref: DocumentReference,
  data: Record<string, unknown>,
): Promise<boolean> {
  try {
    await ref.create(data);
    return true;
  } catch (error) {
    if (isAlreadyExistsError(error)) {
      return false;
    }
    throw error;
  }
}

// Firestore's Admin SDK surfaces a rejected `.create()` against an existing
// document as a GoogleError carrying the gRPC ALREADY_EXISTS status (numeric
// code 6). The string form is checked too, defensively, in case a future SDK
// version or the emulator ever normalises it differently.
function isAlreadyExistsError(error: unknown): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const code = (error as { code?: unknown }).code;
  return code === 6 || code === "already-exists";
}

if (getApps().length === 0) {
  initializeApp();
}

export const escalateStaleReports = onSchedule(
  {
    schedule: "every day 09:00",
    timeZone: "Asia/Singapore",
    region: "asia-southeast1",
  },
  withScheduledErrorReporting("escalateStaleReports", async () => {
    await escalateStaleReportsNow(getFirestore(), Date.now());
  }),
);
