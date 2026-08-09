"use client";

// The home-page section about the post-run summary.
//
// Follows the shared highlight shape (phone frame + copy, animated on scroll)
// and takes its content as a [SitePostRunSummary] so it stays editable from the
// admin console.

import { useRef } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import { CtaButton } from "./CtaButton";
import { IphoneFrame } from "./IphoneFrame";
import type { SitePostRunSummary } from "@/lib/site-highlight";

const summaryStats = [
  ["Distance", "2.4 km"],
  ["Pace", "7'20\" / km"],
  ["Duration", "18 min"],
  ["Plan", "Completed"],
];

const wentWell = ["Plan completed", "Steady pace", "Streak continued"];
const nextFocus = ["Keep the same rhythm", "Avoid increasing intensity too fast"];

function CheckMark() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      aria-hidden="true"
      className="shrink-0"
    >
      <path
        d="m3.4 8.1 3 3L12.7 4.8"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function SummaryInsightCard({
  title,
  items,
  accent = false,
}: {
  title: string;
  items: string[];
  accent?: boolean;
}) {
  return (
    <div className="rounded-lg border border-white/80 bg-white/95 p-3 shadow-[0_18px_50px_-40px_rgba(0,30,98,0.55)] backdrop-blur">
      <p
        className={`text-[10px] font-black uppercase tracking-[0.18em] ${
          accent ? "text-accent" : "text-[#4058b0]"
        }`}
      >
        {title}
      </p>
      <div className="mt-2 space-y-1.5">
        {items.map((item) => (
          <div key={item} className="flex items-start gap-2">
            <span
              className={`mt-0.5 grid h-4 w-4 place-items-center rounded-full ${
                accent ? "bg-accent-soft text-accent" : "bg-brand-soft text-[#4058b0]"
              }`}
            >
              <CheckMark />
            </span>
            <p className="text-xs font-bold leading-snug text-foreground sm:text-sm">
              {item}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}

function PostRunSummaryMockup({ show }: { show: boolean }) {
  const reduceMotion = useReducedMotion();

  return (
    <div className="relative mx-auto w-full min-w-0 max-w-[32rem] overflow-hidden py-2 sm:overflow-visible lg:max-w-[35rem]">
      <div
        aria-hidden="true"
        className="absolute inset-x-6 bottom-4 top-10 rounded-lg bg-brand-soft/75 shadow-[0_34px_90px_-62px_rgba(0,30,98,0.7)] sm:inset-x-10"
      />

      <div className="relative mx-auto w-full max-w-[26.5rem] overflow-hidden rounded-lg border border-border/80 bg-white shadow-[0_34px_90px_-54px_rgba(0,30,98,0.66)]">
        <div className="bg-[#4058b0] px-5 pb-3.5 pt-4 text-white">
          <div className="mx-auto mb-3 h-1.5 w-14 rounded-full bg-white/28" />
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-[11px] font-black uppercase tracking-[0.18em] text-white/72">
                Post-run review
              </p>
              <h3 className="mt-1.5 text-[1.45rem] font-black leading-tight">
                Today’s Run Summary
              </h3>
            </div>
            <span className="rounded-full bg-white/14 px-3 py-1 text-[10px] font-black uppercase tracking-[0.12em] text-white">
              Easy run
            </span>
          </div>
        </div>

        <div className="p-4">
          <div className="grid grid-cols-2 gap-2.5">
            {summaryStats.map(([label, value]) => {
              const isPlan = label === "Plan";

              return (
                <div
                  key={label}
                  className={`rounded-lg border p-3 ${
                    isPlan
                      ? "border-accent/20 bg-accent-soft"
                      : "border-border/80 bg-brand-soft/55"
                  }`}
                >
                  <p
                    className={`text-[10px] font-black uppercase tracking-[0.16em] ${
                      isPlan ? "text-accent" : "text-[#4058b0]"
                    }`}
                  >
                    {label}
                  </p>
                  <p className="mt-1.5 text-lg font-black leading-none text-foreground sm:text-xl">
                    {value}
                  </p>
                </div>
              );
            })}
          </div>

          <div className="mt-3 rounded-lg border border-brand/10 bg-brand-soft/60 p-3.5">
            <div className="flex items-center justify-between gap-3">
              <p className="text-[11px] font-black uppercase tracking-[0.18em] text-[#4058b0]">
                Runiac Reflection
              </p>
              <span className="rounded-full bg-accent-soft px-3 py-1 text-[10px] font-black uppercase tracking-[0.12em] text-accent">
                Next focus
              </span>
            </div>
            <p className="mt-2.5 text-[0.82rem] font-semibold leading-relaxed text-foreground sm:text-sm">
              You completed your{" "}
              <span className="font-black text-[#4058b0]">
                planned easy run
              </span>{" "}
              and kept a{" "}
              <span className="font-black text-[#4058b0]">steady pace</span>.
              This was a strong{" "}
              <span className="font-black text-accent">
                consistency-building
              </span>{" "}
              session.
            </p>
            <p className="mt-2 text-[0.82rem] font-semibold leading-relaxed text-muted sm:text-sm">
              For your next run, focus on maintaining the same rhythm instead
              of increasing intensity too quickly.
            </p>
          </div>

          <motion.div
            className="mt-2.5 grid gap-2.5 sm:grid-cols-2"
            initial={
              reduceMotion
                ? false
                : { opacity: 0, y: 18, scale: 0.96, filter: "blur(4px)" }
            }
            animate={
              show
                ? { opacity: 1, y: 0, scale: 1, filter: "blur(0px)" }
                : { opacity: 0, y: 18, scale: 0.96, filter: "blur(4px)" }
            }
            transition={{
              delay: reduceMotion ? 0 : 0.28,
              type: "spring",
              stiffness: 210,
              damping: 24,
              mass: 0.9,
            }}
          >
            <SummaryInsightCard title="WHAT WENT WELL" items={wentWell} />
            <SummaryInsightCard title="NEXT FOCUS" items={nextFocus} accent />
          </motion.div>

          <p className="mt-2.5 border-t border-border/80 pt-2.5 text-[0.72rem] font-bold leading-relaxed text-muted sm:text-xs">
            Generated from your run data, streak, and weekly progress.
          </p>
        </div>
      </div>
    </div>
  );
}

export function PostRunSummarySection({
  content,
}: {
  content: SitePostRunSummary;
}) {
  const sectionRef = useRef(null);
  const reduceMotion = useReducedMotion();
  const isInView = useInView(sectionRef, {
    amount: 0.2,
    margin: "-8% 0px -12% 0px",
  });
  const show = Boolean(isInView || reduceMotion);

  return (
    <section
      id="post-run-summary"
      ref={sectionRef}
      className="w-full max-w-full overflow-hidden bg-background px-6 py-16 sm:py-20 lg:py-24"
    >
      <div className="mx-auto grid w-full max-w-[92rem] min-w-0 items-center gap-12 lg:grid-cols-[0.9fr_1fr] lg:gap-20">
        <motion.div
          className="min-w-0 max-w-full sm:max-w-none lg:order-1"
          initial={reduceMotion ? false : { opacity: 0, x: -30 }}
          animate={show ? { opacity: 1, x: 0 } : { opacity: 0, x: -30 }}
          transition={{
            delay: reduceMotion ? 0 : 0.08,
            duration: 0.68,
            ease: [0.22, 1, 0.36, 1],
          }}
        >
          <motion.p
            className="text-xs font-semibold uppercase tracking-[0.22em] text-brand sm:text-sm"
            initial={reduceMotion ? false : { opacity: 0, y: 14 }}
            animate={show ? { opacity: 1, y: 0 } : { opacity: 0, y: 14 }}
            transition={{
              delay: reduceMotion ? 0 : 0.16,
              duration: 0.5,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            {content.eyebrow}
          </motion.p>
          <motion.h2
            className="mt-4 max-w-[21rem] break-words font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[1.62rem] font-normal uppercase leading-[1.08] tracking-normal text-[#4058b0] min-[430px]:text-[2.08rem] sm:max-w-4xl sm:text-6xl sm:leading-[1.03] lg:text-7xl"
            initial={
              reduceMotion
                ? false
                : { opacity: 0, y: 22, filter: "blur(4px)" }
            }
            animate={
              show
                ? { opacity: 1, y: 0, filter: "blur(0px)" }
                : { opacity: 0, y: 22, filter: "blur(4px)" }
            }
            transition={{
              delay: reduceMotion ? 0 : 0.24,
              duration: 0.68,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            {content.heading}
          </motion.h2>
          <motion.p
            className="mt-7 max-w-[22rem] break-words text-base leading-relaxed text-muted sm:max-w-2xl sm:text-lg"
            initial={reduceMotion ? false : { opacity: 0, y: 18 }}
            animate={show ? { opacity: 1, y: 0 } : { opacity: 0, y: 18 }}
            transition={{
              delay: reduceMotion ? 0 : 0.34,
              duration: 0.6,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            {content.body}
          </motion.p>

          <motion.div
            className="mt-7 grid max-w-[24rem] gap-3"
            initial={reduceMotion ? false : { opacity: 0, y: 18 }}
            animate={show ? { opacity: 1, y: 0 } : { opacity: 0, y: 18 }}
            transition={{
              delay: reduceMotion ? 0 : 0.4,
              duration: 0.6,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            {content.bullets.map((benefit, index) => (
              <div key={`${index}-${benefit}`} className="flex items-center gap-3">
                <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-accent-soft text-accent">
                  <CheckMark />
                </span>
                <p className="text-sm font-bold leading-snug text-foreground sm:text-base">
                  {benefit}
                </p>
              </div>
            ))}
          </motion.div>

          <motion.div
            className="mt-8 flex flex-wrap items-center gap-3"
            initial={reduceMotion ? false : { opacity: 0, y: 16, scale: 0.98 }}
            animate={
              show
                ? { opacity: 1, y: 0, scale: 1 }
                : { opacity: 0, y: 16, scale: 0.98 }
            }
            transition={{
              delay: reduceMotion ? 0 : 0.46,
              duration: 0.56,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            <CtaButton href="#post-run-summary" variant="primary">
              {content.ctaLabel}
            </CtaButton>
            <span className="rounded-full border border-brand/15 bg-brand-soft px-4 py-2 text-xs font-black uppercase tracking-[0.14em] text-[#4058b0]">
              {content.ctaSecondaryLabel}
            </span>
          </motion.div>
        </motion.div>

        <motion.div
          className="relative mx-auto w-full min-w-0 max-w-[43rem] lg:order-2"
          initial={reduceMotion ? false : { opacity: 0, x: 34, scale: 0.96 }}
          animate={
            show
              ? { opacity: 1, x: 0, scale: 1 }
              : { opacity: 0, x: 34, scale: 0.96 }
          }
          transition={{
            duration: 0.72,
            ease: [0.22, 1, 0.36, 1],
          }}
        >
          {content.imageSrc ? (
            <IphoneFrame src={content.imageSrc} alt={content.imageAlt} />
          ) : (
            <PostRunSummaryMockup show={show} />
          )}
        </motion.div>
      </div>
    </section>
  );
}
