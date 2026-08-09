"use client";

// The home-page section about XP and levels.
//
// Same highlight shape as its siblings, content supplied as a [SiteHighlight].
// XP is entirely server-owned and unaffected by subscription tier, so this
// section describes progression as something earned by running — not bought.

import { useRef } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import { CtaButton } from "./CtaButton";
import { IphoneFrame } from "./IphoneFrame";
import type { SiteHighlight } from "@/lib/site-highlight";

const xpBreakdown = [
  ["Plan completed", "+30 XP"],
  ["Streak continued", "+20 XP"],
  ["Weekly goal progress", "+30 XP"],
];

export function XpProgressionHighlight({
  content,
}: {
  content: SiteHighlight;
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
      id="xp-progression"
      ref={sectionRef}
      className="w-full max-w-full overflow-hidden bg-background px-6 py-24 sm:py-28 lg:py-32"
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
            <>
          <div
            aria-hidden="true"
            className="absolute inset-x-6 bottom-4 top-12 rounded-lg bg-brand-soft/80 shadow-[0_34px_90px_-62px_rgba(0,30,98,0.7)] sm:inset-x-12"
          />

          <div className="relative mx-auto w-full max-w-[28rem] rounded-lg border border-border/80 bg-white p-5 shadow-[0_34px_90px_-56px_rgba(0,30,98,0.62)] sm:p-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-[11px] font-black uppercase tracking-[0.18em] text-[#4058b0]">
                  Runner Progress
                </p>
                <h3 className="mt-2 text-2xl font-black leading-tight text-foreground sm:text-3xl">
                  Level 4 Runner
                </h3>
              </div>
              <span className="rounded-full bg-accent-soft px-3 py-1 text-[10px] font-black uppercase tracking-[0.14em] text-accent">
                +80 XP
              </span>
            </div>

            <div className="mt-7 rounded-lg border border-border/80 bg-brand-soft/55 p-4">
              <div className="flex items-end justify-between gap-4">
                <div>
                  <p className="text-3xl font-black leading-none text-[#4058b0]">
                    420 / 600 XP
                  </p>
                  <p className="mt-2 text-sm font-semibold text-muted">
                    to Level 5
                  </p>
                </div>
                <p className="text-sm font-black text-accent">
                  +80 XP earned
                </p>
              </div>
              <div className="mt-5 h-3 overflow-hidden rounded-full bg-white shadow-inner">
                <motion.div
                  className="h-full rounded-full bg-[#4058b0]"
                  initial={reduceMotion ? false : { width: "0%" }}
                  animate={show ? { width: "70%" } : { width: "0%" }}
                  transition={{
                    delay: reduceMotion ? 0 : 0.42,
                    duration: 0.78,
                    ease: [0.22, 1, 0.36, 1],
                  }}
                />
              </div>
            </div>

            <div className="mt-5 space-y-3">
              {xpBreakdown.map(([label, xp]) => (
                <div
                  key={label}
                  className="flex items-center justify-between gap-4 border-b border-border/80 pb-3 last:border-b-0 last:pb-0"
                >
                  <span className="text-sm font-bold leading-snug text-foreground sm:text-base">
                    {label}
                  </span>
                  <span className="shrink-0 text-sm font-black text-accent sm:text-base">
                    {xp}
                  </span>
                </div>
              ))}
            </div>
          </div>

          <motion.div
            className="relative mx-auto mt-4 w-full max-w-[23rem] rounded-lg border border-white/80 bg-white/95 p-4 shadow-[0_24px_70px_-46px_rgba(0,30,98,0.66)] backdrop-blur sm:absolute sm:bottom-0 sm:right-0 sm:mt-0 sm:w-[22rem] sm:p-5"
            initial={
              reduceMotion
                ? false
                : { opacity: 0, y: 24, scale: 0.94, filter: "blur(5px)" }
            }
            animate={
              show
                ? { opacity: 1, y: 0, scale: 1, filter: "blur(0px)" }
                : { opacity: 0, y: 24, scale: 0.94, filter: "blur(5px)" }
            }
            transition={{
              delay: reduceMotion ? 0 : 0.28,
              type: "spring",
              stiffness: 210,
              damping: 24,
              mass: 0.9,
            }}
          >
            <div className="flex items-center gap-3">
              <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-accent-soft text-sm font-black text-accent">
                XP
              </span>
              <p className="text-[11px] font-black uppercase tracking-[0.18em] text-[#4058b0]">
                RUNIAC REWARD
              </p>
            </div>
            <p className="mt-3 text-sm font-bold leading-relaxed text-foreground sm:text-base">
              Progress is not only about running faster. Every consistent run
              moves you forward.
            </p>
          </motion.div>
            </>
          )}
        </motion.div>
      </div>
    </section>
  );
}
