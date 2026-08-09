"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { getAdminAuth } from "@/lib/firebase/admin";
import { hasFirebaseEnv } from "@/lib/firebase/config";
import {
  SESSION_COOKIE_NAME,
  SESSION_DURATION_MS,
  createAdminSessionCookie,
  getFirebaseAdminUser,
  sendPasswordResetEmail,
  signInWithPassword,
  signUpWithPassword,
} from "@/lib/firebase/session";
import type {
  PasswordResetState,
  SignInState,
  SignUpState,
} from "./auth-state";

// Matches the mobile app's new-password rule
// (mobile/lib/features/auth/presentation/widgets/
// runiac_auth_validators.dart), so an account created here can always sign in
// there.
const MIN_PASSWORD_LENGTH = 8;

const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function signIn(
  _prevState: SignInState,
  formData: FormData,
): Promise<SignInState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");

  if (!email || !password) {
    return { error: "Enter your email and password to sign in." };
  }

  // Firebase path (emulator or live service account).
  if (hasFirebaseEnv()) {
    const result = await signInWithPassword(email, password);

    if (!result.ok) {
      // invalid-credentials carries a friendly message; config/network carry
      // their own descriptive messages.
      return { error: result.message };
    }

    let sessionCookie: string;

    try {
      sessionCookie = await createAdminSessionCookie(result.idToken);
    } catch {
      return { error: "Could not create an admin session. Try again." };
    }

    const cookieStore = await cookies();
    cookieStore.set(SESSION_COOKIE_NAME, sessionCookie, {
      httpOnly: true,
      sameSite: "lax",
      path: "/",
      // The Firebase emulator runs on plain http in development.
      secure: process.env.NODE_ENV === "production",
      maxAge: SESSION_DURATION_MS / 1000,
    });

    const adminUser = await getFirebaseAdminUser(sessionCookie);

    if (adminUser?.isAdmin) {
      redirect("/admin");
    }

    redirect("/");
  }

  return { error: "Sign-in is not configured in this environment." };
}

// Server side of the Google sign-in popup flow: the client obtains an ID
// token from Firebase Auth's GoogleAuthProvider popup, then hands it here to
// be verified and exchanged for the same admin session cookie signInWithPassword
// mints for the email/password flow.
export async function signInWithGoogle(
  idToken: string,
): Promise<SignInState> {
  if (!hasFirebaseEnv()) {
    return { error: "Google sign-in is not configured in this environment." };
  }

  if (typeof idToken !== "string" || !idToken) {
    return { error: "Google sign-in failed. Try again." };
  }

  try {
    await getAdminAuth().verifyIdToken(idToken);
  } catch {
    return { error: "Could not verify the Google sign-in. Try again." };
  }

  let sessionCookie: string;

  try {
    sessionCookie = await createAdminSessionCookie(idToken);
  } catch {
    return { error: "Could not create a session. Try again." };
  }

  const cookieStore = await cookies();
  cookieStore.set(SESSION_COOKIE_NAME, sessionCookie, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    // The Firebase emulator runs on plain http in development.
    secure: process.env.NODE_ENV === "production",
    maxAge: SESSION_DURATION_MS / 1000,
  });

  const adminUser = await getFirebaseAdminUser(sessionCookie);

  if (adminUser?.isAdmin) {
    redirect("/admin");
  }

  redirect("/");
}

// Creates a Runiac account from the website.
//
// The website only creates the Firebase Auth identity; the runner's profile is
// built by the app's onboarding flow the first time they sign in there (see
// signUpWithPassword's note). No session cookie is minted either: the only
// signed-in surface on this site is the admin console, and a brand-new runner
// account is never an admin.
export async function signUp(
  _prevState: SignUpState,
  formData: FormData,
): Promise<SignUpState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const confirmPassword = String(formData.get("confirmPassword") ?? "");

  if (!email || !password) {
    return {
      error: "Enter your email and a password to create your account.",
      createdEmail: null,
    };
  }

  if (!EMAIL_SHAPE.test(email)) {
    return { error: "Enter a valid email address.", createdEmail: null };
  }

  if (password.length < MIN_PASSWORD_LENGTH) {
    return {
      error: `Use at least ${MIN_PASSWORD_LENGTH} characters for your password.`,
      createdEmail: null,
    };
  }

  if (password !== confirmPassword) {
    return { error: "Both passwords must match.", createdEmail: null };
  }

  if (!hasFirebaseEnv()) {
    return {
      error: "Sign-up is not configured in this environment.",
      createdEmail: null,
    };
  }

  const result = await signUpWithPassword(email, password);

  if (!result.ok) {
    return { error: result.message, createdEmail: null };
  }

  return { error: null, createdEmail: result.email };
}

// Sends a password-reset email. Always reports the same generic outcome for a
// well-formed address so the form cannot be used to discover which emails have
// Runiac accounts.
export async function requestPasswordReset(
  _prevState: PasswordResetState,
  formData: FormData,
): Promise<PasswordResetState> {
  const email = String(formData.get("email") ?? "").trim();

  if (!email) {
    return { error: "Enter your email to reset your password.", sent: false };
  }

  if (!EMAIL_SHAPE.test(email)) {
    return { error: "Enter a valid email address.", sent: false };
  }

  if (!hasFirebaseEnv()) {
    return {
      error: "Password reset is not configured in this environment.",
      sent: false,
    };
  }

  const result = await sendPasswordResetEmail(email);

  if (!result.ok) {
    return { error: result.message, sent: false };
  }

  return { error: null, sent: true };
}

export async function signOut() {
  // Always clear the Firebase admin session cookie (no-op when absent).
  const cookieStore = await cookies();
  cookieStore.delete(SESSION_COOKIE_NAME);

  redirect("/login");
}
