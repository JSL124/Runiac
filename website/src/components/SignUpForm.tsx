"use client";

import Link from "next/link";
import { useActionState } from "react";
import { signUp } from "@/lib/actions/auth";
import { initialSignUpState } from "@/lib/actions/auth-state";
import {
  AuthEmailField,
  AuthFormMessage,
  AuthPasswordField,
  AuthSubmitButton,
} from "@/components/AuthFormFields";
import { AuthDivider, AuthGoogleButton } from "@/components/AuthGoogleButton";

// What happens after this form succeeds is the whole point of it: the website
// creates the account only, and the runner finishes onboarding in the app. The
// success panel says so explicitly, because nothing else on the website would
// make that obvious.
function AccountCreatedPanel({ email }: { email: string }) {
  return (
    <div className="space-y-6" role="status" aria-live="polite">
      <div className="rounded-[1.5rem] border border-brand/20 bg-brand-soft/60 px-6 py-6">
        <p className="text-lg font-black text-brand">
          Your Runiac account is ready.
        </p>
        <p className="mt-3 text-sm font-semibold leading-relaxed text-foreground">
          We created your account for{" "}
          <span className="font-black text-brand">{email}</span>. Open the
          Runiac app, sign in with the same email and password, and the app will
          walk you through onboarding - your goal, your running experience, and
          your first beginner plan.
        </p>
      </div>

      <Link
        href="/download"
        className="flex h-16 w-full items-center justify-center rounded-[1.5rem] bg-brand px-6 text-lg font-black text-white shadow-[0_18px_36px_-24px_rgba(0,30,98,0.7)] transition duration-200 hover:-translate-y-px hover:bg-brand/90 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-brand/25"
      >
        Get the app
      </Link>

      <p className="text-center text-sm font-bold text-muted sm:text-base">
        Already have the app?{" "}
        <Link
          href="/login"
          className="font-black text-brand transition-colors hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/30 focus-visible:ring-offset-4"
        >
          Sign in here
        </Link>
      </p>
    </div>
  );
}

export function SignUpForm({
  configured,
  googleConfigured,
}: {
  configured: boolean;
  googleConfigured: boolean;
}) {
  const [state, formAction] = useActionState(signUp, initialSignUpState);

  if (state.createdEmail) {
    return <AccountCreatedPanel email={state.createdEmail} />;
  }

  return (
    <form
      action={formAction}
      className="space-y-5"
      aria-label="Runiac sign up form"
    >
      {!configured ? (
        <AuthFormMessage role="status">
          Sign-up is not configured in this environment. Add the Firebase
          environment variables to enable account creation.
        </AuthFormMessage>
      ) : null}

      <AuthEmailField disabled={!configured} />

      <AuthPasswordField
        id="password"
        name="password"
        label="Password"
        autoComplete="new-password"
        disabled={!configured}
        placeholder="At least 8 characters"
        minLength={8}
      />

      <AuthPasswordField
        id="confirmPassword"
        name="confirmPassword"
        label="Confirm password"
        autoComplete="new-password"
        disabled={!configured}
        placeholder="Repeat your password"
        minLength={8}
      />

      {state.error ? <AuthFormMessage>{state.error}</AuthFormMessage> : null}

      <AuthSubmitButton
        disabled={!configured}
        idleLabel="Create account"
        pendingLabel="Creating account..."
      />

      <AuthDivider />

      <AuthGoogleButton
        configured={googleConfigured}
        idleLabel="Sign up with Google"
      />

      <p className="pt-4 text-center text-sm font-bold text-muted sm:text-base">
        Already have an account?{" "}
        <Link
          href="/login"
          className="font-black text-brand transition-colors hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/30 focus-visible:ring-offset-4"
        >
          Sign in
        </Link>
      </p>
    </form>
  );
}
