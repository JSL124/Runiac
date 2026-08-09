"use client";

// Hero-section newsletter signup. Calls the real `subscribeNewsletter`
// backend callable (see src/lib/newsletter.ts) instead of discarding the
// email locally. Keeps the pre-existing markup/Tailwind classes (input,
// button, aria-live status line) exactly as they were — only the submit
// behaviour changes.

import { FormEvent, useState } from "react";
import { subscribeToNewsletter } from "@/lib/newsletter";

type SignupState =
  | "idle"
  | "submitting"
  | "sent"
  | "already-subscribed"
  | "rate-limited"
  | "error";

const STATUS_MESSAGE: Record<SignupState, string> = {
  idle: "",
  submitting: "Submitting…",
  sent: "Thanks. Check your inbox to confirm your subscription.",
  "already-subscribed": "You’re already on the list — thanks for sticking around.",
  "rate-limited": "Too many attempts from this connection. Please try again in a bit.",
  error: "Something went wrong. Please try again.",
};

export function HeroEmailSignup() {
  const [email, setEmail] = useState("");
  // Honeypot: real users never see or fill this field. A bot's form-filler
  // typically does, so a non-empty value here is treated as spam server-side.
  const [website, setWebsite] = useState("");
  const [state, setState] = useState<SignupState>("idle");

  const isSubmitting = state === "submitting";

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (isSubmitting) {
      return;
    }

    setState("submitting");

    const result = await subscribeToNewsletter(email, website);

    if (!result.ok) {
      setState(result.reason === "invalid-email" ? "error" : result.reason);
      return;
    }

    setState(result.status === "already-subscribed" ? "already-subscribed" : "sent");
    setEmail("");
  }

  return (
    <div className="mx-auto mt-7 w-[calc(100vw-3rem)] max-w-[460px] text-left sm:w-full lg:mx-0">
      <form
        className="flex w-full flex-col gap-3 sm:flex-row"
        onSubmit={handleSubmit}
      >
        <label htmlFor="hero-email" className="sr-only">
          Email address
        </label>
        <input
          id="hero-email"
          name="email"
          type="email"
          required
          value={email}
          placeholder="you@example.com"
          disabled={isSubmitting}
          onChange={(event) => {
            setEmail(event.target.value);
            setState("idle");
          }}
          className="min-h-12 min-w-0 flex-1 rounded-full border border-brand/20 bg-white px-4 text-sm text-foreground outline-none transition-all duration-200 placeholder:text-muted/60 hover:border-brand/50 hover:shadow-[0_14px_34px_-22px_rgba(0,30,98,0.7)] hover:ring-4 hover:ring-brand/10 focus:border-brand focus:shadow-[0_14px_34px_-22px_rgba(0,30,98,0.85)] focus:ring-4 focus:ring-brand/15"
        />

        {/* Honeypot: visually hidden AND removed from the accessibility tree
            and tab order, so it never confuses a screen-reader or keyboard
            user, and never affects layout. Left unfilled by every real
            visitor. */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute h-0 w-0 overflow-hidden opacity-0"
        >
          <label htmlFor="hero-website">Leave this field empty</label>
          <input
            id="hero-website"
            name="website"
            type="text"
            tabIndex={-1}
            autoComplete="off"
            value={website}
            onChange={(event) => setWebsite(event.target.value)}
          />
        </div>

        <button
          type="submit"
          disabled={isSubmitting}
          className="min-h-12 rounded-full bg-accent px-6 text-sm font-semibold text-white shadow-[0_8px_20px_-14px_rgba(242,106,61,0.8)] transition-all duration-200 hover:-translate-y-0.5 hover:bg-accent/95 hover:shadow-[0_16px_34px_-18px_rgba(242,106,61,0.9)] active:translate-y-0 focus:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-70"
        >
          {isSubmitting ? "Submitting…" : "Notify Me"}
        </button>
      </form>
      <p
        className="mt-3 min-h-5 text-xs font-medium text-brand"
        aria-live="polite"
      >
        {STATUS_MESSAGE[state]}
      </p>
      <p className="mt-1 text-[0.7rem] leading-relaxed text-muted">
        By signing up you agree to receive occasional Runiac emails. See our{" "}
        <a href="/legal/privacy" className="font-semibold text-brand hover:underline">
          Privacy Policy
        </a>
        .
      </p>
    </div>
  );
}
