"use client";

// The home-page section about personalised plans.
//
// One of four highlight sections ([XpProgressionHighlight],
// [PostRunSummarySection], [TerritorialLeaderboardSection] and this) that share
// a shape: a phone frame beside copy, animated in on scroll.
//
// Its content is passed in as a [SitePersonalizedPlan] rather than hard-coded,
// so the copy is editable from the admin console's Website Content page without
// a redeploy.

import { useRef } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import { CtaButton } from "./CtaButton";
import { IphoneFrame } from "./IphoneFrame";
import type { SitePersonalizedPlan } from "@/lib/site-personalized-plan";

const startingPoint = [
  ["Goal", "Build consistency"],
  ["Level", "Beginner"],
  ["Recent Activity", "1 run last week"],
  ["Available Days", "Mon · Wed · Fri"],
];

const weeklyPlan = [
  ["MON", "Easy Run · 20 min"],
  ["WED", "Rest Day"],
  ["FRI", "Steady Run · 25 min"],
];

function FlowArrow({ show }: { show: boolean }) {
  const reduceMotion = useReducedMotion();

  return (
    <div className="flex items-center gap-3 px-2 py-0.5" aria-hidden="true">
      <motion.div
        className="h-px flex-1 origin-right bg-border"
        initial={reduceMotion ? false : { scaleX: 0, opacity: 0 }}
        animate={show ? { scaleX: 1, opacity: 1 } : { scaleX: 0, opacity: 0 }}
        transition={{
          delay: reduceMotion ? 0 : 0.38,
          duration: 0.5,
          ease: [0.22, 1, 0.36, 1],
        }}
      />
      <motion.span
        className="grid h-6 w-6 shrink-0 place-items-center rounded-full border border-border bg-white text-xs font-black text-[#4058b0] shadow-sm"
        initial={reduceMotion ? false : { opacity: 0, scale: 0.4, x: -8 }}
        animate={
          show
            ? { opacity: 1, scale: [1, 1.18, 1], x: 0 }
            : { opacity: 0, scale: 0.4, x: -8 }
        }
        transition={{
          delay: reduceMotion ? 0 : 0.54,
          duration: 0.58,
          ease: [0.22, 1, 0.36, 1],
        }}
      >
        →
      </motion.span>
      <motion.div
        className="h-px flex-1 origin-left bg-border"
        initial={reduceMotion ? false : { scaleX: 0, opacity: 0 }}
        animate={show ? { scaleX: 1, opacity: 1 } : { scaleX: 0, opacity: 0 }}
        transition={{
          delay: reduceMotion ? 0 : 0.62,
          duration: 0.5,
          ease: [0.22, 1, 0.36, 1],
        }}
      />
    </div>
  );
}

export function PersonalizedPlanHighlight({
  content,
}: {
  content: SitePersonalizedPlan;
}) {
  const sectionRef = useRef(null);
  const reduceMotion = useReducedMotion();
  const isInView = useInView(sectionRef, {
    amount: 0.24,
    margin: "-8% 0px -12% 0px",
  });
  const show = Boolean(isInView || reduceMotion);

  return (
    <section
      id="personalized-plan"
      ref={sectionRef}
      className="w-full max-w-full overflow-hidden bg-background px-6 py-24 sm:py-28 lg:py-32"
    >
      <div className="mx-auto grid w-full max-w-[92rem] min-w-0 items-center gap-12 lg:grid-cols-[0.9fr_1fr] lg:gap-20">
        <motion.div
          className="min-w-0 max-w-full sm:max-w-none lg:order-2"
          initial={reduceMotion ? false : { opacity: 0, x: 30 }}
          animate={show ? { opacity: 1, x: 0 } : { opacity: 0, x: 30 }}
          transition={{
            delay: reduceMotion ? 0 : 0.1,
            duration: 0.68,
            ease: [0.22, 1, 0.36, 1],
          }}
        >
          <motion.p
            className="text-xs font-semibold uppercase tracking-[0.22em] text-brand sm:text-sm"
            initial={reduceMotion ? false : { opacity: 0, y: 14 }}
            animate={show ? { opacity: 1, y: 0 } : { opacity: 0, y: 14 }}
            transition={{
              delay: reduceMotion ? 0 : 0.18,
              duration: 0.5,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            {content.eyebrow}
          </motion.p>
          <motion.h2
            className="mt-4 max-w-[20rem] break-words font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[1.52rem] font-normal uppercase leading-[1.1] tracking-normal text-[#4058b0] min-[430px]:text-[2.05rem] sm:max-w-4xl sm:text-6xl sm:leading-[1.03] lg:text-7xl"
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
              delay: reduceMotion ? 0 : 0.26,
              duration: 0.68,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            {content.heading}
          </motion.h2>
          <motion.p
            className="mt-7 max-w-[20rem] break-words text-base leading-relaxed text-muted sm:max-w-2xl sm:text-lg"
            initial={reduceMotion ? false : { opacity: 0, y: 18 }}
            animate={show ? { opacity: 1, y: 0 } : { opacity: 0, y: 18 }}
            transition={{
              delay: reduceMotion ? 0 : 0.36,
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
              delay: reduceMotion ? 0 : 0.5,
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
          className="relative mx-auto w-full min-w-0 max-w-[36rem] overflow-hidden py-2 sm:overflow-visible lg:order-1 lg:max-w-[39rem]"
          initial={
            reduceMotion
              ? false
              : { opacity: 0, x: -42, y: 18, scale: 0.93, rotate: -1.2 }
          }
          animate={
            show
              ? { opacity: 1, x: 0, y: 0, scale: 1, rotate: 0 }
              : { opacity: 0, x: -42, y: 18, scale: 0.93, rotate: -1.2 }
          }
          transition={{
            type: "spring",
            stiffness: 150,
            damping: 18,
            mass: 0.9,
          }}
        >
          {content.imageSrc ? (
            <IphoneFrame src={content.imageSrc} alt={content.imageAlt} />
          ) : (
            <>
          <motion.div
            aria-hidden="true"
            className="absolute inset-x-4 bottom-5 top-8 rounded-lg bg-brand-soft/80 shadow-[0_34px_90px_-62px_rgba(0,30,98,0.7)] sm:inset-x-10"
            initial={reduceMotion ? false : { opacity: 0, scale: 0.92 }}
            animate={
              show
                ? { opacity: [0.55, 0.85, 0.7], scale: [0.96, 1.02, 1] }
                : { opacity: 0, scale: 0.92 }
            }
            transition={{
              delay: reduceMotion ? 0 : 0.2,
              duration: 1,
              ease: [0.22, 1, 0.36, 1],
            }}
          />

          <div className="relative mx-auto w-full max-w-[31.5rem] overflow-hidden rounded-lg border border-border/80 bg-white p-4 shadow-[0_34px_90px_-54px_rgba(0,30,98,0.66)]">
            <div className="flex min-w-0 flex-col items-start gap-2 sm:flex-row sm:justify-between sm:gap-4">
              <div className="min-w-0">
                <p className="text-[11px] font-black uppercase tracking-[0.18em] text-[#4058b0]">
                  Your Personalized Week
                </p>
                <h3 className="mt-1.5 text-xl font-black leading-tight text-foreground sm:text-2xl">
                  Built from your starting point
                </h3>
              </div>
              <motion.span
                className="shrink-0 rounded-full bg-accent-soft px-3 py-1 text-[10px] font-black uppercase tracking-[0.14em] text-accent"
                initial={reduceMotion ? false : { opacity: 0, scale: 0.7, x: 10 }}
                animate={
                  show
                    ? { opacity: 1, scale: [1, 1.08, 1], x: 0 }
                    : { opacity: 0, scale: 0.7, x: 10 }
                }
                transition={{
                  delay: reduceMotion ? 0 : 0.32,
                  duration: 0.5,
                  ease: [0.22, 1, 0.36, 1],
                }}
              >
                F3 Plan
              </motion.span>
            </div>

            <div className="mt-4 rounded-lg border border-border/80 bg-brand-soft/45 p-3.5">
              <p className="text-[11px] font-black uppercase tracking-[0.18em] text-[#4058b0]">
                Starting Point
              </p>
              <div className="mt-3 grid grid-cols-2 gap-2.5">
                {startingPoint.map(([label, value], index) => (
                  <motion.div
                    key={label}
                    className="rounded-lg border border-white/80 bg-white px-3 py-2.5 shadow-sm"
                    initial={
                      reduceMotion
                        ? false
                        : { opacity: 0, y: 14, scale: 0.94, filter: "blur(3px)" }
                    }
                    animate={
                      show
                        ? { opacity: 1, y: 0, scale: 1, filter: "blur(0px)" }
                        : { opacity: 0, y: 14, scale: 0.94, filter: "blur(3px)" }
                    }
                    transition={{
                      delay: reduceMotion ? 0 : 0.28 + index * 0.07,
                      duration: 0.46,
                      ease: [0.22, 1, 0.36, 1],
                    }}
                  >
                    <p className="text-[10px] font-black uppercase tracking-[0.16em] text-muted">
                      {label}
                    </p>
                    <p className="mt-1 text-sm font-black leading-snug text-foreground">
                      {value}
                    </p>
                  </motion.div>
                ))}
              </div>
            </div>

            <FlowArrow show={show} />

            <div className="rounded-lg border border-brand/10 bg-white p-3.5 shadow-[0_24px_70px_-50px_rgba(0,30,98,0.58)]">
              <div className="flex min-w-0 flex-col items-start gap-2 sm:flex-row sm:items-center sm:justify-between sm:gap-4">
                <div className="min-w-0">
                  <p className="text-[11px] font-black uppercase tracking-[0.18em] text-[#4058b0]">
                    This Week’s Plan
                  </p>
                  <p className="mt-1 text-sm font-semibold text-muted">
                    Beginner base week
                  </p>
                </div>
                <motion.span
                  className="shrink-0 rounded-full bg-accent-soft px-3 py-1 text-[10px] font-black uppercase tracking-[0.14em] text-accent"
                  initial={reduceMotion ? false : { opacity: 0, scale: 0.75 }}
                  animate={
                    show
                      ? { opacity: 1, scale: [1, 1.12, 1] }
                      : { opacity: 0, scale: 0.75 }
                  }
                  transition={{
                    delay: reduceMotion ? 0 : 0.7,
                    duration: 0.5,
                    ease: [0.22, 1, 0.36, 1],
                  }}
                >
                  Generated
                </motion.span>
              </div>

              <div className="mt-3 space-y-2">
                {weeklyPlan.map(([day, workout], index) => {
                  const isRestDay = workout === "Rest Day";

                  return (
                    <motion.div
                      key={day}
                      className="grid min-w-0 grid-cols-[2.75rem_minmax(0,1fr)] items-center gap-2 rounded-lg border border-border/70 bg-white px-3 py-2 sm:grid-cols-[3rem_minmax(0,1fr)]"
                      initial={
                        reduceMotion
                          ? false
                          : { opacity: 0, x: -18, scale: 0.97 }
                      }
                      animate={
                        show
                          ? { opacity: 1, x: 0, scale: 1 }
                          : { opacity: 0, x: -18, scale: 0.97 }
                      }
                      transition={{
                        delay: reduceMotion ? 0 : 0.78 + index * 0.08,
                        duration: 0.48,
                        ease: [0.22, 1, 0.36, 1],
                      }}
                    >
                      <span className="text-sm font-black text-brand">
                        {day}
                      </span>
                      <motion.span
                        className={`min-w-0 rounded-full px-3 py-1 text-sm font-bold leading-snug sm:w-fit ${
                          isRestDay
                            ? "bg-brand-soft text-[#4058b0]"
                            : "bg-accent-soft text-foreground"
                        }`}
                        initial={reduceMotion ? false : { scale: 0.9 }}
                        animate={show ? { scale: [1, 1.04, 1] } : { scale: 0.9 }}
                        transition={{
                          delay: reduceMotion ? 0 : 0.96 + index * 0.08,
                          duration: 0.42,
                          ease: [0.22, 1, 0.36, 1],
                        }}
                      >
                        {workout}
                      </motion.span>
                    </motion.div>
                  );
                })}
              </div>

              <motion.div
                className="mt-3 rounded-lg bg-brand-soft px-3 py-2"
                initial={reduceMotion ? false : { opacity: 0, y: 10 }}
                animate={show ? { opacity: 1, y: 0 } : { opacity: 0, y: 10 }}
                transition={{
                  delay: reduceMotion ? 0 : 1.08,
                  duration: 0.44,
                  ease: [0.22, 1, 0.36, 1],
                }}
              >
                <p className="text-sm font-black text-brand">
                  Focus — Build consistency
                </p>
              </motion.div>
            </div>

            <FlowArrow show={show} />

            <motion.div
              className="rounded-lg border border-brand/10 bg-brand-soft/70 px-3.5 py-3"
              initial={reduceMotion ? false : { opacity: 0, y: 14, scale: 0.97 }}
              animate={
                show
                  ? { opacity: 1, y: 0, scale: 1 }
                  : { opacity: 0, y: 14, scale: 0.97 }
              }
              transition={{
                delay: reduceMotion ? 0 : 1.12,
                duration: 0.5,
                ease: [0.22, 1, 0.36, 1],
              }}
            >
              <div className="flex items-center gap-3">
                <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-accent-soft text-xs font-black text-accent">
                  i
                </span>
                <p className="text-[11px] font-black uppercase tracking-[0.18em] text-[#4058b0]">
                  Runiac Tip
                </p>
              </div>
              <p className="mt-2 text-sm font-bold leading-relaxed text-foreground">
                This week is about completing your plan, not running faster.
              </p>
            </motion.div>
          </div>
            </>
          )}
        </motion.div>
      </div>
    </section>
  );
}
