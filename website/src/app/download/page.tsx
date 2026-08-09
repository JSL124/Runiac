import type { Metadata } from "next";
import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";
import { getSiteContentWithFallback } from "@/lib/site-content";

export const metadata: Metadata = {
  title: "Download Runiac",
  description:
    "Download Runiac, the beginner-focused running app with personalized plans, XP progression, and fair level-based leaderboards.",
};

const containerStyle = {
  width: "calc(100vw - 3rem)",
  maxWidth: "72rem",
};

export default async function DownloadPage() {
  const content = await getSiteContentWithFallback();
  const { download } = content;

  return (
    <>
      <Navbar />
      <main className="flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden">
        <section className="box-border w-full px-0 py-20 sm:py-24 lg:py-28">
          <div className="mx-auto" style={containerStyle}>
            <div className="grid gap-5 sm:grid-cols-2">
              <div className="rounded-lg border border-border bg-white p-6 shadow-[0_24px_70px_-50px_rgba(0,30,98,0.36)] sm:p-8">
                <h2 className="text-2xl font-semibold text-foreground">
                  Android
                </h2>
                <p className="mt-3 text-sm leading-relaxed text-muted sm:text-base">
                  Install Runiac directly on your Android device.
                </p>
                <a
                  href={download.android.apkUrl}
                  className="mt-6 inline-flex rounded-full bg-brand px-5 py-2.5 text-sm font-bold text-white shadow-sm shadow-brand/10 transition-colors hover:bg-brand/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/35 focus-visible:ring-offset-4"
                >
                  Download APK
                </a>
                <p className="mt-3 text-xs leading-relaxed text-muted">
                  {download.android.note}
                </p>
              </div>

              <div className="rounded-lg border border-dashed border-border bg-brand-soft/40 p-6 sm:p-8">
                <div className="flex items-center justify-between gap-4">
                  <h2 className="text-2xl font-semibold text-foreground">
                    iOS
                  </h2>
                  <span className="inline-flex shrink-0 rounded-full bg-brand-soft px-3 py-1 text-xs font-semibold uppercase tracking-[0.1em] text-brand">
                    {download.ios.badgeLabel}
                  </span>
                </div>
                <p className="mt-3 text-sm leading-relaxed text-muted sm:text-base">
                  {download.ios.reason}
                </p>
              </div>
            </div>

            <div className="mt-16">
              <h2 className="text-2xl font-semibold text-foreground sm:text-3xl">
                Install in 3 steps
              </h2>
              <div className="mt-8 grid gap-5 sm:grid-cols-3">
                {download.steps.map((step, index) => (
                  <div
                    key={step.title}
                    className="rounded-lg border border-border bg-white p-6"
                  >
                    <span className="flex h-8 w-8 items-center justify-center rounded-full bg-brand text-sm font-bold text-white">
                      {index + 1}
                    </span>
                    <h3 className="mt-4 text-lg font-semibold text-foreground">
                      {step.title}
                    </h3>
                    <p className="mt-2 text-sm leading-relaxed text-muted">
                      {step.body}
                    </p>
                  </div>
                ))}
              </div>
            </div>

            <div className="mt-16 rounded-lg border border-border bg-background p-6 shadow-[0_24px_70px_-50px_rgba(0,30,98,0.36)] sm:p-8">
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand">
                System requirements
              </p>
              <h3 className="mt-3 text-2xl font-semibold text-foreground">
                Before you install
              </h3>
              <ul className="mt-5 space-y-2 text-sm leading-relaxed text-muted sm:text-base">
                {download.requirements.map((requirement) => (
                  <li key={requirement}>{requirement}</li>
                ))}
              </ul>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
