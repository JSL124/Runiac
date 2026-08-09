"use client";

import { useRef } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import { CtaButton } from "./CtaButton";
import { IphoneFrame } from "./IphoneFrame";
import type { SiteHighlight } from "@/lib/site-highlight";

// Beginner-friendly "how a day feels" cues shown as the illustration fallback
// when no screenshot is set. Mirrors the real home adventure map: each weekday
// is a stepping stone the runner moves along.
const journeyDays = [
  ["Mon", "Easy 20 min", "done"],
  ["Tue", "Rest day", "done"],
  ["Wed", "Comfortable 30 min", "today"],
  ["Thu", "Recovery run", "upcoming"],
] as const;

export function JourneyMapHighlight({ content }: { content: SiteHighlight }) {
  const sectionRef = useRef(null);
  const reduceMotion = useReducedMotion();
  const isInView = useInView(sectionRef, {
    amount: 0.24,
    margin: "-8% 0px -12% 0px",
  });
  const show = Boolean(isInView || reduceMotion);

  return (
    <section
      id="journey-map"
      ref={sectionRef}
      className="w-full max-w-full overflow-hidden px-6 py-24 sm:py-28 lg:py-32"
    >
      <div className="mx-auto grid w-full max-w-[92rem] min-w-0 items-center gap-12 lg:grid-cols-[0.9fr_1fr] lg:gap-20">
        <motion.div
          className="min-w-0 max-w-full sm:max-w-none"
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
            className="mt-4 max-w-[20rem] break-words font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[1.76rem] font-normal uppercase leading-[1.08] tracking-normal text-[#4058b0] min-[430px]:text-[2.25rem] sm:max-w-4xl sm:text-6xl sm:leading-[1.03] lg:text-7xl"
            initial={
              reduceMotion ? false : { opacity: 0, y: 22, filter: "blur(4px)" }
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
            className="mt-7 max-w-[21rem] break-words text-base leading-relaxed text-muted sm:max-w-2xl sm:text-lg"
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
            className="mt-8"
            initial={reduceMotion ? false : { opacity: 0, y: 16, scale: 0.98 }}
            animate={
              show
                ? { opacity: 1, y: 0, scale: 1 }
                : { opacity: 0, y: 16, scale: 0.98 }
            }
            transition={{
              delay: reduceMotion ? 0 : 0.42,
              duration: 0.56,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            <CtaButton href="#cta" variant="primary">
              {content.ctaLabel}
            </CtaButton>
          </motion.div>
        </motion.div>

        <motion.div
          className="relative mx-auto w-full min-w-0 max-w-[36rem] overflow-hidden pb-10 pt-4 sm:overflow-visible sm:pb-14 lg:max-w-[42rem] lg:pb-12"
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
            <div className="relative mx-auto w-full max-w-[28rem] rounded-lg border border-border/80 bg-white p-5 shadow-[0_34px_90px_-56px_rgba(0,30,98,0.62)] sm:p-6">
              <div className="flex items-center justify-between gap-4">
                <div>
                  <p className="text-[11px] font-black uppercase tracking-[0.18em] text-[#4058b0]">
                    This week&apos;s journey
                  </p>
                  <h3 className="mt-2 text-2xl font-black leading-tight text-foreground sm:text-3xl">
                    Step by step
                  </h3>
                </div>
                <span className="rounded-full bg-accent-soft px-3 py-1 text-[10px] font-black uppercase tracking-[0.14em] text-accent">
                  Day 3
                </span>
              </div>

              <div className="mt-6 space-y-3">
                {journeyDays.map(([day, label, state]) => (
                  <div
                    key={day}
                    className={`flex items-center gap-4 rounded-lg border px-4 py-3 ${
                      state === "today"
                        ? "border-accent/40 bg-accent-soft/50"
                        : "border-border/80 bg-brand-soft/30"
                    }`}
                  >
                    <span
                      className={`grid h-9 w-9 shrink-0 place-items-center rounded-full text-[11px] font-black uppercase ${
                        state === "done"
                          ? "bg-[#4058b0] text-white"
                          : state === "today"
                            ? "bg-accent text-white"
                            : "bg-white text-muted"
                      }`}
                    >
                      {day}
                    </span>
                    <span className="text-sm font-bold leading-snug text-foreground sm:text-base">
                      {label}
                    </span>
                    {state === "today" && (
                      <span className="ml-auto shrink-0 text-xs font-black uppercase tracking-[0.14em] text-accent">
                        Today
                      </span>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </motion.div>
      </div>
    </section>
  );
}
