"use client";

// The scroll-driven "how it works" walkthrough on the home page.
//
// A client component because it animates on scroll: `useInView` starts each
// step as it arrives rather than on mount, so a visitor who lands mid-page does
// not miss the sequence.
//
// `useReducedMotion` is honoured throughout — with the OS preference set, the
// content appears without movement instead of animating. Every section on this
// site that animates follows the same rule.

import { useEffect, useRef, useState, type ReactNode } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import type { Variants } from "motion/react";

const iconProps = {
  className: "h-5 w-5",
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

const steps = [
  {
    n: "01",
    title: "SET YOUR GOAL",
    body: "Share your running experience, fitness level, and goal so Runiac can create a suitable starting point.",
    icon: (
      <svg {...iconProps}>
        <circle cx="12" cy="12" r="8" />
        <circle cx="12" cy="12" r="3" />
        <path d="M12 2v3" />
        <path d="M12 19v3" />
        <path d="M2 12h3" />
        <path d="M19 12h3" />
      </svg>
    ),
  },
  {
    n: "02",
    title: "FOLLOW YOUR PLAN",
    body: "Get a weekly running plan with balanced running days, rest days, and realistic progression.",
    icon: (
      <svg {...iconProps}>
        <rect x="3" y="4" width="18" height="17" rx="2" />
        <path d="M8 2v4" />
        <path d="M16 2v4" />
        <path d="M3 10h18" />
        <path d="m8 15 2 2 4-4" />
      </svg>
    ),
  },
  {
    n: "03",
    title: "TRACK YOUR RUN",
    body: "Record distance, pace, duration, and route through smartphone GPS or optional wearable data.",
    icon: (
      <svg {...iconProps}>
        <path d="M12 21s6-5.2 6-11a6 6 0 0 0-12 0c0 5.8 6 11 6 11Z" />
        <circle cx="12" cy="10" r="2" />
      </svg>
    ),
  },
  {
    n: "04",
    title: "UNDERSTAND YOUR RUN",
    body: "Review simple analysis and beginner-friendly feedback that explains what your running data means.",
    icon: (
      <svg {...iconProps}>
        <path d="M4 19V5" />
        <path d="M4 19h16" />
        <path d="m7 15 4-4 3 3 5-7" />
        <path d="M18 7h1v1" />
      </svg>
    ),
  },
  {
    n: "05",
    title: "BUILD STREAKS & EARN XP",
    body: "Complete planned runs, maintain consistency, and turn your effort into XP, levels, and visible progress.",
    icon: (
      <svg {...iconProps}>
        <path d="M12 22c4 0 7-2.8 7-6.8 0-3.1-1.8-5.2-4.5-7.8-.5 2.4-1.6 3.7-3.2 4.7.2-2.7-.9-5.3-3.1-7.5C7.7 8.3 5 10.8 5 15.2 5 19.2 8 22 12 22Z" />
      </svg>
    ),
  },
  {
    n: "06",
    title: "COMPETE FAIRLY",
    body: "Join level-based territorial leaderboards where you compete with nearby runners at a similar stage.",
    icon: (
      <svg {...iconProps}>
        <path d="M8 21h8" />
        <path d="M12 17v4" />
        <path d="M7 4h10v5a5 5 0 0 1-10 0V4Z" />
        <path d="M17 6h3a3 3 0 0 1-3 3" />
        <path d="M7 6H4a3 3 0 0 0 3 3" />
      </svg>
    ),
  },
];

const headerVariants: Variants = {
  hidden: {
    opacity: 0,
    y: 24,
    filter: "blur(5px)",
  },
  show: {
    opacity: 1,
    y: 0,
    filter: "blur(0px)",
    transition: {
      duration: 0.7,
      ease: [0.22, 1, 0.36, 1],
    },
  },
};

const stepListVariants: Variants = {
  hidden: {},
  show: {
    transition: {
      delayChildren: 0.18,
      staggerChildren: 0.11,
    },
  },
};

const stepItemVariants: Variants = {
  hidden: {
    opacity: 0,
    y: 34,
    scale: 0.965,
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

function StepArrow({
  className,
  direction = "right",
  active = false,
}: {
  className: string;
  direction?: "right" | "down";
  active?: boolean;
}) {
  return (
    <motion.span
      aria-hidden="true"
      animate={
        active
          ? {
              opacity: 1,
              color: "#f26a3d",
              x: direction === "right" ? [0, 4, 0] : 0,
              y: direction === "down" ? [0, 4, 0] : 0,
            }
          : {
              opacity: 0.72,
              color: "#4058b0",
              x: 0,
              y: 0,
            }
      }
      transition={{ duration: 0.58, ease: [0.22, 1, 0.36, 1] }}
      className={`pointer-events-none z-20 flex items-center justify-center text-[#4058b0] ${className}`}
    >
      <svg
        width={direction === "down" ? "16" : "30"}
        height={direction === "down" ? "42" : "16"}
        viewBox={direction === "down" ? "0 0 16 42" : "0 0 30 16"}
        fill="none"
      >
        {direction === "down" ? (
          <>
            <path
              d="M8 2v34"
              stroke="currentColor"
              strokeWidth="1.7"
              strokeLinecap="round"
              strokeDasharray="2 5"
            />
            <path
              d="m3.8 31.5 4.2 4.2 4.2-4.2"
              stroke="currentColor"
              strokeWidth="1.9"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </>
        ) : (
          <>
            <path
              d="M2 8h22"
              stroke="currentColor"
              strokeWidth="1.7"
              strokeLinecap="round"
              strokeDasharray="2 5"
            />
            <path
              d="m19.5 3.8 4.2 4.2-4.2 4.2"
              stroke="currentColor"
              strokeWidth="1.9"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </>
        )}
      </svg>
    </motion.span>
  );
}

function StepCard({
  step,
  index,
  active,
  reduceMotion,
}: {
  step: (typeof steps)[number] & { icon: ReactNode };
  index: number;
  active: boolean;
  reduceMotion: boolean;
}) {
  const isRowEndOnLarge = index === 2;
  const isLast = index === steps.length - 1;
  const activeCardClasses = active
    ? "border-[#4058b0]/45 shadow-[0_34px_90px_-48px_rgba(0,30,98,0.82)]"
    : "border-border shadow-[0_22px_70px_-48px_rgba(0,30,98,0.62)]";

  return (
    <motion.li
      className="relative min-w-0 pl-12 sm:pl-0"
      variants={reduceMotion ? undefined : stepItemVariants}
    >
      <span
        aria-hidden="true"
        className={`absolute left-[0.95rem] top-8 z-10 h-3 w-3 rounded-full border-2 border-white transition-all duration-500 sm:hidden ${
          active
            ? "scale-125 bg-[#4058b0] shadow-[0_0_0_7px_rgba(64,88,176,0.14)]"
            : "bg-accent shadow-[0_0_0_4px_rgba(242,106,61,0.12)]"
        }`}
      />
      {!isLast && (
        <StepArrow
          className="absolute left-[0.55rem] top-[calc(100%+0.25rem)] sm:hidden"
          direction="down"
          active={active}
        />
      )}
      {!isLast && (
        <StepArrow
          className={`absolute -right-6 top-[3.1rem] hidden sm:flex lg:hidden ${
            index % 2 === 1 ? "sm:hidden" : ""
          }`}
          active={active}
        />
      )}
      {!isLast && !isRowEndOnLarge && (
        <StepArrow
          className="absolute -right-6 top-[3.1rem] hidden lg:flex xl:hidden"
          active={active}
        />
      )}
      {!isLast && (
        <StepArrow
          className="absolute -right-6 top-[3.1rem] hidden xl:flex"
          active={active}
        />
      )}

      <motion.article
        animate={
          reduceMotion
            ? undefined
            : active
              ? { y: -5 }
              : { y: 0 }
        }
        transition={{ duration: 0.5, ease: [0.22, 1, 0.36, 1] }}
        className={`group flex h-full min-h-[18.5rem] min-w-0 flex-col rounded-lg border bg-white p-5 transition-all duration-500 sm:min-h-[19rem] sm:p-6 lg:hover:-translate-y-1 lg:hover:border-[#4058b0]/35 lg:hover:shadow-[0_30px_86px_-46px_rgba(0,30,98,0.76)] ${activeCardClasses}`}
      >
        <div className="flex items-center justify-between gap-3">
          <span
            className={`rounded-full px-3 py-1 text-xs font-bold tracking-[0.08em] transition-colors duration-500 group-hover:bg-[#4058b0] group-hover:text-white ${
              active ? "bg-[#4058b0] text-white" : "bg-brand-soft text-brand"
            }`}
          >
            {step.n}
          </span>
          <span
            className={`grid h-10 w-10 shrink-0 place-items-center rounded-full transition-colors duration-500 group-hover:bg-accent group-hover:text-white ${
              active ? "bg-accent text-white" : "bg-accent-soft text-accent"
            }`}
          >
            {step.icon}
          </span>
        </div>
        <h3
          className={`mt-6 break-words text-base font-bold uppercase leading-snug tracking-normal transition-colors duration-500 group-hover:text-brand ${
            active ? "text-brand" : "text-foreground"
          }`}
        >
          {step.title}
        </h3>
        <p className="mt-4 break-words text-sm leading-relaxed text-muted">
          {step.body}
        </p>
      </motion.article>
    </motion.li>
  );
}

export function BeginnerJourney() {
  const sectionRef = useRef(null);
  const isInView = useInView(sectionRef, {
    amount: 0.28,
    margin: "-8% 0px -12% 0px",
  });
  const reduceMotion = useReducedMotion();
  const show = Boolean(isInView || reduceMotion);
  const [activeStep, setActiveStep] = useState(0);

  useEffect(() => {
    if (!show || reduceMotion) {
      return;
    }

    const cycle = window.setInterval(() => {
      setActiveStep((current) => (current + 1) % steps.length);
    }, 1450);

    return () => window.clearInterval(cycle);
  }, [show, reduceMotion]);

  return (
    <section
      id="how-it-works"
      ref={sectionRef}
      className="relative w-full bg-background px-6 pb-20 pt-6 sm:pb-24 sm:pt-8 lg:pb-28 lg:pt-8"
    >
      <span id="journey" className="absolute -top-24" aria-hidden="true" />
      <div className="mx-auto max-w-[92rem]">
        <motion.header
          className="mx-auto mb-10 max-w-4xl text-center sm:mb-12 lg:mb-14"
          initial={reduceMotion ? false : "hidden"}
          animate={show ? "show" : "hidden"}
          variants={reduceMotion ? undefined : headerVariants}
        >
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-brand sm:text-sm">
            HOW RUNIAC WORKS
          </p>
          <h2 className="mx-auto mt-4 max-w-[19rem] overflow-hidden font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[1.65rem] font-normal uppercase leading-[1.04] tracking-normal text-[#4058b0] sm:max-w-none sm:text-6xl lg:text-7xl">
            <span className="block">FROM FIRST RUN</span>
            <span className="block">TO CONSISTENT</span>
            <span className="block">RUNNER.</span>
          </h2>
          <p className="mx-auto mt-6 max-w-[22rem] text-base leading-relaxed text-muted sm:max-w-3xl sm:text-lg">
            Runiac turns early running into a guided journey — plan, run,
            understand, level up, and stay motivated.
          </p>
        </motion.header>

        <div className="relative">
          <span
            aria-hidden="true"
            className="absolute left-[1.3rem] top-0 hidden h-full w-px bg-border/80 max-sm:block"
          />
          <span
            aria-hidden="true"
            className="absolute left-8 right-8 top-[3.35rem] hidden h-px bg-border/80 lg:block"
          />
          <span
            aria-hidden="true"
            className="absolute left-8 right-8 top-[calc(3.35rem+19rem+1.25rem)] hidden h-px bg-border/70 lg:block xl:hidden"
          />
          <motion.ol
            className="relative z-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6"
            initial={reduceMotion ? false : "hidden"}
            animate={show ? "show" : "hidden"}
            variants={reduceMotion ? undefined : stepListVariants}
          >
            {steps.map((step, index) => (
              <StepCard
                key={step.n}
                step={step}
                index={index}
                active={activeStep === index}
                reduceMotion={Boolean(reduceMotion)}
              />
            ))}
          </motion.ol>
        </div>
      </div>
    </section>
  );
}
