"use client";

// Browser-side Firebase app for the Google sign-in popup only.
//
// The client SDK's one job here is to run the Google popup and hand back an
// ID token - it never talks to Firestore, never renders trusted data, and
// never becomes a source of truth. The server (src/lib/actions/auth.ts)
// verifies that token and mints the httpOnly session cookie; once the token
// has been captured we sign the client SDK back out immediately so no
// client-side auth state lingers. The session cookie stays the single source
// of truth for who is signed in.

import { getApp, getApps, initializeApp } from "firebase/app";
import {
  GoogleAuthProvider,
  getAuth,
  signInWithPopup,
  signOut,
} from "firebase/auth";
import {
  getFirebaseAuthDomain,
  getFirebaseProjectId,
  getFirebaseWebApiKey,
} from "./config";

// Lazily initializes (or reuses) the one browser-side Firebase app instance.
// Exported so other client-only modules that need a Firebase SDK service
// (e.g. src/lib/newsletter.ts, which calls Cloud Functions via
// getFunctions()) share this exact app rather than each running their own
// initializeApp(), which would otherwise throw "app already exists".
export function getClientApp() {
  return getApps().length
    ? getApp()
    : initializeApp({
        apiKey: getFirebaseWebApiKey() ?? undefined,
        authDomain: getFirebaseAuthDomain(),
        projectId: getFirebaseProjectId(),
      });
}

function getClientAuth() {
  return getAuth(getClientApp());
}

// Runs the Google popup and returns a fresh ID token, or null when the user
// closed the popup without completing sign-in. Any other failure is
// rethrown so the caller can surface an error.
export async function signInWithGooglePopup(): Promise<string | null> {
  const auth = getClientAuth();

  let idToken: string;

  try {
    const result = await signInWithPopup(auth, new GoogleAuthProvider());
    idToken = await result.user.getIdToken();
  } catch (error) {
    const code = (error as { code?: string })?.code;

    if (
      code === "auth/popup-closed-by-user" ||
      code === "auth/cancelled-popup-request"
    ) {
      return null;
    }

    throw error;
  }

  try {
    // Best-effort: the ID token is already captured, so a signOut failure
    // here shouldn't block the server exchange.
    await signOut(auth);
  } catch {
    // Ignored - the client-side session is discarded either way once the
    // server mints its own httpOnly cookie.
  }

  return idToken;
}
