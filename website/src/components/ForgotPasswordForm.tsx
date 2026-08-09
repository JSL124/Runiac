"use client";

import Link from "next/link";
import { useActionState } from "react";
import { requestPasswordReset } from "@/lib/actions/auth";
import { initialPasswordResetState } from "@/lib/actions/auth-state";
import {
  AuthEmailField,
  AuthFormMessage,
  AuthSubmitButton,
} from "@/components/AuthFormFields";

export function ForgotPasswordForm({ configured }: { configured: boolean }) {
  const [state, formAction] = useActionState(
    requestPasswordReset,
    initialPasswordResetState,
  );

  return (
    <form
      action={formAction}
      className="space-y-5"
      aria-label="Runiac password reset form"
    >
      {!configured ? (
        <AuthFormMessage role="status">
          Password reset is not configured in this environment. Add the Firebase
          environment variables to enable it.
        </AuthFormMessage>
      ) : null}

      <AuthEmailField disabled={!configured} />

      {state.error ? <AuthFormMessage>{state.error}</AuthFormMessage> : null}

      {/* Deliberately the same message whether or not that email has an
          account - see requestPasswordReset(). */}
      {state.sent ? (
        <AuthFormMessage role="status" tone="success">
          If an account exists for that email, a reset link is on its way. The
          link opens a secure Firebase page where you can choose a new
          password, then sign in again here or in the app.
        </AuthFormMessage>
      ) : null}

      <AuthSubmitButton
        disabled={!configured}
        idleLabel="Send reset link"
        pendingLabel="Sending..."
      />

      <div className="space-y-4 pt-4 text-center">
        <p className="text-sm font-bold text-muted sm:text-base">
          Remembered it?{" "}
          <Link
            href="/login"
            className="font-black text-brand transition-colors hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/30 focus-visible:ring-offset-4"
          >
            Back to sign in
          </Link>
        </p>
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
