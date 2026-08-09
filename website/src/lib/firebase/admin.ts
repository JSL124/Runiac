// Lazy firebase-admin App singleton for the Runiac admin console.
//
// Next.js dev mode hot-reloads modules, which can otherwise trigger a duplicate
// initializeApp() call; getApps() guards against that. In emulator mode the
// SDK auto-detects FIRESTORE_EMULATOR_HOST / FIREBASE_AUTH_EMULATOR_HOST, so no
// credentials are supplied. In live mode we pass explicit cert credentials.

import { cert, getApps, initializeApp, type App } from "firebase-admin/app";
import { getAuth, type Auth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

import {
  getFirebaseProjectId,
  getServiceAccount,
  hasCredentialsFilePath,
  isEmulatorMode,
} from "./config";

const APP_NAME = "runiac-admin";

let cachedApp: App | null = null;

export function getAdminApp(): App {
  if (cachedApp) {
    return cachedApp;
  }

  const existing = getApps().find((app) => app.name === APP_NAME);

  if (existing) {
    cachedApp = existing;
    return cachedApp;
  }

  const projectId = getFirebaseProjectId();

  if (isEmulatorMode()) {
    cachedApp = initializeApp({ projectId }, APP_NAME);
    return cachedApp;
  }

  const serviceAccount = getServiceAccount();

  if (serviceAccount) {
    cachedApp = initializeApp(
      {
        projectId: serviceAccount.projectId,
        credential: cert({
          projectId: serviceAccount.projectId,
          clientEmail: serviceAccount.clientEmail,
          privateKey: serviceAccount.privateKey,
        }),
      },
      APP_NAME,
    );
    return cachedApp;
  }

  if (hasCredentialsFilePath()) {
    // Application Default Credentials from GOOGLE_APPLICATION_CREDENTIALS.
    cachedApp = initializeApp({ projectId }, APP_NAME);
    return cachedApp;
  }

  throw new Error(
    "Firebase Admin is not configured. Set FIRESTORE_EMULATOR_HOST + " +
      "FIREBASE_AUTH_EMULATOR_HOST for emulator mode, or a service account for " +
      "live mode.",
  );
}

export function getAdminAuth(): Auth {
  return getAuth(getAdminApp());
}

export function getAdminDb(): Firestore {
  return getFirestore(getAdminApp());
}
