"use client";

// The home page's feature grid, grouped by what the runner is trying to do.
//
// Content is declared as [FeatureGroup] data at the top and rendered by one
// block below, so reordering or adding a feature is a data edit rather than a
// layout change.

import { useRef, type ReactNode } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import type { Variants } from "motion/react";

type FeatureGroup = {
  title: string;
  description: string;
  bullets: string[];
  icon: ReactNode;
  preview: ReactNode;
  emphasized?: boolean;
};

const iconProps = {
  width: 22,
  height: 22,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.85,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

const headerVariants: Variants = {
  hidden: {
    opacity: 0,
    y: 26,
    filter: "blur(5px)",
  },
  show: {
    opacity: 1,
    y: 0,
    filter: "blur(0px)",
    transition: {
      duration: 0.72,
      ease: [0.22, 1, 0.36, 1],
    },
  },
};

const gridVariants: Variants = {
  hidden: {},
  show: {
    transition: {
      delayChildren: 0.16,
      staggerChildren: 0.12,
    },
  },
};

const cardVariants: Variants = {
  hidden: {
    opacity: 0,
    y: 34,
    scale: 0.97,
    filter: "blur(6px)",
  },
  show: {
    opacity: 1,
    y: 0,
    scale: 1,
    filter: "blur(0px)",
    transition: {
      type: "spring",
      stiffness: 210,
      damping: 25,
      mass: 0.9,
    },
  },
};

function MockPanel({
  children,
  emphasized = false,
}: {
  children: ReactNode;
  emphasized?: boolean;
}) {
  return (
    <div
      className={`mt-7 rounded-2xl border p-4 ${
        emphasized
          ? "border-[#4058b0]/10 bg-white shadow-[0_22px_60px_-46px_rgba(64,88,176,0.5)]"
          : "border-border/80 bg-brand-soft/45"
      }`}
    >
      {children}
    </div>
  );
}

const featureGroups: FeatureGroup[] = [
  {
    title: "START SAFELY",
    description:
      "Personalized plans and reminders help beginners follow a realistic routine without doing too much too soon.",
    bullets: [
      "Beginner-focused onboarding",
      "Weekly running plan",
      "Running and rest reminders",
      "Overtraining-aware guidance",
    ],
    icon: (
      <svg {...iconProps}>
        <path d="M12 3 5 6v5c0 4.4 2.8 8.4 7 10 4.2-1.6 7-5.6 7-10V6l-7-3Z" />
        <path d="m9 12 2 2 4-5" />
      </svg>
    ),
    preview: (
      <MockPanel>
        <div className="flex items-center justify-between gap-3">
          <span className="text-xs font-bold uppercase tracking-[0.16em] text-[#4058b0]">
            Today&apos;s Plan
          </span>
          <span className="rounded-full bg-accent-soft px-2.5 py-1 text-[10px] font-bold uppercase tracking-[0.12em] text-accent">
            Guided
          </span>
        </div>
        <div className="mt-4 rounded-xl bg-white p-4 shadow-[0_14px_34px_-28px_rgba(0,30,98,0.65)]">
          <p className="text-lg font-bold text-foreground">Easy Run · 20 min</p>
          <p className="mt-2 text-sm text-muted">Rest day tomorrow</p>
          <div className="mt-4 rounded-full bg-brand-soft px-3 py-2 text-xs font-semibold text-[#4058b0]">
            Safe progression focus
          </div>
        </div>
      </MockPanel>
    ),
  },
  {
    title: "TRACK & UNDERSTAND",
    description:
      "GPS tracking and simple analysis turn each run into clear feedback, not confusing raw numbers.",
    bullets: [
      "GPS run tracking",
      "Distance, pace, duration, and route",
      "Beginner-friendly analysis",
      "Simple post-run summary",
    ],
    icon: (
      <svg {...iconProps}>
        <path d="M12 21s6-5.2 6-11a6 6 0 0 0-12 0c0 5.8 6 11 6 11Z" />
        <circle cx="12" cy="10" r="2" />
        <path d="M4 21h16" />
      </svg>
    ),
    preview: (
      <MockPanel>
        <div className="grid grid-cols-3 gap-2">
          {[
            ["Distance", "2.4 km"],
            ["Pace", "7'20\" / km"],
            ["Duration", "18 min"],
          ].map(([label, value]) => (
            <div key={label} className="rounded-xl bg-white p-3">
              <p className="text-[10px] font-semibold uppercase tracking-[0.12em] text-muted">
                {label}
              </p>
              <p className="mt-1 text-sm font-bold text-foreground">{value}</p>
            </div>
          ))}
        </div>
        <div className="mt-3 rounded-xl bg-white p-4">
          <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-[#4058b0]">
            Summary
          </p>
          <p className="mt-2 text-sm font-medium leading-relaxed text-foreground">
            You kept a steady pace today.
          </p>
        </div>
      </MockPanel>
    ),
  },
  {
    title: "STAY CONSISTENT",
    description:
      "Streaks, weekly goals, XP, and levels make progress visible even before performance improvements feel obvious.",
    bullets: [
      "Current streak",
      "Weekly consistency goal",
      "XP rewards",
      "Runner levels",
    ],
    emphasized: true,
    icon: (
      <svg {...iconProps}>
        <rect x="3" y="5" width="18" height="16" rx="2.5" />
        <path d="M8 3v4" />
        <path d="M16 3v4" />
        <path d="M3 10h18" />
        <path d="m8 15 2 2 4-4" />
        <path d="M17 16h.01" />
      </svg>
    ),
    preview: (
      <MockPanel emphasized>
        <div className="grid gap-3 sm:grid-cols-[0.85fr_1.15fr]">
          <div className="rounded-2xl bg-[#4058b0] p-4 text-white">
            <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-white/70">
              Current Streak
            </p>
            <p className="mt-3 text-4xl font-black leading-none">5</p>
            <p className="mt-1 text-sm font-semibold text-white/85">days</p>
          </div>
          <div className="space-y-3 rounded-2xl bg-brand-soft p-4">
            <div>
              <div className="flex items-center justify-between gap-3 text-xs font-bold text-foreground">
                <span>Weekly Goal</span>
                <span className="text-[#4058b0]">2 / 3 runs</span>
              </div>
              <div className="mt-2 h-2 rounded-full bg-white">
                <div className="h-full w-2/3 rounded-full bg-accent" />
              </div>
            </div>
            <div>
              <div className="flex items-center justify-between gap-3 text-xs font-bold text-foreground">
                <span>XP Progress</span>
                <span className="text-[#4058b0]">420 / 600 XP</span>
              </div>
              <div className="mt-2 h-2 rounded-full bg-white">
                <div className="h-full w-[70%] rounded-full bg-[#4058b0]" />
              </div>
              <p className="mt-2 text-xs font-semibold text-muted">
                to Level 4
              </p>
            </div>
          </div>
        </div>
      </MockPanel>
    ),
  },
  {
    title: "RUN TOGETHER",
    description:
      "Community routes, sharing cards, and level-based territorial leaderboards create fair motivation with nearby runners.",
    bullets: [
      "Community route sharing",
      "Social achievement cards",
      "Local leaderboard",
      "Same-level competition",
    ],
    icon: (
      <svg {...iconProps}>
        <path d="M8 21h8" />
        <path d="M12 17v4" />
        <path d="M7 4h10v5a5 5 0 0 1-10 0V4Z" />
        <path d="M17 6h3a3 3 0 0 1-3 3" />
        <path d="M7 6H4a3 3 0 0 0 3 3" />
      </svg>
    ),
    preview: (
      <MockPanel>
        <div className="flex items-center justify-between gap-3">
          <p className="text-xs font-bold uppercase tracking-[0.14em] text-[#4058b0]">
            Jurong East · Level 1-5
          </p>
          <span className="rounded-full bg-white px-2.5 py-1 text-[10px] font-bold uppercase tracking-[0.12em] text-accent">
            Local
          </span>
        </div>
        <div className="mt-4 space-y-2">
          {[
            ["1.", "Mina", "850 XP"],
            ["2.", "Alex", "790 XP"],
            ["3.", "You", "760 XP"],
          ].map(([rank, name, xp], index) => (
            <div
              key={name}
              className={`flex items-center justify-between rounded-xl px-3 py-2 text-sm font-semibold ${
                index === 2
                  ? "bg-[#4058b0] text-white"
                  : "bg-white text-foreground"
              }`}
            >
              <span className="flex items-center gap-2">
                <span
                  className={index === 2 ? "text-white/70" : "text-muted"}
                >
                  {rank}
                </span>
                {name}
              </span>
              <span className={index === 2 ? "text-white" : "text-[#4058b0]"}>
                {xp}
              </span>
            </div>
          ))}
        </div>
      </MockPanel>
    ),
  },
];

export function MvpFeatures() {
  const sectionRef = useRef(null);
  const reduceMotion = useReducedMotion();
  const isInView = useInView(sectionRef, {
    amount: 0.18,
    margin: "-8% 0px -12% 0px",
  });
  const show = Boolean(isInView || reduceMotion);

  return (
    <section
      id="features"
      ref={sectionRef}
      className="w-full px-6 py-24 sm:py-28 lg:py-32"
    >
      <div className="mx-auto max-w-[92rem]">
        <motion.header
          className="mx-auto mb-14 max-w-3xl text-center sm:mb-20"
          initial={reduceMotion ? false : "hidden"}
          animate={show ? "show" : "hidden"}
          variants={reduceMotion ? undefined : headerVariants}
        >
          <p className="mb-4 text-xs font-semibold uppercase tracking-[0.18em] text-brand sm:text-sm">
            CORE FEATURES
          </p>
          <h2 className="text-3xl font-semibold leading-[1.15] tracking-tight sm:text-4xl lg:text-5xl">
            <span className="font-['Sprintura_Demo',var(--font-inter),sans-serif] font-normal uppercase tracking-normal text-[#4058b0]">
              FEATURES BUILT FOR CONSISTENCY.
            </span>
          </h2>
          <p className="mt-5 text-base leading-relaxed text-muted sm:text-lg">
            Runiac brings together guidance, tracking, motivation, and fair
            competition to help beginners build a sustainable running habit.
          </p>
        </motion.header>

        <motion.div
          className="grid items-stretch gap-6 md:grid-cols-2"
          initial={reduceMotion ? false : "hidden"}
          animate={show ? "show" : "hidden"}
          variants={reduceMotion ? undefined : gridVariants}
        >
          {featureGroups.map((feature) => (
            <motion.article
              key={feature.title}
              variants={reduceMotion ? undefined : cardVariants}
              className={`group flex h-full min-w-0 flex-col rounded-2xl border bg-white p-6 transition-all duration-300 hover:-translate-y-0.5 sm:p-7 lg:p-8 ${
                feature.emphasized
                  ? "border-[#4058b0]/12 shadow-[0_34px_90px_-58px_rgba(64,88,176,0.56)]"
                  : "border-border shadow-[0_24px_70px_-54px_rgba(64,88,176,0.5)] hover:shadow-[0_28px_82px_-56px_rgba(64,88,176,0.62)]"
              }`}
              whileHover={reduceMotion ? undefined : { y: -5 }}
              transition={{ duration: 0.42, ease: [0.22, 1, 0.36, 1] }}
            >
              <div className="flex items-start justify-between gap-4">
                <span className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-brand-soft text-[#4058b0]">
                  {feature.icon}
                </span>
              </div>

              <div className="mt-6 flex flex-1 flex-col">
                <h3 className="text-xl font-black uppercase leading-tight tracking-normal text-[#4058b0] sm:text-2xl">
                  {feature.title}
                </h3>
                <p className="mt-3 max-w-2xl text-sm leading-relaxed text-muted sm:text-base">
                  {feature.description}
                </p>

                <ul className="mt-6 grid gap-2 text-sm font-semibold text-foreground sm:grid-cols-2">
                  {feature.bullets.map((bullet) => (
                    <li key={bullet} className="flex min-w-0 items-start gap-2">
                      <span
                        aria-hidden="true"
                        className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${
                          feature.emphasized ? "bg-accent" : "bg-[#4058b0]"
                        }`}
                      />
                      <span className="break-words">{bullet}</span>
                    </li>
                  ))}
                </ul>

                <div className="mt-auto">{feature.preview}</div>
              </div>
            </motion.article>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
