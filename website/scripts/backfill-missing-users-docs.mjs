// Create missing top-level `users/{uid}` governance docs for existing accounts
// that only have a `userProfiles/{uid}` doc (so they show up in the admin
// console's Users & Roles list, which reads `users` for userRole /
// subscriptionStatus / accountStatus / createdAt).
//
// Defaults applied to every missing doc: userRole="runner",
// subscriptionStatus="basic", accountStatus="active". createdAt is
// approximated from the userProfiles doc's `updatedAt` (falls back to now
// if absent). Existing `users/{uid}` docs are left untouched — this only
// creates docs that don't exist yet.
//
// Every write is recorded in `adminAuditLogs` with action
// "user.backfill.create-users-doc" and a before/after snapshot, matching the
// audit pattern used by src/lib/firebase/firestore.ts.
//
// Usage:
//   node scripts/backfill-missing-users-docs.mjs --actor <admin-email> [--dry-run]
//
// Works against the emulator (when FIRESTORE_EMULATOR_HOST +
// FIREBASE_AUTH_EMULATOR_HOST are set) or live Firebase (service account via
// FIREBASE_SERVICE_ACCOUNT_KEY or GOOGLE_APPLICATION_CREDENTIALS).
//
// Reads .env.local from the project root with a minimal parser (no dotenv).

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { cert, getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDir, "..");

const USERS = "users";
const USER_PROFILES = "userProfiles";
const ADMIN_AUDIT_LOGS = "adminAuditLogs";

const DEFAULT_USER_ROLE = "runner";
const DEFAULT_SUBSCRIPTION_STATUS = "basic";
const DEFAULT_ACCOUNT_STATUS = "active";

loadEnvLocal();

function loadEnvLocal() {
  const envPath = resolve(projectRoot, ".env.local");
  let contents;
  try {
    contents = readFileSync(envPath, "utf8");
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

function parseArgs(argv) {
  const args = { actor: null, dryRun: false };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--dry-run") {
      args.dryRun = true;
    } else if (token === "--actor") {
      args.actor = argv[index + 1] ?? null;
      index += 1;
    }
  }
  return args;
}

function isEmulatorMode() {
  return Boolean(
    process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST,
  );
}

function getProjectId() {
  return process.env.FIREBASE_PROJECT_ID?.trim() || "runiac-fypp";
}

function initApp() {
  if (getApps().length > 0) {
    return getApps()[0];
  }

  const projectId = getProjectId();

  if (isEmulatorMode()) {
    return initializeApp({ projectId });
  }

  const inlineJson = process.env.FIREBASE_SERVICE_ACCOUNT_KEY?.trim();
  if (inlineJson) {
    const parsed = JSON.parse(inlineJson);
    return initializeApp({
      projectId: parsed.project_id ?? projectId,
      credential: cert({
        projectId: parsed.project_id ?? projectId,
        clientEmail: parsed.client_email,
        privateKey: String(parsed.private_key).replace(/\\n/g, "\n"),
      }),
    });
  }

  if (process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim()) {
    return initializeApp({ projectId });
  }

  throw new Error(
    "No Firebase credentials. Set emulator hosts or a service account.",
  );
}

async function appendAuditLog(db, entry) {
  const record = {
    actor: entry.actor,
    action: entry.action,
    targetType: entry.targetType,
    targetId: entry.targetId,
    detail: entry.detail,
    createdAt: FieldValue.serverTimestamp(),
  };
  if (entry.changedFields !== undefined) record.changedFields = entry.changedFields;
  if (entry.before !== undefined) record.before = entry.before;
  if (entry.after !== undefined) record.after = entry.after;
  await db.collection(ADMIN_AUDIT_LOGS).add(record);
}

function approximateCreatedAt(profileData) {
  const updatedAt = profileData?.["updatedAt"];
  if (updatedAt instanceof Timestamp) {
    return updatedAt;
  }
  return Timestamp.now();
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!args.actor) {
    console.error(
      "Usage: node scripts/backfill-missing-users-docs.mjs --actor <admin-email> [--dry-run]",
    );
    process.exit(1);
  }

  initApp();
  const db = getFirestore();

  const profilesSnapshot = await db.collection(USER_PROFILES).get();
  console.log(
    `Found ${profilesSnapshot.size} userProfiles doc(s) ` +
      `(mode: ${isEmulatorMode() ? "emulator" : "live"}, project: ${getProjectId()}).`,
  );

  let created = 0;
  let skipped = 0;

  for (const profileDoc of profilesSnapshot.docs) {
    const uid = profileDoc.id;
    const userRef = db.collection(USERS).doc(uid);
    const existing = await userRef.get();

    if (existing.exists) {
      skipped += 1;
      continue;
    }

    const profileData = profileDoc.data();
    const createdAt = approximateCreatedAt(profileData);
    const after = {
      userRole: DEFAULT_USER_ROLE,
      subscriptionStatus: DEFAULT_SUBSCRIPTION_STATUS,
      accountStatus: DEFAULT_ACCOUNT_STATUS,
      createdAt: createdAt.toDate().toISOString(),
    };

    if (args.dryRun) {
      console.log(`[dry-run] would create users/${uid}:`, after);
      created += 1;
      continue;
    }

    await userRef.set({
      userRole: DEFAULT_USER_ROLE,
      subscriptionStatus: DEFAULT_SUBSCRIPTION_STATUS,
      accountStatus: DEFAULT_ACCOUNT_STATUS,
      createdAt,
      updatedAt: FieldValue.serverTimestamp(),
    });

    await appendAuditLog(db, {
      actor: args.actor,
      action: "user.backfill.create-users-doc",
      targetType: "user",
      targetId: uid,
      detail: `Created missing users/${uid} doc from userProfiles/${uid} with default role/subscription/status.`,
      changedFields: ["userRole", "subscriptionStatus", "accountStatus", "createdAt"],
      before: null,
      after,
    });

    console.log(`Created users/${uid}.`);
    created += 1;
  }

  console.log(
    `${args.dryRun ? "[dry-run] " : ""}Done. Created ${created}, skipped ${skipped} (already had a users doc).`,
  );
}

main().catch((error) => {
  console.error("Backfill failed:");
  console.error(error?.message ?? error);
  process.exit(1);
});
