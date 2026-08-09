// Shared test helpers for integration tests that run against the Firestore
// emulator. Expanded in WP4 with typed seed helpers so overview.int.test.ts
// can write documents matching the exact shapes src/lib/firebase/firestore.ts
// reads, without duplicating field-name knowledge in the test file itself.

import { Timestamp, type Firestore } from "firebase-admin/firestore";

import { getAdminDb } from "@/lib/firebase/admin";

// The collection name literals below mirror the (unexported, module-private)
// constants declared at the top of src/lib/firebase/firestore.ts. They are
// copied here rather than imported because that file does not export them;
// keep these in sync with that file if a collection is ever renamed.
const USERS = "users";
const ACTIVITIES = "activities";
const ERROR_GROUPS = "errorGroups";
const REPORTS = "reports";
const LEADERBOARD_PERIODS = "leaderboardPeriods";
const LEADERBOARD_AGGREGATION_LOCKS = "leaderboardAggregationLocks";
const ADMIN_NOTIFICATIONS = "adminNotifications";
const CONFIG = "config";
const ADMIN_AUDIT_LOGS = "adminAuditLogs";
const PROJECT_DOCUMENTS = "projectDocuments";

const CURRENT_PERIOD_DOC_ID = "monthly_current";

// Collections cleared by resetFirestore(). Scoped to the overview surfaces
// integration tests exercise today; extend this list as WP4 grows.
const OVERVIEW_COLLECTIONS = [
  USERS,
  ACTIVITIES,
  ERROR_GROUPS,
  REPORTS,
  LEADERBOARD_PERIODS,
  LEADERBOARD_AGGREGATION_LOCKS,
  ADMIN_NOTIFICATIONS,
  CONFIG,
  ADMIN_AUDIT_LOGS,
  PROJECT_DOCUMENTS,
];

// True when a Firestore emulator host is configured for this process. Tests
// that require the emulator should skip themselves when this is false rather
// than attempting to hit a live project.
export function emulatorAvailable(): boolean {
  return Boolean(process.env.FIRESTORE_EMULATOR_HOST);
}

// Returns the real Admin SDK Firestore accessor used by the admin console
// itself, so integration tests read/write through the same client the app
// code does.
export function getTestDb(): Firestore {
  return getAdminDb();
}

async function deleteCollection(db: Firestore, collectionName: string): Promise<void> {
  const snapshot = await db.collection(collectionName).get();

  if (snapshot.empty) {
    return;
  }

  const batch = db.batch();
  for (const doc of snapshot.docs) {
    batch.delete(doc.ref);
  }
  await batch.commit();
}

// Clears every document in the overview collections so each integration test
// starts from an empty emulator state. Intended to run in a beforeEach/
// afterEach hook, never against a live project.
export async function resetFirestore(): Promise<void> {
  const db = getTestDb();
  await Promise.all(
    OVERVIEW_COLLECTIONS.map((collectionName) => deleteCollection(db, collectionName)),
  );
}

// --- seed helpers ------------------------------------------------------------
//
// Each helper below writes a document matching the exact field names/types
// the real readers in src/lib/firebase/firestore.ts expect (verified against
// that file and src/lib/firebase/types.ts), so integration tests exercise the
// live read path end-to-end rather than a shape that only looks plausible.
// All timestamps are ISO strings, matching how the backend actually stores
// them for these collections (never a Firestore Timestamp on write here).

// activities/{id} — see ActivitySummaryRow / listActivitySummaries() /
// listActivityOwnerUidsInWindow() in firestore.ts.
export type SeedActivityInput = {
  id?: string;
  ownerUid: string;
  startedAt: string;
  distanceMeters?: number;
  durationSeconds?: number;
  validationStatus?: string;
  createdAt?: string;
};

export async function seedActivity(
  db: Firestore,
  input: SeedActivityInput,
): Promise<string> {
  const ref = input.id
    ? db.collection(ACTIVITIES).doc(input.id)
    : db.collection(ACTIVITIES).doc();

  await ref.set({
    ownerUid: input.ownerUid,
    startedAt: input.startedAt,
    distanceMeters: input.distanceMeters ?? 5000,
    durationSeconds: input.durationSeconds ?? 1800,
    validationStatus: input.validationStatus ?? "validated",
    createdAt: input.createdAt ?? input.startedAt,
  });

  return ref.id;
}

// errorGroups/{fingerprint} — see ErrorGroupRow / listErrorGroups() in
// firestore.ts. Doc fields are `os` (not `osVersion`) and
// `affectedUserCount` (not `affectedUsers`).
export type SeedErrorGroupInput = {
  id?: string;
  title?: string;
  source?: "mobile" | "functions";
  severity?: string;
  status?: string;
  lastSeenAt: string;
  firstSeenAt?: string;
  occurrences?: number;
  affectedUserCount?: number;
  screen?: string;
  appVersion?: string;
  os?: string;
  platform?: string;
  sanitized?: boolean;
  note?: string | null;
};

export async function seedErrorGroup(
  db: Firestore,
  input: SeedErrorGroupInput,
): Promise<string> {
  const ref = input.id
    ? db.collection(ERROR_GROUPS).doc(input.id)
    : db.collection(ERROR_GROUPS).doc();

  await ref.set({
    title: input.title ?? "Test error",
    source: input.source ?? "mobile",
    severity: input.severity ?? "low",
    status: input.status ?? "new",
    lastSeenAt: input.lastSeenAt,
    firstSeenAt: input.firstSeenAt ?? input.lastSeenAt,
    occurrences: input.occurrences ?? 1,
    affectedUserCount: input.affectedUserCount ?? 1,
    screen: input.screen ?? "home",
    appVersion: input.appVersion ?? "1.0.0",
    os: input.os ?? "iOS 18",
    platform: input.platform ?? "ios",
    sanitized: input.sanitized ?? true,
    note: input.note ?? null,
  });

  return ref.id;
}

// leaderboardPeriods/monthly_current — see LeaderboardCurrentPeriodRow /
// getLeaderboardCurrentPeriod() in firestore.ts. `generatedAt` must be set
// for getLiveAggregationJob() to treat this period as the aggregation job's
// source of truth (rather than falling back to leaderboardSnapshots).
export type SeedCurrentPeriodInput = {
  periodKey: string;
  periodType?: string;
  periodLabel?: string;
  timezone?: string;
  refreshesAt?: string;
  buildId?: string;
  generatedAt?: string;
  aggregationStatus?: string;
  updatedAt?: string;
};

export async function seedCurrentPeriod(
  db: Firestore,
  input: SeedCurrentPeriodInput,
): Promise<void> {
  await db
    .collection(LEADERBOARD_PERIODS)
    .doc(CURRENT_PERIOD_DOC_ID)
    .set({
      periodType: input.periodType ?? "monthly",
      periodKey: input.periodKey,
      periodLabel: input.periodLabel ?? input.periodKey,
      timezone: input.timezone ?? "Asia/Singapore",
      refreshesAt: input.refreshesAt ?? new Date().toISOString(),
      buildId: input.buildId ?? "test-build",
      generatedAt: input.generatedAt ?? new Date().toISOString(),
      aggregationStatus: input.aggregationStatus ?? "completed",
      updatedAt: input.updatedAt ?? new Date().toISOString(),
    });
}

// leaderboardAggregationLocks/monthly_{periodKey} — see
// LeaderboardAggregationLockRow / getLeaderboardAggregationLock() in
// firestore.ts.
export type SeedAggregationLockInput = {
  periodKey: string;
  status: "running" | "completed" | "failed" | string;
  buildId?: string;
  startedAt?: string;
  completedAt?: string | null;
  failedAt?: string | null;
  leaseExpiresAt?: string | null;
  updatedAt?: string;
};

export async function seedAggregationLock(
  db: Firestore,
  input: SeedAggregationLockInput,
): Promise<void> {
  await db
    .collection(LEADERBOARD_AGGREGATION_LOCKS)
    .doc(`monthly_${input.periodKey}`)
    .set({
      buildId: input.buildId ?? "test-build",
      status: input.status,
      startedAt: input.startedAt ?? new Date().toISOString(),
      completedAt:
        input.completedAt ??
        (input.status === "completed" ? new Date().toISOString() : null),
      failedAt:
        input.failedAt ??
        (input.status === "failed" ? new Date().toISOString() : null),
      leaseExpiresAt: input.leaseExpiresAt ?? null,
      updatedAt: input.updatedAt ?? new Date().toISOString(),
    });
}

// reports/{id} — see ReportRow / listReports() in firestore.ts.
export type SeedReportInput = {
  id?: string;
  reporterUid?: string;
  targetType?: string;
  targetId?: string;
  reason?: string;
  description?: string;
  resolutionStatus?: string;
  resolutionNote?: string | null;
  createdAt?: string;
  source?: string | null;
};

export async function seedReport(
  db: Firestore,
  input: SeedReportInput = {},
): Promise<string> {
  const ref = input.id
    ? db.collection(REPORTS).doc(input.id)
    : db.collection(REPORTS).doc();

  await ref.set({
    reporterUid: input.reporterUid ?? "reporter-uid",
    targetType: input.targetType ?? "user",
    targetId: input.targetId ?? "target-id",
    reason: input.reason ?? "Test report",
    description: input.description ?? "",
    resolutionStatus: input.resolutionStatus ?? "pending",
    resolutionNote: input.resolutionNote ?? null,
    createdAt: input.createdAt ?? new Date().toISOString(),
    source: input.source ?? null,
  });

  return ref.id;
}

// users/{uid} — see AdminUserRow / listUsers() and countUsers() /
// countUsersBySubscription() in firestore.ts. Only the admin-owned fields
// that live on `users/{uid}` (not `userProfiles/{uid}`) are seeded here.
export type SeedUserInput = {
  uid?: string;
  userRole?: string;
  subscriptionStatus?: string;
  subscriptionExpiresAt?: string | null;
  accountStatus?: string;
  createdAt?: string;
};

export async function seedUser(
  db: Firestore,
  input: SeedUserInput = {},
): Promise<string> {
  const uid = input.uid ?? db.collection(USERS).doc().id;

  await db
    .collection(USERS)
    .doc(uid)
    .set({
      userRole: input.userRole ?? "runner",
      subscriptionStatus: input.subscriptionStatus ?? "basic",
      subscriptionExpiresAt: input.subscriptionExpiresAt ?? null,
      accountStatus: input.accountStatus ?? "active",
      createdAt: input.createdAt ?? new Date().toISOString(),
    });

  return uid;
}

// config/{name} — see getConfigDoc() in firestore.ts. Merge-write so a test
// can seed only the fields it cares about (e.g. version/updatedBy) without
// asserting on the full document shape.
export async function seedConfigDoc(
  db: Firestore,
  name: string,
  data: Record<string, unknown>,
): Promise<void> {
  await db.collection(CONFIG).doc(name).set(data, { merge: true });
}

// projectDocuments/{id} — see ProjectDocumentRecord / mapProjectDocumentRow()
// / listProjectDocuments() / getProjectDocumentById() in firestore.ts.
// `createdAt` defaults to a real Firestore Timestamp (rather than an ISO
// string like the other seed helpers above) because the production write
// path (createProjectDocument()) stores FieldValue.serverTimestamp() there;
// defaulting to a Timestamp lets integration tests exercise the same toIso()
// Timestamp-to-string normalization the real read path relies on.
export type SeedProjectDocumentInput = {
  id?: string;
  title?: string;
  category?: string;
  documentDate: string;
  fileName?: string;
  fileSize?: number;
  storagePath?: string;
  createdAt?: Timestamp | Date | string;
  createdBy?: string;
};

export async function seedProjectDocument(
  db: Firestore,
  input: SeedProjectDocumentInput,
): Promise<string> {
  const ref = input.id
    ? db.collection(PROJECT_DOCUMENTS).doc(input.id)
    : db.collection(PROJECT_DOCUMENTS).doc();

  await ref.set({
    title: input.title ?? "Test document",
    category: input.category ?? "proposal",
    documentDate: input.documentDate,
    fileName: input.fileName ?? "doc.pdf",
    fileSize: input.fileSize ?? 1024,
    storagePath: input.storagePath ?? `project-documents/${ref.id}/doc.pdf`,
    createdAt: input.createdAt ?? Timestamp.now(),
    createdBy: input.createdBy ?? "admin@example.com",
  });

  return ref.id;
}

// adminNotifications/{id} — see AdminNotificationRow /
// listAdminNotifications() in firestore.ts.
export type SeedAdminNotificationInput = {
  id?: string;
  kind?: string;
  severity?: string;
  title?: string;
  detail?: string;
  href?: string;
  createdAt?: string;
  status?: string;
};

export async function seedAdminNotification(
  db: Firestore,
  input: SeedAdminNotificationInput = {},
): Promise<string> {
  const ref = input.id
    ? db.collection(ADMIN_NOTIFICATIONS).doc(input.id)
    : db.collection(ADMIN_NOTIFICATIONS).doc();

  await ref.set({
    kind: input.kind ?? "test",
    severity: input.severity ?? "low",
    title: input.title ?? "Test notification",
    detail: input.detail ?? "",
    href: input.href ?? "/admin",
    createdAt: input.createdAt ?? new Date().toISOString(),
    status: input.status ?? "unread",
  });

  return ref.id;
}
