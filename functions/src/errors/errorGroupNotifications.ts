// Error group severity-crossing notifications (admin-automation-policy-
// control-plane, enforcement point 3).
//
// RECURSION-HAZARD EXCEPTION — read before touching this file's error
// handling: every other trigger/scheduled/callable handler in this codebase
// is wrapped in `withTriggerErrorReporting` / `withScheduledErrorReporting` /
// `withCallableErrorReporting` (see errors/withErrorReporting.ts), which
// reports an unexpected fault back into `errorGroups`. This trigger listens
// on writes to `errorGroups/{fingerprint}` itself. Wrapping it in that same
// helper would mean a fault in THIS handler gets reported by writing to
// `errorGroups`, which re-fires this very trigger, which can fault again,
// writing to `errorGroups` again — a self-sustaining write loop with no
// external actor involved. So this handler is deliberately, permanently NOT
// wrapped in `withTriggerErrorReporting`. Instead the whole handler body is
// wrapped in its own try/catch that logs with `console.error` and NEVER
// rethrows — Cloud Logging still sees the failure, but nothing here can ever
// write to the collection it is watching.
//
// The same invariant forces the config load below to run with
// `reportFallback: false`: a reporting `loadAutomationConfig` would call
// `reportConfigFallback` → `reportBackendError` → `ingestErrorGroup` on a
// degraded `config/automation` document, and that WRITES an `errorGroups`
// document — re-firing this trigger on every organic error write for as long
// as the config stays degraded. The reporting path stays on for every other
// caller; only this trigger loads silently (console.warn still fires).
//
// Behaviour: notifies only when a group's severity CROSSES the configured
// floor (`config/automation.notifications.minimumErrorSeverity`) on this
// write — i.e. it was below the floor before this write and is at/above it
// after. Severity is recomputed on every ingest (see sanitize.ts
// deriveSeverity()), so without this crossing check a group sitting at or
// above the floor would renotify on every single occurrence. One
// `adminNotifications/error_<fingerprint>` document per group, written once
// via a `.create()` that swallows ALREADY_EXISTS, is the de-duplication.

import { getApps, initializeApp } from "firebase-admin/app";
import {
  FieldValue,
  getFirestore,
  type DocumentData,
  type DocumentReference,
  type DocumentSnapshot,
  type Firestore,
} from "firebase-admin/firestore";
import {
  onDocumentWritten,
  type Change,
  type FirestoreEvent,
} from "firebase-functions/v2/firestore";
import { loadAutomationConfig } from "../config/configLoader.js";
import type { Severity } from "./sanitize.js";

const ERROR_GROUPS_COLLECTION = "errorGroups";
const ADMIN_NOTIFICATIONS_COLLECTION = "adminNotifications";

// Ranked low → critical. 0 is reserved for "no severity" (group did not
// exist before this write, or its prior document was malformed), which is
// always below every real severity floor.
const SEVERITY_RANK: Readonly<Record<Severity, number>> = {
  low: 1,
  medium: 2,
  high: 3,
  critical: 4,
};

export type ErrorGroupNotificationHandlers = {
  readonly onWritten: (
    fingerprint: string,
    before: DocumentSnapshot | undefined,
    after: DocumentSnapshot | undefined,
  ) => Promise<void>;
};

export function createErrorGroupNotificationHandlers(dependencies: {
  readonly firestore: Firestore;
}): ErrorGroupNotificationHandlers {
  return {
    onWritten: async (fingerprint, before, after) => {
      try {
        // Deletes carry no `after` snapshot (or an `after` that no longer
        // exists): there is nothing to escalate, and re-notifying on a
        // group's deletion would be actively wrong.
        if (after === undefined || !after.exists) {
          return;
        }

        // reportFallback: false — see the recursion-hazard header comment.
        const config = await loadAutomationConfig(dependencies.firestore, {
          reportFallback: false,
        });
        if (!config.notifications.notifyErrorGroups) {
          return;
        }

        const minRank = SEVERITY_RANK[config.notifications.minimumErrorSeverity];
        const beforeSeverity =
          before !== undefined && before.exists ? readSeverity(before.data()) : undefined;
        const afterSeverity = readSeverity(after.data());

        const beforeRank = beforeSeverity === undefined ? 0 : SEVERITY_RANK[beforeSeverity];
        const afterRank = afterSeverity === undefined ? 0 : SEVERITY_RANK[afterSeverity];

        // Crossing only: strictly below the floor before, at-or-above it
        // after. A group already at/above the floor writing again (more
        // occurrences, same or higher severity) does NOT renotify.
        if (!(beforeRank < minRank && afterRank >= minRank)) {
          return;
        }

        const afterData = after.data() ?? {};
        const severity = afterSeverity ?? "low";
        const errorType = readString(afterData, "errorType");
        const title = readString(afterData, "title");
        const detailSource = [errorType, title].filter((part) => part.length > 0).join(": ");

        const ref = dependencies.firestore
          .collection(ADMIN_NOTIFICATIONS_COLLECTION)
          .doc(`error_${fingerprint}`);

        await createIfAbsent(ref, {
          kind: "error-group",
          severity,
          title: `Error group reached ${severity}`,
          detail:
            detailSource.length > 0
              ? `${detailSource} (fingerprint ${fingerprint})`
              : `Error group ${fingerprint} reached ${severity} severity.`,
          href: "/admin/errors",
          createdAt: FieldValue.serverTimestamp(),
          status: "unread",
        });
      } catch (error) {
        // See file header: this handler must NEVER throw and must NEVER be
        // wrapped in withTriggerErrorReporting.
        console.error("[errorGroupNotifications] onWritten failed", error);
      }
    },
  };
}

function readSeverity(data: DocumentData | undefined): Severity | undefined {
  const value = data?.["severity"];
  return value === "low" || value === "medium" || value === "high" || value === "critical"
    ? value
    : undefined;
}

function readString(data: DocumentData, key: string): string {
  const value = data[key];
  return typeof value === "string" ? value : "";
}

async function createIfAbsent(
  ref: DocumentReference,
  data: Record<string, unknown>,
): Promise<void> {
  try {
    await ref.create(data);
  } catch (error) {
    if (!isAlreadyExistsError(error)) {
      throw error;
    }
    // ALREADY_EXISTS: this fingerprint already has a notification on file
    // from an earlier crossing (or a retried delivery of this same write).
    // Swallowed by design — one notification per group, ever.
  }
}

// Same gRPC ALREADY_EXISTS (code 6) check used by staleReportSweep.ts.
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

const productionErrorGroupNotificationHandlers = createErrorGroupNotificationHandlers({
  firestore: getFirestore(),
});

export const errorGroupWritten = onDocumentWritten(
  {
    document: `${ERROR_GROUPS_COLLECTION}/{fingerprint}`,
    region: "asia-southeast1",
  },
  async (
    event: FirestoreEvent<Change<DocumentSnapshot> | undefined, { fingerprint: string }>,
  ) => {
    // Outer try/catch is defence in depth only: onWritten() above already
    // guarantees it never throws. See the file-header recursion-hazard
    // comment for why NOTHING in this file ever calls
    // withTriggerErrorReporting.
    try {
      const change = event.data;
      await productionErrorGroupNotificationHandlers.onWritten(
        event.params.fingerprint,
        change?.before,
        change?.after,
      );
    } catch (error) {
      console.error("[errorGroupNotifications] errorGroupWritten failed", error);
    }
  },
);
