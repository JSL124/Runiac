// The public Features page.
//
// Long because it is the marketing content itself — each section is written out
// rather than generated from a list, so copy and layout can differ per feature.
// A fully static server component with no data fetching, which is what keeps it
// cheap to serve.
//
// Anything claimed here must match what the app actually does; this page is the
// public description of the product.

import type { Metadata } from "next";
import Image from "next/image";
import { AppMockup } from "@/components/AppMockup";
import { CtaButton } from "@/components/CtaButton";
import { FeatureHeroScrollWash } from "@/components/FeatureHeroScrollWash";
import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";

export const metadata: Metadata = {
  title: "Runiac Features - Built for beginner consistency.",
  description:
    "Explore Runiac features for beginner runners: activity tracking, weekly plans, reminders, streaks, XP progression, product previews, and fair future motivation layers.",
};

const habitLoop = [
  {
    step: "01",
    title: "Onboarding",
    body: "Runiac learns the runner's starting point, goal, and current confidence.",
  },
  {
    step: "02",
    title: "First Run",
    body: "The first session is simple, guided, and focused on completing the effort.",
  },
  {
    step: "03",
    title: "Feedback",
    body: "Post-run feedback translates activity data into plain beginner language.",
  },
  {
    step: "04",
    title: "Weekly Plan",
    body: "A realistic plan balances running days, rest days, and safe progression.",
  },
  {
    step: "05",
    title: "Reminder",
    body: "Running and rest reminders help the next action arrive at the right time.",
  },
  {
    step: "06",
    title: "Streak",
    body: "Consistency becomes visible before performance improvement feels obvious.",
  },
  {
    step: "07",
    title: "XP",
    body: "Completed runs, weekly consistency, and plan adherence become progress.",
  },
  {
    step: "08",
    title: "Next Run",
    body: "The loop turns one completed run into the next achievable step.",
  },
];

const mvpFeatures = [
  {
    id: "F1",
    title: "Activity Tracking",
    body: "Record distance, duration, pace, and route as the foundation for every run.",
  },
  {
    id: "F2",
    title: "Basic Running Analysis",
    body: "Explain running data in simple terms so beginners know what changed and why it matters.",
  },
  {
    id: "F3",
    title: "Weekly Running Plan",
    body: "Guide new runners with realistic weekly structure, rest days, and gradual progression.",
  },
  {
    id: "F4",
    title: "Running / Rest Reminders",
    body: "Bring users back to the next planned action without creating pressure or confusion.",
  },
  {
    id: "F6",
    title: "Streak & Consistency",
    body: "Show regular effort clearly, even when pace or distance has not improved yet.",
  },
  {
    id: "F9",
    title: "XP & Level Progression",
    body: "Reward completed runs, plan adherence, streak continuation, and weekly consistency.",
  },
];

const uiPreviews = [
  {
    title: "Weekly Plan UI",
    body: "Shows what to do this week without making beginners design their own training structure.",
    variant: "plan" as const,
  },
  {
    title: "Streak + XP UI",
    body: "Makes small wins visible so effort feels rewarding before performance changes are obvious.",
    variant: "streak" as const,
  },
  {
    title: "Post-run Feedback UI",
    body: "Turns the completed run into supportive reflection instead of a wall of raw metrics.",
    variant: "feedback" as const,
  },
];

const phaseTwoFeatures = [
  {
    id: "F5",
    title: "Social Sharing",
    body: "Share selected achievements and progress moments with confirmation and control.",
  },
  {
    id: "F7",
    title: "Community Route Sharing",
    body: "Discover beginner-friendly routes from local runners with privacy-aware sharing.",
  },
  {
    id: "F8",
    title: "Territorial Leaderboard",
    body: "Compete locally by level division, not against every runner in one global table.",
  },
  {
    id: "F10",
    title: "AI-assisted Summary",
    body: "Create richer plain-language post-run reflections without medical diagnosis claims.",
  },
];

const trustItems = [
  {
    title: "Firebase Auth",
    body: "Secures user identity before activity, progress, and profile data are stored.",
  },
  {
    title: "Cloud Firestore",
    body: "Stores activity records, weekly progress, streaks, XP, and profile state.",
  },
  {
    title: "Cloud Functions validation",
    body: "Keeps XP, streaks, and leaderboard updates server-side instead of trusting the client.",
  },
  {
    title: "FCM reminders",
    body: "Delivers running and rest reminders that support the user's planned routine.",
  },
];

const comparisonRows = [
  {
    traditional: "Focus on pace, splits, and advanced performance data.",
    runiac: "Focus on consistency, safe progression, and visible beginner progress.",
  },
  {
    traditional: "Show raw post-run numbers that beginners may not know how to interpret.",
    runiac: "Translate run data into short, supportive feedback that explains what happened.",
  },
  {
    traditional: "Push users into broad rankings where beginners compare with advanced runners.",
    runiac: "Use fair, level-based local competition so motivation stays achievable.",
  },
  {
    traditional: "Treat missed runs as gaps in a training log.",
    runiac: "Use reminders, streaks, XP, and weekly plans to help users return to the habit loop.",
  },
];

const freeItems = [
  "GPS run tracking",
  "Basic running analysis",
  "Weekly running plan",
  "Running and rest reminders",
  "Streak tracking",
  "XP progression",
];

const premiumItems = [
  "Advanced analytics",
  "Goal preparation for 5K, 10K, 21K, and 42K",
  "Enhanced post-run summaries",
  "Advanced route filters",
  "Premium sharing cards",
  "Profile frames and badge styles",
];

function SectionHeader({
  eyebrow,
  title,
  lead,
}: {
  eyebrow: string;
  title: string;
  lead: string;
}) {
  return (
    <header className="mx-auto mb-12 max-w-4xl text-center sm:mb-16">
      <p className="text-xs font-semibold uppercase tracking-[0.22em] text-brand sm:text-sm">
        {eyebrow}
      </p>
      <h2 className="mt-4 break-words font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[1.65rem] font-normal uppercase leading-[1.05] tracking-normal text-[#4058b0] sm:text-5xl lg:text-6xl">
        {title}
      </h2>
      <p className="mx-auto mt-5 max-w-3xl text-base leading-relaxed text-muted sm:text-lg">
        {lead}
      </p>
    </header>
  );
}

function FeatureHero() {
  return (
    <section
      id="features-top"
      className="relative isolate flex min-h-[calc(100svh-5.75rem)] w-full overflow-hidden bg-brand text-white"
    >
      <Image
        src="/feature-subscription-runners.jpeg"
        alt="A friendly group of runners training together"
        fill
        priority
        sizes="100vw"
        className="-z-30 object-cover object-[center_38%]"
      />
      <div
        aria-hidden="true"
        className="absolute inset-0 -z-20 bg-[linear-gradient(180deg,rgba(0,16,20,0.84)_0%,rgba(0,30,98,0.78)_43%,rgba(242,106,61,0.82)_100%)]"
      />
      <div
        aria-hidden="true"
        className="absolute inset-0 -z-10 bg-[radial-gradient(circle_at_78%_35%,rgba(255,255,255,0.18),transparent_28%),radial-gradient(circle_at_18%_78%,rgba(242,106,61,0.32),transparent_34%)]"
      />
      <FeatureHeroScrollWash />

      <div className="mx-6 flex w-[calc(100vw-3rem)] max-w-[21.375rem] -translate-y-8 flex-col items-center justify-center self-center py-16 text-center sm:mx-auto sm:max-w-[92rem] sm:-translate-y-10 sm:py-20 lg:-translate-y-14 lg:py-24">
        <h1 className="max-w-[21rem] break-words font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[2rem] font-normal uppercase leading-[1.04] tracking-normal text-white drop-shadow-[0_20px_48px_rgba(0,0,0,0.35)] sm:max-w-5xl sm:text-6xl lg:text-7xl">
          <span className="block">Keep going</span>
          <span className="block">with more</span>
          <span className="block">clarity.</span>
        </h1>

        <p className="mx-auto mt-7 max-w-3xl break-words text-base leading-relaxed text-white/86 drop-shadow-[0_10px_28px_rgba(0,0,0,0.25)] sm:text-xl">
          Premium turns goals, trends, and post-run reflection into clearer next
          steps while keeping competition fair for every runner.
        </p>

        <div className="mt-9 flex justify-center">
          <CtaButton
            href="/pricing"
            variant="primary"
            className="w-full rounded-lg px-8 py-4 text-base font-semibold sm:w-auto sm:text-lg"
          >
            Unlock Runiac Premium
          </CtaButton>
        </div>
      </div>
    </section>
  );
}

function HabitLoopSection() {
  return (
    <section
      id="habit-loop"
      className="w-full bg-brand-soft/40 px-6 py-24 sm:py-28 lg:py-32"
    >
      <div className="mx-auto max-w-[92rem]">
        <SectionHeader
          eyebrow="Beginner habit loop"
          title="One run leads to the next."
          lead="The feature set is designed as a repeatable loop, so beginners always know what just happened and what to do next."
        />

        <ol className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {habitLoop.map((item) => (
            <li
              key={item.step}
              className="min-w-0 rounded-lg border border-border bg-white p-5 shadow-[0_22px_70px_-54px_rgba(64,88,176,0.5)]"
            >
              <span className="inline-flex rounded-full bg-accent-soft px-3 py-1 text-xs font-bold text-accent">
                {item.step}
              </span>
              <h3 className="mt-5 break-words text-lg font-black uppercase leading-tight text-brand">
                {item.title}
              </h3>
              <p className="mt-3 text-sm leading-relaxed text-muted">
                {item.body}
              </p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}

function MvpFeatureSection() {
  return (
    <section id="mvp-features" className="w-full px-6 py-24 sm:py-28 lg:py-32">
      <div className="mx-auto max-w-[92rem]">
        <SectionHeader
          eyebrow="MVP features"
          title="Available in MVP demo."
          lead="These are the core features that make Runiac useful for a beginner's first running habit."
        />

        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
          {mvpFeatures.map((feature) => (
            <article
              key={feature.id}
              className="flex min-h-[17rem] min-w-0 flex-col rounded-lg border border-border bg-white p-6 shadow-[0_24px_70px_-54px_rgba(64,88,176,0.5)] transition-all duration-200 hover:-translate-y-0.5 hover:border-[#4058b0]/35 hover:shadow-[0_30px_84px_-56px_rgba(64,88,176,0.66)]"
            >
              <div className="flex items-start justify-between gap-4">
                <span className="rounded-full bg-brand-soft px-3 py-1 text-xs font-black text-brand">
                  {feature.id}
                </span>
                <span className="rounded-full bg-accent-soft px-3 py-1 text-[10px] font-bold uppercase tracking-[0.12em] text-accent">
                  MVP
                </span>
              </div>
              <h3 className="mt-8 break-words text-2xl font-black uppercase leading-tight text-[#4058b0]">
                {feature.title}
              </h3>
              <p className="mt-4 text-base leading-relaxed text-muted">
                {feature.body}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function ProductPreviewSection() {
  return (
    <section
      id="product-preview"
      className="w-full bg-brand px-6 py-24 text-white sm:py-28 lg:py-32"
    >
      <div className="mx-auto max-w-[92rem]">
        <header className="mx-auto mb-14 max-w-4xl text-center">
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-white/70 sm:text-sm">
            Product UI preview
          </p>
          <h2 className="mt-4 break-words font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[2.15rem] font-normal uppercase leading-[1.04] tracking-normal text-white sm:text-5xl lg:text-6xl">
            Simple screens for the next run.
          </h2>
          <p className="mx-auto mt-5 max-w-3xl text-base leading-relaxed text-white/75 sm:text-lg">
            The product interface should feel clear, motivating, and focused on
            what a beginner needs today.
          </p>
        </header>

        <div className="grid gap-8 lg:grid-cols-3">
          {uiPreviews.map((preview) => (
            <article
              key={preview.title}
              className="min-w-0 rounded-lg border border-white/12 bg-white/[0.06] p-6 backdrop-blur"
            >
              <div className="min-h-[30rem]">
                <AppMockup variant={preview.variant} />
              </div>
              <h3 className="mt-7 break-words text-xl font-black uppercase leading-tight text-white">
                {preview.title}
              </h3>
              <p className="mt-3 text-sm leading-relaxed text-white/72">
                {preview.body}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function PricingTeaserSection() {
  return (
    <section
      id="feature-pricing"
      className="w-full bg-background px-6 py-24 sm:py-28 lg:py-32"
    >
      <div className="mx-auto max-w-[92rem]">
        <SectionHeader
          eyebrow="Free and premium direction"
          title="Start free. Upgrade when ready."
          lead="Runiac keeps the core habit-forming experience free. Premium adds deeper insight and richer expression, not unfair competition advantages."
        />

        <div className="grid gap-6 lg:grid-cols-2">
          <article className="min-w-0 rounded-lg border border-border bg-white p-6 shadow-[0_24px_70px_-54px_rgba(64,88,176,0.48)] sm:p-8">
            <span className="rounded-full bg-brand-soft px-3 py-1 text-xs font-black uppercase tracking-[0.12em] text-brand">
              Free
            </span>
            <h3 className="mt-6 text-3xl font-black uppercase leading-tight text-[#4058b0]">
              Core habit loop.
            </h3>
            <ul className="mt-6 grid gap-3 text-sm font-semibold text-foreground sm:grid-cols-2">
              {freeItems.map((item) => (
                <li key={item} className="flex min-w-0 items-start gap-2">
                  <span
                    aria-hidden="true"
                    className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-accent"
                  />
                  <span className="break-words">{item}</span>
                </li>
              ))}
            </ul>
          </article>

          <article className="min-w-0 rounded-lg border border-[#4058b0]/20 bg-brand-soft/70 p-6 shadow-[0_24px_70px_-54px_rgba(64,88,176,0.55)] sm:p-8">
            <span className="rounded-full bg-white px-3 py-1 text-xs font-black uppercase tracking-[0.12em] text-brand">
              Premium
            </span>
            <h3 className="mt-6 text-3xl font-black uppercase leading-tight text-[#4058b0]">
              Deeper insight.
            </h3>
            <ul className="mt-6 grid gap-3 text-sm font-semibold text-foreground sm:grid-cols-2">
              {premiumItems.map((item) => (
                <li key={item} className="flex min-w-0 items-start gap-2">
                  <span
                    aria-hidden="true"
                    className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-[#4058b0]"
                  />
                  <span className="break-words">{item}</span>
                </li>
              ))}
            </ul>
          </article>
        </div>

        <p className="mx-auto mt-8 max-w-3xl text-center text-sm font-semibold leading-relaxed text-muted">
          Premium gives deeper insight, not unfair ranking advantages. It never
          adds extra XP, ranking boosts, or exclusive competitive information.
        </p>
      </div>
    </section>
  );
}

function PhaseTwoSection() {
  return (
    <section id="phase-2" className="w-full px-6 py-24 sm:py-28 lg:py-32">
      <div className="mx-auto max-w-[92rem]">
        <SectionHeader
          eyebrow="Phase 2 preview"
          title="Future motivation layer."
          lead="These features show the product vision beyond the MVP demo while keeping fair competition and beginner confidence protected."
        />

        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-4">
          {phaseTwoFeatures.map((feature) => (
            <article
              key={feature.id}
              className="min-w-0 rounded-lg border border-border bg-white p-6"
            >
              <span className="rounded-full bg-brand-soft px-3 py-1 text-xs font-black text-brand">
                {feature.id}
              </span>
              <h3 className="mt-6 break-words text-xl font-black uppercase leading-tight text-[#4058b0]">
                {feature.title}
              </h3>
              <p className="mt-4 text-sm leading-relaxed text-muted">
                {feature.body}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function TrustSection() {
  return (
    <section
      id="feature-trust"
      className="w-full bg-brand-soft/45 px-6 py-24 sm:py-28 lg:py-32"
    >
      <div className="mx-auto max-w-[92rem]">
        <SectionHeader
          eyebrow="Trust & integrity"
          title="Progress should be credible."
          lead="Runiac's technical plan keeps identity, activity records, reminders, XP, and validation in the right parts of the Firebase stack."
        />

        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-4">
          {trustItems.map((item) => (
            <article
              key={item.title}
              className="min-w-0 rounded-lg border border-border bg-white p-6 shadow-sm"
            >
              <h3 className="break-words text-lg font-black uppercase leading-tight text-brand">
                {item.title}
              </h3>
              <p className="mt-4 text-sm leading-relaxed text-muted">
                {item.body}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function DifferenceSection() {
  return (
    <section
      id="runiac-difference"
      className="w-full bg-background px-6 py-24 sm:py-28 lg:py-32"
    >
      <div className="mx-auto max-w-[92rem]">
        <SectionHeader
          eyebrow="Why Runiac feels different"
          title="Built for retention, not pressure."
          lead="Traditional running apps are useful, but beginners often need a product that helps them keep returning."
        />

        <div className="overflow-hidden rounded-lg border border-border bg-white shadow-[0_24px_70px_-54px_rgba(64,88,176,0.52)]">
          <div className="grid bg-brand text-sm font-black uppercase tracking-[0.12em] text-white md:grid-cols-2">
            <div className="border-b border-white/15 p-5 md:border-b-0 md:border-r">
              Traditional apps
            </div>
            <div className="p-5">Runiac</div>
          </div>
          {comparisonRows.map((row) => (
            <div
              key={row.traditional}
              className="grid border-t border-border md:grid-cols-2"
            >
              <div className="border-b border-border p-5 text-sm leading-relaxed text-muted md:border-b-0 md:border-r">
                {row.traditional}
              </div>
              <div className="p-5 text-sm font-semibold leading-relaxed text-foreground">
                {row.runiac}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function FeatureFinalCta() {
  return (
    <section id="features-cta" className="w-full px-6 py-24 sm:py-28">
      <div className="mx-auto max-w-6xl rounded-3xl bg-brand px-8 py-20 text-center text-white shadow-[0_30px_80px_-40px_rgba(0,30,98,0.65)] sm:px-12 sm:py-24">
        <p className="text-xs font-semibold uppercase tracking-[0.2em] text-white/70">
          Start small. Keep moving.
        </p>
        <h2 className="mx-auto mt-4 max-w-3xl text-3xl font-semibold leading-[1.15] tracking-tight sm:text-4xl lg:text-5xl">
          Try the Runiac habit loop from plan to progress.
        </h2>
        <p className="mx-auto mt-5 max-w-2xl text-sm leading-relaxed text-white/80 sm:text-base">
          The first version focuses on the features that help beginners return
          for the next run.
        </p>
        <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
          <CtaButton href="/#cta" variant="primary" className="px-7 py-3.5">
            View Prototype
          </CtaButton>
          <CtaButton
            href="/pricing"
            variant="ghost"
            className="border-white/30 px-7 py-3.5 text-white hover:bg-white/10"
          >
            Compare Free and Premium
          </CtaButton>
        </div>
      </div>
    </section>
  );
}

export default function FeaturesPage() {
  return (
    <>
      <Navbar />
      <main className="flex w-full flex-1 flex-col overflow-x-hidden">
        <FeatureHero />
        <HabitLoopSection />
        <MvpFeatureSection />
        <ProductPreviewSection />
        <PricingTeaserSection />
        <PhaseTwoSection />
        <TrustSection />
        <DifferenceSection />
        <FeatureFinalCta />
      </main>
      <Footer />
    </>
  );
}
