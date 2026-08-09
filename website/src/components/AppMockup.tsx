// A fake Runiac screen, built in HTML, for the marketing pages.
//
// Rendered rather than screenshotted so it stays sharp at any size, needs no
// image assets, and can be restyled with the rest of the site. Each [Variant]
// is one app surface the page wants to show off.
//
// It only has to *look* like the app — nothing here is shared with the Flutter
// UI, so treat it as illustration and keep it honest about what the app does.

import type { ReactNode } from "react";

type Variant = "hero" | "streak" | "plan" | "feedback";

const StatusBar = () => (
  <div className="flex items-center justify-between px-5 pt-3 pb-1 text-[10px] font-medium text-muted">
    <span>9:41</span>
    <div className="flex items-center gap-1">
      <span className="h-1.5 w-1.5 rounded-full bg-muted/60" />
      <span className="h-1.5 w-1.5 rounded-full bg-muted/60" />
      <span className="h-1.5 w-1.5 rounded-full bg-muted/60" />
    </div>
  </div>
);

const PhoneFrame = ({ children }: { children: ReactNode }) => (
  <div className="relative mx-auto w-full max-w-[286px] rounded-[2.5rem] border border-border bg-white shadow-[0_30px_60px_-20px_rgba(0,30,98,0.28)] ring-1 ring-brand/10 sm:max-w-[320px]">
    <div className="absolute left-1/2 top-2 z-10 h-1.5 w-16 -translate-x-1/2 rounded-full bg-foreground/10" />
    <div className="overflow-hidden rounded-[2.5rem]">
      <StatusBar />
      <div className="px-5 pb-6 pt-2">{children}</div>
    </div>
  </div>
);

const HeroBody = () => (
  <div className="space-y-4">
    <div>
      <p className="text-[10px] font-semibold uppercase tracking-widest text-muted">
        Today
      </p>
      <h3 className="mt-1 text-lg font-semibold leading-tight text-foreground">
        Easy 20-min run
      </h3>
      <p className="mt-1 text-xs text-muted">
        Conversational pace. Stop early if you need to.
      </p>
    </div>

    <div className="rounded-2xl border border-border bg-brand-soft/60 p-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-base">🔥</span>
          <span className="text-sm font-semibold text-brand">7-day streak</span>
        </div>
        <span className="text-[10px] font-medium text-brand/70">Keep going</span>
      </div>
    </div>

    <div className="rounded-2xl border border-border p-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium text-muted">XP this week</span>
        <span className="text-xs font-semibold text-foreground">320 / 500</span>
      </div>
      <div className="mt-2 h-2 overflow-hidden rounded-full bg-border">
        <div
          className="h-full rounded-full bg-accent"
          style={{ width: "64%" }}
        />
      </div>
      <p className="mt-2 text-[10px] text-muted">
        +40 XP after today&apos;s run
      </p>
    </div>

    <button
      type="button"
      className="w-full rounded-full bg-brand py-2.5 text-xs font-semibold text-white"
    >
      Start run
    </button>
  </div>
);

const StreakBody = () => {
  const days = ["M", "T", "W", "T", "F", "S", "S"];
  const completed = [true, true, true, true, true, true, true];
  return (
    <div className="space-y-4">
      <p className="text-[10px] font-semibold uppercase tracking-widest text-muted">
        Streak
      </p>
      <div className="rounded-2xl bg-brand-soft p-5 text-center">
        <p className="text-5xl">🔥</p>
        <p className="mt-1 text-3xl font-bold text-brand">7 days</p>
        <p className="mt-1 text-xs text-muted">Your longest streak yet.</p>
      </div>
      <div className="flex items-center justify-between">
        {days.map((d, i) => (
          <div key={i} className="flex flex-col items-center gap-1.5">
            <span
              className={`grid h-7 w-7 place-items-center rounded-full text-[10px] font-semibold ${
                completed[i]
                  ? "bg-accent text-white"
                  : "bg-border text-muted"
              }`}
            >
              {completed[i] ? "✓" : ""}
            </span>
            <span className="text-[10px] text-muted">{d}</span>
          </div>
        ))}
      </div>
    </div>
  );
};

const PlanBody = () => {
  const plan = [
    { day: "Mon", title: "Easy 20 min", tag: "Run", active: true },
    { day: "Tue", title: "Rest day", tag: "Rest", active: false },
    { day: "Wed", title: "Walk-run 25 min", tag: "Run", active: false },
    { day: "Thu", title: "Rest day", tag: "Rest", active: false },
    { day: "Fri", title: "Easy 25 min", tag: "Run", active: false },
  ];
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-[10px] font-semibold uppercase tracking-widest text-muted">
          This week
        </p>
        <span className="text-[10px] font-medium text-brand">Week 3</span>
      </div>
      <div className="space-y-2">
        {plan.map((p) => (
          <div
            key={p.day}
            className={`flex items-center justify-between rounded-xl border px-3 py-2.5 ${
              p.active
                ? "border-brand/30 bg-brand-soft/60"
                : "border-border bg-white"
            }`}
          >
            <div className="flex items-center gap-3">
              <span className="grid h-8 w-8 place-items-center rounded-lg bg-white text-[10px] font-semibold text-muted ring-1 ring-border">
                {p.day}
              </span>
              <div>
                <p className="text-xs font-semibold text-foreground">
                  {p.title}
                </p>
                <p className="text-[10px] text-muted">{p.tag}</p>
              </div>
            </div>
            {p.active && (
              <span className="rounded-full bg-accent px-2 py-0.5 text-[9px] font-semibold uppercase tracking-wider text-white">
                Today
              </span>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};

const FeedbackBody = () => (
  <div className="space-y-4">
    <p className="text-[10px] font-semibold uppercase tracking-widest text-muted">
      Run complete
    </p>
    <div className="rounded-2xl bg-brand-soft p-4 text-center">
      <p className="text-2xl">🌱</p>
      <p className="mt-2 text-sm font-semibold text-brand">
        Nice and steady today.
      </p>
      <p className="mt-1 text-[11px] leading-relaxed text-muted">
        Your pace was even from start to finish — that&apos;s exactly how easy
        runs should feel.
      </p>
    </div>
    <div className="grid grid-cols-3 gap-2">
      <div className="rounded-xl border border-border p-2 text-center">
        <p className="text-[9px] uppercase tracking-wider text-muted">Time</p>
        <p className="mt-1 text-sm font-semibold text-foreground">22:14</p>
      </div>
      <div className="rounded-xl border border-border p-2 text-center">
        <p className="text-[9px] uppercase tracking-wider text-muted">XP</p>
        <p className="mt-1 text-sm font-semibold text-accent">+40</p>
      </div>
      <div className="rounded-xl border border-border p-2 text-center">
        <p className="text-[9px] uppercase tracking-wider text-muted">Streak</p>
        <p className="mt-1 text-sm font-semibold text-brand">7🔥</p>
      </div>
    </div>
    <button
      type="button"
      className="w-full rounded-full border border-brand/20 py-2.5 text-xs font-semibold text-brand"
    >
      See weekly plan
    </button>
  </div>
);

const bodies: Record<Variant, ReactNode> = {
  hero: <HeroBody />,
  streak: <StreakBody />,
  plan: <PlanBody />,
  feedback: <FeedbackBody />,
};

export function AppMockup({ variant = "hero" }: { variant?: Variant }) {
  return <PhoneFrame>{bodies[variant]}</PhoneFrame>;
}
