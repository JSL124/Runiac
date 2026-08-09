// Seed the Firebase EMULATOR with a realistic Runiac demo dataset.
//
// Refuses to run against live Firebase: requires both FIRESTORE_EMULATOR_HOST
// and FIREBASE_AUTH_EMULATOR_HOST. Idempotent — every document uses a fixed ID
// and is written with merge, so re-running updates in place.
//
// Usage:
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
//   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//   node scripts/seed-emulator.mjs
//
// (Both hosts are also picked up from .env.local if present.)

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDir, "..");

loadEnvLocal();

if (
  !process.env.FIRESTORE_EMULATOR_HOST ||
  !process.env.FIREBASE_AUTH_EMULATOR_HOST
) {
  console.error(
    "Refusing to seed: FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST " +
      "must both be set. This script only targets the local emulator.",
  );
  process.exit(1);
}

function loadEnvLocal() {
  let contents;
  try {
    contents = readFileSync(resolve(projectRoot, ".env.local"), "utf8");
  } catch {
    return;
  }
  for (const rawLine of contents.split("\n")) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }
    const equals = line.indexOf("=");
    if (equals === -1) {
      continue;
    }
    const key = line.slice(0, equals).trim();
    let value = line.slice(equals + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) {
      process.env[key] = value;
    }
  }
}

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID?.trim() || "runiac-fypp";

if (getApps().length === 0) {
  initializeApp({ projectId: PROJECT_ID });
}

const auth = getAuth();
const db = getFirestore();

const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = Date.now();

function daysAgoIso(days) {
  return new Date(NOW - days * DAY_MS).toISOString();
}

function daysAgoTimestamp(days) {
  return Timestamp.fromMillis(NOW - days * DAY_MS);
}

async function upsertAuthUser(uid, email, password, displayName) {
  try {
    await auth.getUser(uid);
    await auth.updateUser(uid, { email, password, displayName, emailVerified: true });
  } catch (error) {
    if (error?.code === "auth/user-not-found") {
      await auth.createUser({ uid, email, password, displayName, emailVerified: true });
    } else {
      throw error;
    }
  }
}

// --- personas ---------------------------------------------------------------

const REGIONS = [
  "Tampines",
  "Jurong East",
  "Bishan",
  "Woodlands",
  "Bedok",
  "Clementi",
  "Ang Mo Kio",
  "Serangoon",
  "Punggol",
  "Queenstown",
];

const FITNESS_LEVELS = ["beginner", "intermediate", "advanced"];

const ADMIN = {
  uid: "seed-admin",
  email: "admin@runiac.app",
  password: "runiac-admin-2026",
  displayName: "Runiac Admin",
  nickname: "runiac-admin",
};

function runnerPersona(index) {
  const number = String(index + 1).padStart(2, "0");
  return {
    uid: `seed-runner-${number}`,
    email: `runner${number}@runiac.app`,
    password: "runiac-demo-2026",
    displayName: `Runner ${number}`,
    nickname: `runner-${number}`,
    subscriptionStatus: index % 3 === 0 ? "premium" : "basic",
    fitnessLevel: FITNESS_LEVELS[index % FITNESS_LEVELS.length],
    region: REGIONS[index % REGIONS.length],
  };
}

const RUNNERS = Array.from({ length: 10 }, (_, index) => runnerPersona(index));

async function seedUsers() {
  // Admin.
  await upsertAuthUser(ADMIN.uid, ADMIN.email, ADMIN.password, ADMIN.displayName);
  await db.collection("users").doc(ADMIN.uid).set(
    {
      userRole: "platformAdmin",
      subscriptionStatus: "premium",
      accountStatus: "active",
      createdAt: daysAgoTimestamp(120),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await db.collection("userProfiles").doc(ADMIN.uid).set(
    {
      displayName: ADMIN.displayName,
      fullName: "Runiac Administrator",
      nickname: ADMIN.nickname,
      fitnessLevel: "advanced",
      locationLabel: "Central, Singapore",
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  // Runners.
  for (let index = 0; index < RUNNERS.length; index += 1) {
    const runner = RUNNERS[index];
    await upsertAuthUser(runner.uid, runner.email, runner.password, runner.displayName);
    await db.collection("users").doc(runner.uid).set(
      {
        userRole: "runner",
        subscriptionStatus: runner.subscriptionStatus,
        accountStatus: index === 4 ? "suspended" : "active",
        totalXp: 500 + index * 275,
        level: 1 + (index % 8),
        streakCount: index % 6,
        createdAt: daysAgoTimestamp(90 - index * 5),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await db.collection("userProfiles").doc(runner.uid).set(
      {
        displayName: runner.displayName,
        fullName: `${runner.displayName} Tan`,
        nickname: runner.nickname,
        fitnessLevel: runner.fitnessLevel,
        locationLabel: `${runner.region}, Singapore`,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

async function seedReports() {
  const reports = [
    {
      id: "seed-report-01",
      targetType: "user",
      targetId: "seed-runner-05",
      reason: "harassment",
      description: "Abusive nickname reported by another runner.",
      resolutionStatus: "pending",
    },
    {
      id: "seed-report-02",
      targetType: "route",
      targetId: "route-east-coast",
      reason: "unsafe-route",
      description: "Route crosses an active construction zone.",
      resolutionStatus: "reviewing",
    },
    {
      id: "seed-report-03",
      targetType: "user",
      targetId: "seed-runner-03",
      reason: "medical-concern",
      description: "Runner requests a gentler pace ramp due to a knee injury.",
      resolutionStatus: "pending",
    },
    {
      id: "seed-report-04",
      targetType: "activity",
      targetId: "seed-activity-03",
      reason: "suspicious-distance",
      description: "Reported implausible distance for the recorded duration.",
      resolutionStatus: "resolved",
    },
    {
      id: "seed-report-05",
      targetType: "user",
      targetId: "seed-runner-08",
      reason: "impersonation",
      description: "Claims to be an official Runiac coach.",
      resolutionStatus: "dismissed",
    },
    {
      id: "seed-report-06",
      targetType: "route",
      targetId: "route-macritchie",
      reason: "inappropriate-content",
      description: "Route description contains offensive language.",
      // No resolutionStatus: exercises the "missing => pending" path.
    },
  ];

  for (let index = 0; index < reports.length; index += 1) {
    const report = reports[index];
    const doc = {
      reporterUid: RUNNERS[index % RUNNERS.length].uid,
      targetType: report.targetType,
      targetId: report.targetId,
      reason: report.reason,
      description: report.description,
      createdAt: daysAgoTimestamp(12 - index),
    };
    if (report.resolutionStatus) {
      doc.resolutionStatus = report.resolutionStatus;
    }
    await db.collection("reports").doc(report.id).set(doc, { merge: true });
  }
}

async function seedActivities() {
  for (let index = 0; index < 15; index += 1) {
    const runner = RUNNERS[index % RUNNERS.length];
    const id = `seed-activity-${String(index + 1).padStart(2, "0")}`;
    const summaryId = `seed-summary-${String(index + 1).padStart(2, "0")}`;
    const daysAgo = index * 2;
    const distanceMeters = 3000 + (index % 7) * 900;
    const durationSeconds = 1200 + (index % 7) * 360;
    const averagePace = Math.round((durationSeconds / distanceMeters) * 1000);
    const validationStatus = index % 6 === 0 ? "flagged" : "validated";

    await db.collection("activities").doc(id).set(
      {
        ownerUid: runner.uid,
        status: "validated",
        source: "seed",
        activityType: "run",
        startedAt: daysAgoIso(daysAgo),
        endedAt: daysAgoIso(daysAgo),
        durationSeconds,
        distanceMeters,
        averagePaceSecondsPerKm: averagePace,
        routePrivacy: "private",
        validationStatus,
        createdAt: daysAgoTimestamp(daysAgo),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await db.collection("runSummaries").doc(summaryId).set(
      {
        ownerUid: runner.uid,
        activityId: id,
        title: "Seeded Run",
        startedAt: daysAgoIso(daysAgo),
        endedAt: daysAgoIso(daysAgo),
        distanceMeters,
        durationSeconds,
        averagePaceSecondsPerKm: averagePace,
        validationStatus,
        createdAt: daysAgoTimestamp(daysAgo),
      },
      { merge: true },
    );
  }
}

async function seedLeaderboardSnapshot() {
  const now = new Date(NOW);
  const monthlyPeriod = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
  const entries = RUNNERS.map((runner, index) => ({
    uid: runner.uid,
    rank: index + 1,
    displayName: runner.displayName,
    score: 5000 - index * 320,
  }));

  await db
    .collection("leaderboardSnapshots")
    .doc(`monthly-${monthlyPeriod}`)
    .set(
      {
        monthlyPeriod,
        periodType: "monthly",
        generatedAt: FieldValue.serverTimestamp(),
        entries,
      },
      { merge: true },
    );
}

async function seedAuditLogs() {
  const logs = [
    {
      id: "seed-audit-01",
      action: "admin-action",
      targetType: "user",
      targetId: "seed-runner-05",
      detail: "Suspended account for policy review",
    },
    {
      id: "seed-audit-02",
      action: "subscription-change",
      targetType: "user",
      targetId: "seed-runner-01",
      detail: "Set subscriptionStatus to premium",
    },
    {
      id: "seed-audit-03",
      action: "report-resolution",
      targetType: "report",
      targetId: "seed-report-04",
      detail: "Set resolutionStatus to resolved",
    },
  ];

  for (let index = 0; index < logs.length; index += 1) {
    const log = logs[index];
    await db.collection("adminAuditLogs").doc(log.id).set(
      {
        actor: ADMIN.email,
        action: log.action,
        targetType: log.targetType,
        targetId: log.targetId,
        detail: log.detail,
        createdAt: daysAgoTimestamp(9 - index),
      },
      { merge: true },
    );
  }
}

async function seedAutomation() {
  // Automation config with auto-hide switched on and a low threshold so the
  // report-count automation is easy to demo against the seeded reports.
  await db.collection("config").doc("automation").set(
    {
      autoHide: { enabled: true, reportThreshold: 2 },
      staleReportEscalation: { enabled: true, pendingDays: 7 },
      scheduled: {
        leaderboardSnapshotRefresh: true,
        subscriptionExpirySweep: true,
        pushNotificationDispatch: true,
      },
      notifications: {
        notifyErrorGroups: true,
        minimumErrorSeverity: "critical",
        notifyNewReports: false,
      },
      version: 1,
    },
    { merge: true },
  );

  // A critical error group so the errorGroupWritten trigger / errors tab has
  // severity data to work with.
  await db.collection("errorGroups").doc("seed-error-group-critical").set(
    {
      errorType: "StateError",
      title: "Run tracking session lost GPS permission mid-run",
      severity: "critical",
      occurrenceCount: 14,
      firstSeenAt: daysAgoTimestamp(3),
      lastSeenAt: daysAgoTimestamp(0),
      status: "open",
    },
    { merge: true },
  );

  // One unread admin notification so the Overview "Attention needed" panel
  // renders a live item immediately after seeding.
  await db.collection("adminNotifications").doc("seed-notification-01").set(
    {
      kind: "error-group",
      severity: "critical",
      title: "Error group reached critical",
      detail:
        "StateError: Run tracking session lost GPS permission mid-run (fingerprint seed-error-group-critical)",
      href: "/admin/errors",
      createdAt: daysAgoTimestamp(0),
      status: "unread",
    },
    { merge: true },
  );
}

async function main() {
  console.log(`Seeding emulator (project: ${PROJECT_ID})...`);
  await seedUsers();
  console.log(`  users: 1 admin + ${RUNNERS.length} runners`);
  await seedReports();
  console.log("  reports: 6 across target types");
  await seedActivities();
  console.log("  activities + runSummaries: 15 over the last 30 days");
  await seedLeaderboardSnapshot();
  console.log("  leaderboardSnapshots: 1 monthly snapshot");
  await seedAuditLogs();
  console.log("  adminAuditLogs: 3 entries");
  await seedAutomation();
  console.log("  config/automation + errorGroups + adminNotifications: seeded");
  console.log("");
  console.log("Done. Admin login:");
  console.log(`  email:    ${ADMIN.email}`);
  console.log(`  password: ${ADMIN.password}`);
}

main().catch((error) => {
  console.error("Seed failed:");
  console.error(error?.message ?? error);
  process.exit(1);
});
