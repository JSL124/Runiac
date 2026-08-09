"use client";

import Image from "next/image";
import { useState, useTransition } from "react";
import { signInWithGoogle } from "@/lib/actions/auth";
import { signInWithGooglePopup } from "@/lib/firebase/client";
import { AuthFormMessage } from "@/components/AuthFormFields";

// Google account button, shared by sign in and sign up.
//
// There is only one Google flow for both: the popup signs the runner in and
// creates the Firebase Auth account on first use. A brand-new Google account
// therefore reaches the app with no profile document, which is exactly the
// state the app's onboarding flow expects.

function GoogleMark() {
  return (
    <Image
      src="/google-icon.png"
      alt=""
      width={26}
      height={26}
      className="h-[26px] w-[26px] shrink-0 object-contain"
      aria-hidden="true"
      priority
    />
  );
}

export function AuthGoogleButton({
  configured,
  idleLabel,
  pendingLabel = "Connecting to Google...",
}: {
  configured: boolean;
  idleLabel: string;
  pendingLabel?: string;
}) {
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  async function handleClick() {
    setError(null);

    let idToken: string | null;

    try {
      idToken = await signInWithGooglePopup();
    } catch {
      setError("Google sign-in failed. Try again.");
      return;
    }

    if (!idToken) {
      // The user closed the popup - not an error, just leave the form as is.
      return;
    }

    startTransition(async () => {
      const result = await signInWithGoogle(idToken);

      if (result.error) {
        setError(result.error);
      }
    });
  }

  return (
    <>
      <button
        type="button"
        onClick={handleClick}
        disabled={!configured || pending}
        className="flex h-16 w-full items-center justify-center gap-4 rounded-[1.5rem] border border-border bg-white px-6 text-base font-black text-foreground shadow-[0_12px_36px_-28px_rgba(0,30,98,0.45)] transition duration-200 hover:-translate-y-px hover:border-brand/25 hover:bg-brand-soft/35 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-brand/12 disabled:cursor-not-allowed disabled:opacity-60 sm:text-lg"
      >
        <GoogleMark />
        {pending ? pendingLabel : idleLabel}
      </button>

      {error ? <AuthFormMessage>{error}</AuthFormMessage> : null}
    </>
  );
}

export function AuthDivider() {
  return (
    <div className="flex items-center gap-4 py-2" aria-hidden="true">
      <span className="h-px flex-1 bg-border" />
      <span className="text-sm font-black text-brand/35">or</span>
      <span className="h-px flex-1 bg-border" />
    </div>
  );
}
