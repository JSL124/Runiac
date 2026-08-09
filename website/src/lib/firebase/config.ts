// Firebase environment handling for the Runiac admin console.
//
// Small pure helpers that read process.env and never throw at import time.
// Two runtime modes are supported:
//
//   * Emulator mode  - FIRESTORE_EMULATOR_HOST + FIREBASE_AUTH_EMULATOR_HOST are
//     set. The Admin SDK and the Identity Toolkit REST endpoint talk to the
//     local emulators; no service account or web API key is required.
//   * Live mode      - a service account (inline JSON or credentials file path)
//     plus the Identity Toolkit web API key are configured.

export const DEFAULT_FIREBASE_PROJECT_ID = "runiac-fypp";

export type FirebaseServiceAccount = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

export function getFirebaseProjectId() {
  return process.env.FIREBASE_PROJECT_ID?.trim() || DEFAULT_FIREBASE_PROJECT_ID;
}

// The default Cloud Storage bucket for `getFirebaseProjectId()`, used by the
// project-documents feature (src/lib/firebase/storage.ts). Runiac's bucket
// uses the post-October-2024 `<project-id>.firebasestorage.app` naming —
// verified against the live project with
// `firebase apps:sdkconfig web --project runiac-fypp`, which is the only
// authoritative source here (firebase_options.dart is gitignored, and the
// Flutter test fixture in
// mobile/test/firebase_emulator_identity_test.dart
// claims `.appspot.com`, which does NOT resolve — uploads against it fail
// with "The specified bucket does not exist"). FIREBASE_STORAGE_BUCKET
// overrides this.
export function getFirebaseStorageBucket() {
  return (
    process.env.FIREBASE_STORAGE_BUCKET?.trim() ||
    `${getFirebaseProjectId()}.firebasestorage.app`
  );
}

export function isEmulatorMode() {
  return Boolean(
    process.env.FIRESTORE_EMULATOR_HOST &&
      process.env.FIREBASE_AUTH_EMULATOR_HOST,
  );
}

export function getFirestoreEmulatorHost() {
  return process.env.FIRESTORE_EMULATOR_HOST?.trim() || null;
}

export function getAuthEmulatorHost() {
  return process.env.FIREBASE_AUTH_EMULATOR_HOST?.trim() || null;
}

// Client-side counterpart to isEmulatorMode() above. FIRESTORE_EMULATOR_HOST /
// FIREBASE_AUTH_EMULATOR_HOST are server-only — Next.js only inlines env vars
// prefixed NEXT_PUBLIC_ into the browser bundle — so a Client Component (e.g.
// src/lib/newsletter.ts, which calls a Functions callable straight from the
// browser) has no way to see the server's emulator mode at all without a
// dedicated public var. Format is "host:port", e.g. "127.0.0.1:5001", matching
// connectFunctionsEmulator()'s (host, port) signature.
export function getFunctionsEmulatorHost() {
  return process.env.NEXT_PUBLIC_FUNCTIONS_EMULATOR_HOST?.trim() || null;
}

export function getFirebaseWebApiKey() {
  return process.env.NEXT_PUBLIC_FIREBASE_API_KEY?.trim() || null;
}

// The Auth domain used by the Google sign-in popup. Falls back to the default
// Firebase-hosted domain for the configured project so callers don't need a
// dedicated env var in the common case.
export function getFirebaseAuthDomain() {
  return (
    process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN?.trim() ||
    `${getFirebaseProjectId()}.firebaseapp.com`
  );
}

// True when Google sign-in can run end to end: the client popup needs the
// public web API key, and the server needs Admin SDK credentials to verify
// the resulting ID token and mint the session cookie.
export function hasGoogleSignInEnv() {
  return Boolean(getFirebaseWebApiKey()) && hasFirebaseEnv();
}

// Reads the service account credentials for live mode, if configured. Prefers
// inline JSON (FIREBASE_SERVICE_ACCOUNT_KEY) and falls back to a credentials
// file path (GOOGLE_APPLICATION_CREDENTIALS) that the SDK resolves itself.
export function getServiceAccount(): FirebaseServiceAccount | null {
  const inlineJson = process.env.FIREBASE_SERVICE_ACCOUNT_KEY?.trim();

  if (!inlineJson) {
    return null;
  }

  let parsed: unknown;

  try {
    parsed = JSON.parse(inlineJson);
  } catch {
    throw new Error(
      "FIREBASE_SERVICE_ACCOUNT_KEY is set but is not valid JSON.",
    );
  }

  if (typeof parsed !== "object" || parsed === null) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT_KEY must be a JSON object.");
  }

  const record = parsed as Record<string, unknown>;
  const projectId = readString(record, "project_id") ?? getFirebaseProjectId();
  const clientEmail = readString(record, "client_email");
  const privateKeyRaw = readString(record, "private_key");

  if (!clientEmail || !privateKeyRaw) {
    throw new Error(
      "FIREBASE_SERVICE_ACCOUNT_KEY must include client_email and private_key.",
    );
  }

  return {
    projectId,
    clientEmail,
    // Support keys pasted with escaped newlines in a single-line env value.
    privateKey: privateKeyRaw.replace(/\\n/g, "\n"),
  };
}

export function hasCredentialsFilePath() {
  return Boolean(process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim());
}

// True when the module has enough configuration to talk to Firebase in either
// mode. Used by the wiring layer to decide between live data and mock data.
export function hasFirebaseEnv() {
  if (isEmulatorMode()) {
    return true;
  }

  if (hasCredentialsFilePath()) {
    return true;
  }

  return Boolean(process.env.FIREBASE_SERVICE_ACCOUNT_KEY?.trim());
}

export function getBootstrapAdminEmails() {
  return (process.env.FIREBASE_ADMIN_EMAILS ?? "")
    .split(",")
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean);
}

export function isBootstrapAdminEmail(email: string | null | undefined) {
  if (!email) {
    return false;
  }

  return getBootstrapAdminEmails().includes(email.trim().toLowerCase());
}

function readString(record: Record<string, unknown>, key: string) {
  const value = record[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}
