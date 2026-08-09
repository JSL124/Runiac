"use client";

import Link from "next/link";
import { useActionState } from "react";
import { signIn } from "@/lib/actions/auth";
import { initialSignInState } from "@/lib/actions/auth-state";
import {
  AuthEmailField,
  AuthFormMessage,
  AuthPasswordField,
  AuthSubmitButton,
} from "@/components/AuthFormFields";
import { AuthDivider, AuthGoogleButton } from "@/components/AuthGoogleButton";

export function LoginForm({
  configured,
  googleConfigured,
}: {
  configured: boolean;
  googleConfigured: boolean;
}) {
  const [state, formAction] = useActionState(signIn, initialSignInState);

  return (
    <form
      action={formAction}
      className="space-y-5"
      aria-label="Runiac sign in form"
    >
      {!configured ? (
        <AuthFormMessage role="status">
          Sign-in is not configured in this environment. Add the Firebase
          environment variables to enable account access.
        </AuthFormMessage>
      ) : null}

      <AuthEmailField disabled={!configured} />

      <AuthPasswordField
        id="password"
        name="password"
        label="Password"
        autoComplete="current-password"
        disabled={!configured}
        placeholder="Enter your password"
      />

      {state.error ? <AuthFormMessage>{state.error}</AuthFormMessage> : null}

      <AuthSubmitButton
        disabled={!configured}
        idleLabel="Sign in"
        pendingLabel="Signing in..."
      />

      <AuthDivider />

      <AuthGoogleButton
        configured={googleConfigured}
        idleLabel="Continue with Google"
      />

      <div className="space-y-10 pt-4 text-center">
        <Link
          href="/forgot-password"
          className="inline-block text-sm font-black text-brand transition-colors hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/30 focus-visible:ring-offset-4"
        >
          Forgot password?
        </Link>
        <p className="text-sm font-bold text-muted sm:text-base">
          Do not have an account?{" "}
          <Link
            href="/signup"
            className="font-black text-brand transition-colors hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/30 focus-visible:ring-offset-4"
          >
            Sign up
          </Link>
        </p>
      </div>
    </form>
  );
}
