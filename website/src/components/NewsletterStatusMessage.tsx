// Shared, presentational body for the three static newsletter redirect
// targets (confirmed / unsubscribed / invalid — see src/app/newsletter/*).
// These pages are the redirect destination for links sent by the backend
// email pipeline, so they must render as pure static markup: no Firestore
// read, no Firebase Admin credentials, nothing that can fail if the backend
// or a service account is unreachable.

import Link from "next/link";

const containerStyle = {
  width: "calc(100vw - 3rem)",
  maxWidth: "34rem",
};

export type NewsletterStatusTone = "success" | "neutral" | "warn";

const TONE_EYEBROW_STYLES: Record<NewsletterStatusTone, string> = {
  success: "text-brand",
  neutral: "text-brand",
  warn: "text-accent",
};

export function NewsletterStatusMessage({
  eyebrow,
  title,
  description,
  tone = "neutral",
}: {
  eyebrow: string;
  title: string;
  description: string;
  tone?: NewsletterStatusTone;
}) {
  return (
    <section className="box-border flex w-full flex-1 items-center justify-center px-0 py-24 sm:py-32">
      <div className="mx-auto text-center" style={containerStyle}>
        <p
          className={`text-xs font-semibold uppercase tracking-[0.18em] sm:text-sm ${TONE_EYEBROW_STYLES[tone]}`}
        >
          {eyebrow}
        </p>
        <h1 className="mt-4 text-3xl font-semibold italic leading-[1.1] tracking-normal text-brand sm:text-4xl">
          {title}
        </h1>
        <p className="mt-5 text-base leading-relaxed text-muted sm:text-lg">
          {description}
        </p>
        <div className="mt-10 flex flex-col items-center gap-3 sm:flex-row sm:justify-center">
          <Link
            href="/"
            className="inline-flex h-11 items-center justify-center rounded-full bg-accent px-6 text-sm font-semibold text-white transition-colors duration-150 hover:bg-accent/90"
          >
            Back to Runiac
          </Link>
          <a
            href="mailto:admin@runiac.app"
            className="inline-flex h-11 items-center justify-center rounded-full border border-border px-6 text-sm font-semibold text-brand transition-colors duration-150 hover:bg-brand-soft/60"
          >
            Contact us
          </a>
        </div>
      </div>
    </section>
  );
}
