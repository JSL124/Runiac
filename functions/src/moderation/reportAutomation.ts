import { getApps, initializeApp } from "firebase-admin/app";
import {
  Timestamp,
  getFirestore,
  type DocumentData,
  type Firestore,
} from "firebase-admin/firestore";
import { onDocumentCreated, type FirestoreEvent, type QueryDocumentSnapshot } from "firebase-functions/v2/firestore";
import { loadAutomationConfig } from "../config/configLoader.js";
import { withTriggerErrorReporting } from "../errors/withErrorReporting.js";

// Automates two report-driven admin-console workflows off the creation of a
// `reports/{reportId}` document, gated by `config/automation`
// (`loadAutomationConfig`):
//
// 1. Notifications: when `notifications.notifyNewReports` is on, writes an
//    `adminNotifications/report_<reportId>` doc so a new report surfaces on
//    the admin console without a poll. The doc id is deterministic (the
//    report id itself), so a redelivered trigger event races into the same
//    doc rather than creating a duplicate notification.
//
// 2. Auto-hide: when `autoHide.enabled` is on and the report targets a
//    `feedPost`, counts all `reports` docs for that same
//    (targetType, targetId) pair — the `reports (targetType ASC, targetId
//    ASC)` composite index in firestore.indexes.json backs this count — and,
//    once the count reaches `autoHide.reportThreshold`, creates a
//    `moderationCommands/auto_removeFeedPost_<postId>` command doc with a
//    deterministic id derived from the post id. That determinism is what
//    keeps this handler race-safe both under fan-in (several reports
//    crossing the threshold "simultaneously") and under replay: `.create()`
//    on an existing doc rejects with ALREADY_EXISTS (gRPC code 6), which
//    this module treats as "someone already requested this", not an error.
//    `requestedBy: "system:report-auto-hide"` marks the command as
//    system-originated the same way `requestedBy` is used for admin-issued
//    commands, and `status: "pending"` is safe to leave as-is even under a
//    duplicate create attempt: `moderationCommandCreated`
//    (`moderation/moderationCommand.ts`) only reads `kind`/`postId` off the
//    command doc and only treats "completed"/"failed" as terminal, so a
//    second create attempt racing behind the first never causes a second
//    removal — it just fails to create and is swallowed here.
//
// The audit-log entry (`adminAuditLogs`, actor "system") for the auto-hide
// request is written ONLY when this call's `.create()` actually succeeded
// (not on ALREADY_EXISTS), so a replayed or racing event never double-logs a
// request that only happened once. The entry shape mirrors the system
// audit entries `subscriptionExpiryCore.ts` writes for its own system-actor
// changes (actor/action/targetType/targetId/detail/changedFields/before/
// after/createdAt), with `before: null` because the command doc did not
// exist before this request.
//
// Actual post removal is out of scope here: it is performed by the existing
// `moderationCommandCreated` trigger once it consumes the command doc this
// module creates.
const REPORTS_COLLECTION = "reports";
const ADMIN_NOTIFICATIONS_COLLECTION = "adminNotifications";
const MODERATION_COMMANDS_COLLECTION = "moderationCommands";
const ADMIN_AUDIT_LOGS_COLLECTION = "adminAuditLogs";

export type ReportAutomationHandlers = {
  readonly onReportCreated: (
    reportId: string,
    data: DocumentData,
  ) => Promise<void>;
};

export function createReportAutomationHandlers(dependencies: {
  readonly firestore: Firestore;
}): ReportAutomationHandlers {
  return {
    onReportCreated: async (reportId, data) => {
      const firestore = dependencies.firestore;
      const config = await loadAutomationConfig(firestore);
      const nowTimestamp = Timestamp.now();

      const targetType = readString(data["targetType"]);
      const targetId = readString(data["targetId"]);

      if (config.notifications.notifyNewReports) {
        await notifyNewReport(firestore, reportId, targetType, targetId, nowTimestamp);
      }

      if (!config.autoHide.enabled) {
        return;
      }

      // Auto-hide only ever targets feed posts; every other targetType
      // (e.g. "user") is left for manual admin review.
      if (targetType !== "feedPost" || targetId === null || !isIdentifier(targetId)) {
        return;
      }

      await maybeAutoHideFeedPost(
        firestore,
        targetId,
        config.autoHide.reportThreshold,
        nowTimestamp,
      );
    },
  };
}

export function createReportAutomationTriggers(dependencies: {
  readonly firestore: Firestore;
}) {
  const handlers = createReportAutomationHandlers(dependencies);
  return {
    reportCreated: onDocumentCreated(
      {
        document: `${REPORTS_COLLECTION}/{reportId}`,
        region: "asia-southeast1",
      },
      withTriggerErrorReporting(
        "reportCreated",
        async (
          event: FirestoreEvent<QueryDocumentSnapshot | undefined, { reportId: string }>,
        ) => {
          const data = event.data?.data();
          if (data === undefined) {
            return;
          }
          await handlers.onReportCreated(event.params.reportId, data);
        },
      ),
    ),
  };
}

if (getApps().length === 0) {
  initializeApp();
}

const productionReportAutomationTriggers = createReportAutomationTriggers({
  firestore: getFirestore(),
});

export const reportCreated = productionReportAutomationTriggers.reportCreated;

async function notifyNewReport(
  firestore: Firestore,
  reportId: string,
  targetType: string | null,
  targetId: string | null,
  nowTimestamp: Timestamp,
): Promise<void> {
  const ref = firestore.collection(ADMIN_NOTIFICATIONS_COLLECTION).doc(`report_${reportId}`);

  try {
    await ref.create({
      kind: "new-report",
      severity: "medium",
      title: "New report submitted",
      detail: `A new report was submitted for ${targetType ?? "unknown"} ${targetId ?? "unknown"} (report ${reportId}).`,
      href: "/admin/exceptions",
      createdAt: nowTimestamp,
      status: "unread",
    });
  } catch (error) {
    if (!isAlreadyExistsError(error)) {
      throw error;
    }
    // Already delivered by a previous run of this same event: idempotent.
  }
}

async function maybeAutoHideFeedPost(
  firestore: Firestore,
  postId: string,
  reportThreshold: number,
  nowTimestamp: Timestamp,
): Promise<void> {
  const countSnapshot = await firestore
    .collection(REPORTS_COLLECTION)
    .where("targetType", "==", "feedPost")
    .where("targetId", "==", postId)
    .count()
    .get();
  const reportCount = countSnapshot.data().count;

  if (reportCount < reportThreshold) {
    return;
  }

  const commandId = `auto_removeFeedPost_${postId}`;
  const commandRef = firestore.collection(MODERATION_COMMANDS_COLLECTION).doc(commandId);

  let created = false;
  try {
    await commandRef.create({
      kind: "removeFeedPost",
      postId,
      requestedBy: "system:report-auto-hide",
      requestedAt: nowTimestamp,
      status: "pending",
      reportCount,
    });
    created = true;
  } catch (error) {
    if (!isAlreadyExistsError(error)) {
      throw error;
    }
    // A prior report crossing the same threshold (or a replay of this same
    // event) already requested this removal; the audit entry below was
    // already written the first time, so skip both the command and the log.
    // Known narrow window: if the instance dies between the successful
    // create() above and the audit set() below, the replay lands here and
    // the command stays unaudited. Accepted: the command document itself
    // (requestedBy: "system:report-auto-hide") remains the durable record.
  }

  if (!created) {
    return;
  }

  await firestore.collection(ADMIN_AUDIT_LOGS_COLLECTION).doc().set({
    actor: "system",
    action: "moderation.report-auto-hide.request",
    targetType: "moderation-command",
    targetId: commandId,
    detail: `Auto-hide requested for feed post ${postId} after ${reportCount} reports reached the threshold of ${reportThreshold}.`,
    changedFields: ["status", "postId", "reportCount"],
    before: null,
    after: { status: "pending", postId, reportCount },
    createdAt: nowTimestamp,
  });
}

function isIdentifier(value: string | undefined): value is string {
  return value !== undefined && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function readString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function isAlreadyExistsError(error: unknown): boolean {
  // The Firestore Admin SDK (google-gax) surfaces a failed `.create()` on an
  // existing document as an error whose `.code` is the numeric gRPC status
  // ALREADY_EXISTS (6) — see
  // https://github.com/googleapis/nodejs-firestore and grpc's status.proto.
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: unknown }).code === 6
  );
}
