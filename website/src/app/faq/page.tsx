import type { Metadata } from "next";
import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";
import { getSiteContentWithFallback } from "@/lib/site-content";

export const metadata: Metadata = {
  title: "FAQ | Runiac",
  description:
    "Answers to common questions about Runiac — personalized running plans, XP progression, fair level-based leaderboards, streaks, and pricing.",
};

const containerStyle = {
  width: "calc(100vw - 3rem)",
  maxWidth: "72rem",
};

export default async function FaqPage() {
  const content = await getSiteContentWithFallback();
  const faqs = content.faqs;

  return (
    <>
      <Navbar />
      <main className="flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden">
        <section className="box-border w-full px-0 py-20 sm:py-24 lg:py-28">
          <div className="mx-auto" style={containerStyle}>
            <div className="max-w-3xl">
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand sm:text-sm">
                Frequently asked questions
              </p>
              <h1 className="mt-4 text-4xl font-semibold italic leading-[1.08] tracking-normal text-brand sm:text-5xl lg:text-6xl">
                Everything you need to know before your first run.
              </h1>
              <p className="mt-6 text-base leading-relaxed text-muted sm:text-lg">
                Short answers to the questions we hear most about plans,
                progression, fair competition, and pricing.
              </p>
            </div>

            <div className="mt-14 space-y-4">
              {faqs.map((faq) => (
                <details
                  key={faq.question}
                  className="group rounded-lg border border-border bg-white p-5 transition-shadow open:shadow-md sm:p-6"
                >
                  <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-base font-semibold text-foreground marker:content-none sm:text-lg">
                    <span>{faq.question}</span>
                    <span
                      className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-border text-brand transition-transform duration-200 group-open:rotate-45"
                      aria-hidden="true"
                    >
                      +
                    </span>
                  </summary>
                  <p className="mt-4 text-sm leading-relaxed text-muted sm:text-base">
                    {faq.answer}
                  </p>
                </details>
              ))}
            </div>

            <div className="mt-16 rounded-lg border border-border bg-background p-6 shadow-[0_24px_70px_-50px_rgba(0,30,98,0.36)] sm:p-8">
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand">
                Still have a question?
              </p>
              <h3 className="mt-3 text-2xl font-semibold text-foreground">
                We&apos;re happy to help.
              </h3>
              <p className="mt-3 max-w-2xl text-sm leading-relaxed text-muted sm:text-base">
                Reach out through the About page to get in touch with the team
                behind Runiac.
              </p>
              <a
                href="/about"
                className="mt-5 inline-flex rounded-full bg-brand px-5 py-2.5 text-sm font-bold text-white shadow-sm shadow-brand/10 transition-colors hover:bg-brand/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/35 focus-visible:ring-offset-4"
              >
                Contact us
              </a>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
