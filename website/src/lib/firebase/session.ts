// Server-side session-cookie auth flow for the Runiac admin console.
//
// The Platform Administrator signs in with the same Firebase Auth accounts as
// the mobile app. We exchange email/password for an ID token via the Identity
// Toolkit REST API, mint a Firebase session cookie from that ID token, and then
// verify the cookie on each request. Admin status is derived from the user's
// Firestore role (users/{uid}.userRole === 'platformAdmin') with a bootstrap
// fallback for emails listed in FIREBASE_ADMIN_EMAILS.
//
// This module is intentionally framework-agnostic: it never imports
// next/headers. Callers pass cookie values in and read them out.

import { getAdminAuth, getAdminDb } from "./admin";
import {
  getAuthEmulatorHost,
  getFirebaseWebApiKey,
  isBootstrapAdminEmail,
  isEmulatorMode,
} from "./config";

export const SESSION_COOKIE_NAME = "runiac_admin_session";

// createSessionCookie accepts a max expiry of 14 days; we use 5.
export const SESSION_DURATION_MS = 5 * 24 * 60 * 60 * 1000;

export type SignInErrorKind = "invalid-credentials" | "config" | "network";

export type SignInSuccess = {
  ok: true;
  idToken: string;
  uid: string;
  email: string;
};

export type SignInFailure = {
  ok: false;
  kind: SignInErrorKind;
  message: string;
};

export type SignInResult = SignInSuccess | SignInFailure;

export type SignUpErrorKind =
  | "email-exists"
  | "weak-password"
  | "invalid-email"
  | "config"
  | "network";

export type SignUpSuccess = {
  ok: true;
  idToken: string;
  uid: string;
  email: string;
};

export type SignUpFailure = {
  ok: false;
  kind: SignUpErrorKind;
  message: string;
};

export type SignUpResult = SignUpSuccess | SignUpFailure;

export type PasswordResetResult =
  | { ok: true }
  | { ok: false; kind: "config" | "network"; message: string };

export type FirebaseAdminUser = {
  uid: string;
  email: string | null;
  isAdmin: boolean;
};

type IdentityToolkitResponse = {
  idToken?: string;
  localId?: string;
  email?: string;
  error?: { message?: string };
};

// The Identity Toolkit REST methods this module drives. `signInWithPassword`
// backs the console sign-in, `signUp` backs website account creation, and
// `sendOobCode` backs the password-reset email.
type IdentityToolkitMethod = "signInWithPassword" | "signUp" | "sendOobCode";

function identityToolkitUrl(
  method: IdentityToolkitMethod,
): { url: string; ok: true } | { ok: false } {
  if (isEmulatorMode()) {
    const host = getAuthEmulatorHost();

    if (!host) {
      return { ok: false };
    }

    return {
      ok: true,
      url:
        `http://${host}/identitytoolkit.googleapis.com/v1/` +
        `accounts:${method}?key=fake-api-key`,
    };
  }

  const apiKey = getFirebaseWebApiKey();

  if (!apiKey) {
    return { ok: false };
  }

  return {
    ok: true,
    url:
      "https://identitytoolkit.googleapis.com/v1/" +
      `accounts:${method}?key=${apiKey}`,
  };
}

const NOT_CONFIGURED_MESSAGE =
  "Firebase sign-in is not configured. Set NEXT_PUBLIC_FIREBASE_API_KEY " +
  "(live) or FIREBASE_AUTH_EMULATOR_HOST (emulator).";

// Exchanges email/password for an ID token. Never throws raw fetch errors:
// distinguishes bad credentials from configuration/network problems.
export async function signInWithPassword(
  email: string,
  password: string,
): Promise<SignInResult> {
  const endpoint = identityToolkitUrl("signInWithPassword");

  if (!endpoint.ok) {
    return { ok: false, kind: "config", message: NOT_CONFIGURED_MESSAGE };
  }

  let response: Response;

  try {
    response = await fetch(endpoint.url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    });
  } catch {
    return {
      ok: false,
      kind: "network",
      message: "Could not reach the Firebase authentication service.",
    };
  }

  let body: IdentityToolkitResponse;

  try {
    body = (await response.json()) as IdentityToolkitResponse;
  } catch {
    return {
      ok: false,
      kind: "network",
      message: "Received an unreadable response from Firebase authentication.",
    };
  }

  if (!response.ok || !body.idToken || !body.localId) {
    const code = body.error?.message ?? "";

    if (
      code.includes("INVALID_LOGIN_CREDENTIALS") ||
      code.includes("INVALID_PASSWORD") ||
      code.includes("EMAIL_NOT_FOUND") ||
      code.includes("USER_DISABLED") ||
      code.includes("INVALID_EMAIL")
    ) {
      return {
        ok: false,
        kind: "invalid-credentials",
        message: "Invalid email or password.",
      };
    }

    return {
      ok: false,
      kind: "config",
      message: code || "Firebase authentication failed.",
    };
  }

  return {
    ok: true,
    idToken: body.idToken,
    uid: body.localId,
    email: body.email ?? email,
  };
}

// Creates a brand-new email/password account.
//
// Deliberately creates the Firebase Auth identity only: no Firestore document
// is written here. The mobile app treats a signed-in account with no
// `userProfiles/{uid}` document as "onboarding not finished yet" and routes it
// straight into the in-app onboarding flow, which is where a runner's profile
// is actually built. Writing a placeholder profile from the website would make
// the account look already-onboarded and skip that flow.
export async function signUpWithPassword(
  email: string,
  password: string,
): Promise<SignUpResult> {
  const endpoint = identityToolkitUrl("signUp");

  if (!endpoint.ok) {
    return { ok: false, kind: "config", message: NOT_CONFIGURED_MESSAGE };
  }

  let response: Response;

  try {
    response = await fetch(endpoint.url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    });
  } catch {
    return {
      ok: false,
      kind: "network",
      message: "Could not reach the Firebase authentication service.",
    };
  }

  let body: IdentityToolkitResponse;

  try {
    body = (await response.json()) as IdentityToolkitResponse;
  } catch {
    return {
      ok: false,
      kind: "network",
      message: "Received an unreadable response from Firebase authentication.",
    };
  }

  if (!response.ok || !body.idToken || !body.localId) {
    const code = body.error?.message ?? "";

    if (code.includes("EMAIL_EXISTS")) {
      return {
        ok: false,
        kind: "email-exists",
        message:
          "An account already exists for that email. Sign in instead, or " +
          "reset your password.",
      };
    }

    if (code.includes("WEAK_PASSWORD") || code.includes("PASSWORD_")) {
      return {
        ok: false,
        kind: "weak-password",
        message: "Choose a stronger password of at least 8 characters.",
      };
    }

    if (code.includes("INVALID_EMAIL") || code.includes("MISSING_EMAIL")) {
      return {
        ok: false,
        kind: "invalid-email",
        message: "Enter a valid email address.",
      };
    }

    return {
      ok: false,
      kind: "config",
      message: code || "Could not create the account. Try again.",
    };
  }

  return {
    ok: true,
    idToken: body.idToken,
    uid: body.localId,
    email: body.email ?? email,
  };
}

// Sends a Firebase password-reset email. The link in that mail is handled by
// Firebase's own hosted action page on the project's auth domain, so there is
// no reset handler to build here.
//
// EMAIL_NOT_FOUND is reported as success on purpose: the caller shows one
// generic "if an account exists, a link is on the way" message either way, so
// the form can never be used to probe which emails have Runiac accounts.
export async function sendPasswordResetEmail(
  email: string,
): Promise<PasswordResetResult> {
  const endpoint = identityToolkitUrl("sendOobCode");

  if (!endpoint.ok) {
    return { ok: false, kind: "config", message: NOT_CONFIGURED_MESSAGE };
  }

  let response: Response;

  try {
    response = await fetch(endpoint.url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ requestType: "PASSWORD_RESET", email }),
    });
  } catch {
    return {
      ok: false,
      kind: "network",
      message: "Could not reach the Firebase authentication service.",
    };
  }

  if (response.ok) {
    return { ok: true };
  }

  let body: IdentityToolkitResponse;

  try {
    body = (await response.json()) as IdentityToolkitResponse;
  } catch {
    return {
      ok: false,
      kind: "network",
      message: "Received an unreadable response from Firebase authentication.",
    };
  }

  const code = body.error?.message ?? "";

  if (code.includes("EMAIL_NOT_FOUND")) {
    return { ok: true };
  }

  return {
    ok: false,
    kind: "network",
    message: "Could not send the reset email right now. Try again.",
  };
}

// Mints a Firebase session cookie from a fresh ID token.
export async function createAdminSessionCookie(idToken: string) {
  return getAdminAuth().createSessionCookie(idToken, {
    expiresIn: SESSION_DURATION_MS,
  });
}

// Verifies a session cookie (with revocation check). Returns null on any
// failure so callers can treat it as "not signed in".
export async function verifyAdminSession(
  cookieValue: string | null | undefined,
): Promise<{ uid: string; email: string | null } | null> {
  if (!cookieValue) {
    return null;
  }

  try {
    const decoded = await getAdminAuth().verifySessionCookie(cookieValue, true);
    return { uid: decoded.uid, email: decoded.email ?? null };
  } catch {
    return null;
  }
}

// Verifies the session and resolves the caller's admin status. A user is an
// admin when their users/{uid} doc has userRole 'platformAdmin', OR their email
// is in the bootstrap allowlist (which may have no user doc yet).
export async function getFirebaseAdminUser(
  cookieValue: string | null | undefined,
): Promise<FirebaseAdminUser | null> {
  const session = await verifyAdminSession(cookieValue);

  if (!session) {
    return null;
  }

  let userRole: string | null = null;

  try {
    const snapshot = await getAdminDb()
      .collection("users")
      .doc(session.uid)
      .get();

    if (snapshot.exists) {
      const role = snapshot.get("userRole");
      userRole = typeof role === "string" ? role : null;
    }
  } catch {
    // Missing doc / read failure: fall back to the bootstrap allowlist only.
    userRole = null;
  }

  const isAdmin =
    userRole === "platformAdmin" || isBootstrapAdminEmail(session.email);

  return { uid: session.uid, email: session.email, isAdmin };
}
