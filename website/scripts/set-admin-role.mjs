// Grant the Platform Administrator role to a Firebase Auth user.
//
// Usage:
//   node scripts/set-admin-role.mjs <email>
//   node scripts/set-admin-role.mjs <email> --create --password <pw>
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
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDir, "..");

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
  const args = { email: null, create: false, password: null };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--create") {
      args.create = true;
    } else if (token === "--password") {
      args.password = argv[index + 1] ?? null;
      index += 1;
    } else if (!args.email && !token.startsWith("--")) {
      args.email = token;
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

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!args.email) {
    console.error(
      "Usage: node scripts/set-admin-role.mjs <email> [--create --password <pw>]",
    );
    process.exit(1);
  }

  initApp();
  const auth = getAuth();
  const db = getFirestore();

  let userRecord = null;
  try {
    userRecord = await auth.getUserByEmail(args.email);
    console.log(`Found existing Auth user: ${userRecord.uid}`);
  } catch (error) {
    if (error?.code !== "auth/user-not-found") {
      throw error;
    }
  }

  if (!userRecord) {
    if (!args.create) {
      console.error(
        `No Auth user for ${args.email}. Re-run with --create --password <pw>.`,
      );
      process.exit(1);
    }
    if (!args.password) {
      console.error("--create requires --password <pw>.");
      process.exit(1);
    }
    userRecord = await auth.createUser({
      email: args.email,
      password: args.password,
      emailVerified: true,
    });
    console.log(`Created Auth user: ${userRecord.uid}`);
  }

  const userRef = db.collection("users").doc(userRecord.uid);
  const existing = await userRef.get();
  const subscriptionStatus =
    existing.exists && typeof existing.get("subscriptionStatus") === "string"
      ? existing.get("subscriptionStatus")
      : "basic";

  await userRef.set(
    {
      userRole: "platformAdmin",
      subscriptionStatus,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  console.log(
    `Set users/${userRecord.uid}.userRole = platformAdmin ` +
      `(mode: ${isEmulatorMode() ? "emulator" : "live"}, project: ${getProjectId()}).`,
  );
}

main().catch((error) => {
  console.error("Failed to set admin role:");
  console.error(error?.message ?? error);
  process.exit(1);
});
