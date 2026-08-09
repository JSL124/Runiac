import type { ReactNode } from "react";

export type LegalSection = {
  heading: string;
  body: ReactNode;
};

export type LegalDocumentProps = {
  eyebrow: string;
  title: string;
  effectiveDate: string;
  intro: string;
  sections: LegalSection[];
};

const containerStyle = {
  width: "calc(100vw - 3rem)",
  maxWidth: "72rem",
};

export function LegalDocument({
  eyebrow,
  title,
  effectiveDate,
  intro,
  sections,
}: LegalDocumentProps) {
  return (
    <section className="box-border w-full px-0 py-20 sm:py-24 lg:py-28">
      <div className="mx-auto" style={containerStyle}>
        <div className="max-w-3xl">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand sm:text-sm">
            {eyebrow}
          </p>
          <h1 className="mt-4 text-4xl font-semibold italic leading-[1.08] tracking-normal text-brand sm:text-5xl lg:text-6xl">
            {title}
          </h1>
          <p className="mt-6 text-sm font-semibold text-muted">
            Effective date: {effectiveDate}
          </p>
          <p className="mt-4 text-base leading-relaxed text-muted sm:text-lg">
            {intro}
          </p>
        </div>

        <div className="mt-12 max-w-3xl rounded-lg border border-border bg-brand-soft p-5 sm:p-6">
          <p className="text-sm leading-relaxed text-muted">
            Runiac is a Final Year Project. This document was prepared for that
            project and is provided for transparency — it is not legal advice.
          </p>
        </div>

        <div className="mt-12 max-w-3xl space-y-10">
          {sections.map((section) => (
            <div key={section.heading}>
              <h2 className="text-2xl font-semibold text-foreground">
                {section.heading}
              </h2>
              <div className="mt-3 space-y-3 text-sm leading-relaxed text-muted sm:text-base">
                {section.body}
              </div>
            </div>
          ))}
        </div>

        <div className="mt-16 max-w-3xl rounded-lg border border-border bg-white p-6 shadow-[0_24px_70px_-50px_rgba(0,30,98,0.36)] sm:p-8">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand">
            Questions about this document?
          </p>
          <h3 className="mt-3 text-2xl font-semibold text-foreground">
            Get in touch.
          </h3>
          <p className="mt-3 text-sm leading-relaxed text-muted sm:text-base">
            Email{" "}
            <a
              className="font-semibold text-brand hover:underline"
              href="mailto:admin@runiac.app"
            >
              admin@runiac.app
            </a>{" "}
            and we will respond as soon as we can.
          </p>
        </div>
      </div>
    </section>
  );
}
