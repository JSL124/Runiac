"use client";

import { useState } from "react";
import { useFormStatus } from "react-dom";

// Shared field, message and button primitives for the account forms (sign in,
// sign up, reset password) so the three of them stay visually identical
// without triplicating the Tailwind classes.

const fieldClasses =
  "h-16 w-full rounded-[1.5rem] border border-border bg-brand-soft/65 px-5 text-base font-semibold text-foreground outline-none transition-colors duration-200 placeholder:text-muted/55 hover:border-brand/35 focus:border-brand focus:bg-white focus:ring-4 focus:ring-brand/10 disabled:cursor-not-allowed disabled:opacity-60";

export function AuthLabel({
  htmlFor,
  children,
}: {
  htmlFor: string;
  children: React.ReactNode;
}) {
  return (
    <label
      htmlFor={htmlFor}
      className="mb-2 block text-sm font-bold text-brand"
    >
      {children}
    </label>
  );
}

export function AuthEmailField({
  disabled,
  label = "Email",
  id = "email",
}: {
  disabled: boolean;
  label?: string;
  id?: string;
}) {
  return (
    <div>
      <AuthLabel htmlFor={id}>{label}</AuthLabel>
      <input
        id={id}
        name="email"
        type="email"
        autoComplete="email"
        required
        disabled={disabled}
        placeholder="you@example.com"
        className={fieldClasses}
      />
    </div>
  );
}

export function AuthPasswordField({
  id,
  name,
  label,
  autoComplete,
  disabled,
  placeholder,
  minLength,
}: {
  id: string;
  name: string;
  label: string;
  autoComplete: "current-password" | "new-password";
  disabled: boolean;
  placeholder: string;
  minLength?: number;
}) {
  const [showPassword, setShowPassword] = useState(false);

  return (
    <div>
      <AuthLabel htmlFor={id}>{label}</AuthLabel>
      <div className="relative">
        <input
          id={id}
          name={name}
          type={showPassword ? "text" : "password"}
          autoComplete={autoComplete}
          required
          minLength={minLength}
          disabled={disabled}
          placeholder={placeholder}
          className={`${fieldClasses} pr-14`}
        />
        <button
          type="button"
          onClick={() => setShowPassword((value) => !value)}
          aria-label={showPassword ? "Hide password" : "Show password"}
          aria-pressed={showPassword}
          className="absolute right-4 top-1/2 flex h-9 w-9 -translate-y-1/2 items-center justify-center rounded-full text-muted transition-colors hover:bg-white hover:text-brand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/30"
        >
          {showPassword ? (
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="h-5 w-5"
              aria-hidden="true"
            >
              <path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c6.5 0 10 6 10 6a17.6 17.6 0 0 1-2.16 3M6.6 6.6A17.6 17.6 0 0 0 2 10s3.5 6 10 6a9.12 9.12 0 0 0 4.5-1.2" />
              <path d="M9.9 9.9a3 3 0 0 0 4.2 4.2" />
              <path d="M2 2l20 20" />
            </svg>
          ) : (
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="h-5 w-5"
              aria-hidden="true"
            >
              <path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6-10-6-10-6Z" />
              <circle cx="12" cy="12" r="3" />
            </svg>
          )}
        </button>
      </div>
    </div>
  );
}

// One notice box for every inline message these forms show. `tone` only picks
// the colour; `role` decides whether screen readers interrupt ("alert" for
// failures, "status" for confirmations and configuration notices).
export function AuthFormMessage({
  children,
  role = "alert",
  tone = "warning",
}: {
  children: React.ReactNode;
  role?: "alert" | "status";
  tone?: "warning" | "success";
}) {
  const toneClasses =
    tone === "success"
      ? "border-brand/25 bg-brand-soft/70"
      : "border-accent/25 bg-accent-soft";

  return (
    <p
      role={role}
      className={`rounded-[1.25rem] border px-5 py-3.5 text-sm font-semibold leading-relaxed text-foreground ${toneClasses}`}
    >
      {children}
    </p>
  );
}

// Submit button wired to the enclosing form's pending state, so it disables
// itself for the duration of the server action.
export function AuthSubmitButton({
  disabled,
  idleLabel,
  pendingLabel,
}: {
  disabled: boolean;
  idleLabel: string;
  pendingLabel: string;
}) {
  const { pending } = useFormStatus();

  return (
    <button
      type="submit"
      disabled={pending || disabled}
      className="flex h-16 w-full items-center justify-center rounded-[1.5rem] bg-brand px-6 text-lg font-black text-white shadow-[0_18px_36px_-24px_rgba(0,30,98,0.7)] transition duration-200 hover:-translate-y-px hover:bg-brand/90 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-brand/25 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:translate-y-0"
    >
      {pending ? pendingLabel : idleLabel}
    </button>
  );
}
