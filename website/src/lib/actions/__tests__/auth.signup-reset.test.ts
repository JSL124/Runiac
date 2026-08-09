// Unit tests for the two public account actions added for the website:
// signUp() and requestPasswordReset(). The Identity Toolkit layer
// (src/lib/firebase/session.ts) is mocked out, so this file only asserts the
// action-layer contract: validation, hasFirebaseEnv() gating, and the two
// invariants that matter beyond happy paths — the website never creates a
// Firestore profile for a new account (the app's onboarding owns that), and a
// reset request never reveals whether an email has an account.

import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  hasFirebaseEnvMock,
  signUpWithPasswordMock,
  sendPasswordResetEmailMock,
} = vi.hoisted(() => ({
  hasFirebaseEnvMock: vi.fn(),
  signUpWithPasswordMock: vi.fn(),
  sendPasswordResetEmailMock: vi.fn(),
}));

vi.mock("@/lib/firebase/config", () => ({
  hasFirebaseEnv: hasFirebaseEnvMock,
}));

vi.mock("@/lib/firebase/admin", () => ({
  getAdminAuth: vi.fn(),
}));

vi.mock("@/lib/firebase/session", () => ({
  SESSION_COOKIE_NAME: "runiac_admin_session",
  SESSION_DURATION_MS: 1000,
  createAdminSessionCookie: vi.fn(),
  getFirebaseAdminUser: vi.fn(),
  signInWithPassword: vi.fn(),
  signUpWithPassword: signUpWithPasswordMock,
  sendPasswordResetEmail: sendPasswordResetEmailMock,
}));

vi.mock("next/headers", () => ({
  cookies: vi.fn(async () => ({ set: vi.fn(), delete: vi.fn() })),
}));

vi.mock("next/navigation", () => ({
  redirect: vi.fn(),
}));

import { requestPasswordReset, signUp } from "@/lib/actions/auth";
import {
  initialPasswordResetState,
  initialSignUpState,
} from "@/lib/actions/auth-state";

function signUpForm(fields: Record<string, string>) {
  const formData = new FormData();

  for (const [key, value] of Object.entries(fields)) {
    formData.set(key, value);
  }

  return formData;
}

const validSignUp = {
  email: "runner@runiac.app",
  password: "password123",
  confirmPassword: "password123",
};

describe("signUp", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasFirebaseEnvMock.mockReturnValue(true);
    signUpWithPasswordMock.mockResolvedValue({
      ok: true,
      idToken: "id-token",
      uid: "new-uid",
      email: "runner@runiac.app",
    });
  });

  it("creates the account and reports the email back for the app handoff", async () => {
    const state = await signUp(initialSignUpState, signUpForm(validSignUp));

    expect(signUpWithPasswordMock).toHaveBeenCalledWith(
      "runner@runiac.app",
      "password123",
    );
    expect(state).toEqual({ error: null, createdEmail: "runner@runiac.app" });
  });

  it("trims the email so a pasted address still matches in the app", async () => {
    await signUp(
      initialSignUpState,
      signUpForm({ ...validSignUp, email: "  runner@runiac.app  " }),
    );

    expect(signUpWithPasswordMock).toHaveBeenCalledWith(
      "runner@runiac.app",
      "password123",
    );
  });

  it("rejects a mismatched confirmation without calling Firebase", async () => {
    const state = await signUp(
      initialSignUpState,
      signUpForm({ ...validSignUp, confirmPassword: "password124" }),
    );

    expect(state.createdEmail).toBeNull();
    expect(state.error).toBe("Both passwords must match.");
    expect(signUpWithPasswordMock).not.toHaveBeenCalled();
  });

  it("rejects a password shorter than the app's 8-character minimum", async () => {
    // The app refuses to create anything shorter, so accepting it here would
    // mint an account its owner could not manage from the app.
    const state = await signUp(
      initialSignUpState,
      signUpForm({
        ...validSignUp,
        password: "short7c",
        confirmPassword: "short7c",
      }),
    );

    expect(state.error).toBe(
      "Use at least 8 characters for your password.",
    );
    expect(signUpWithPasswordMock).not.toHaveBeenCalled();
  });

  it("rejects a malformed email", async () => {
    const state = await signUp(
      initialSignUpState,
      signUpForm({ ...validSignUp, email: "runner@runiac" }),
    );

    expect(state.error).toBe("Enter a valid email address.");
    expect(signUpWithPasswordMock).not.toHaveBeenCalled();
  });

  it("surfaces the Firebase failure message", async () => {
    signUpWithPasswordMock.mockResolvedValue({
      ok: false,
      kind: "email-exists",
      message: "An account already exists for that email.",
    });

    const state = await signUp(initialSignUpState, signUpForm(validSignUp));

    expect(state).toEqual({
      error: "An account already exists for that email.",
      createdEmail: null,
    });
  });

  it("refuses to create an account when Firebase is not configured", async () => {
    hasFirebaseEnvMock.mockReturnValue(false);

    const state = await signUp(initialSignUpState, signUpForm(validSignUp));

    expect(state.error).toBe("Sign-up is not configured in this environment.");
    expect(signUpWithPasswordMock).not.toHaveBeenCalled();
  });
});

describe("requestPasswordReset", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasFirebaseEnvMock.mockReturnValue(true);
    sendPasswordResetEmailMock.mockResolvedValue({ ok: true });
  });

  it("sends the reset email for a valid address", async () => {
    const state = await requestPasswordReset(
      initialPasswordResetState,
      signUpForm({ email: "  runner@runiac.app " }),
    );

    expect(sendPasswordResetEmailMock).toHaveBeenCalledWith(
      "runner@runiac.app",
    );
    expect(state).toEqual({ error: null, sent: true });
  });

  it("reports the same success for an address with no account", async () => {
    // sendPasswordResetEmail() maps EMAIL_NOT_FOUND to ok:true precisely so
    // this form cannot be used to enumerate Runiac accounts.
    sendPasswordResetEmailMock.mockResolvedValue({ ok: true });

    const state = await requestPasswordReset(
      initialPasswordResetState,
      signUpForm({ email: "stranger@example.com" }),
    );

    expect(state).toEqual({ error: null, sent: true });
  });

  it("rejects an empty or malformed email without calling Firebase", async () => {
    const empty = await requestPasswordReset(
      initialPasswordResetState,
      signUpForm({ email: "   " }),
    );
    const malformed = await requestPasswordReset(
      initialPasswordResetState,
      signUpForm({ email: "runner@" }),
    );

    expect(empty.error).toBe("Enter your email to reset your password.");
    expect(malformed.error).toBe("Enter a valid email address.");
    expect(empty.sent).toBe(false);
    expect(malformed.sent).toBe(false);
    expect(sendPasswordResetEmailMock).not.toHaveBeenCalled();
  });

  it("surfaces a transport failure instead of claiming the mail was sent", async () => {
    sendPasswordResetEmailMock.mockResolvedValue({
      ok: false,
      kind: "network",
      message: "Could not send the reset email right now. Try again.",
    });

    const state = await requestPasswordReset(
      initialPasswordResetState,
      signUpForm({ email: "runner@runiac.app" }),
    );

    expect(state).toEqual({
      error: "Could not send the reset email right now. Try again.",
      sent: false,
    });
  });

  it("refuses when Firebase is not configured", async () => {
    hasFirebaseEnvMock.mockReturnValue(false);

    const state = await requestPasswordReset(
      initialPasswordResetState,
      signUpForm({ email: "runner@runiac.app" }),
    );

    expect(state.error).toBe(
      "Password reset is not configured in this environment.",
    );
    expect(sendPasswordResetEmailMock).not.toHaveBeenCalled();
  });
});
