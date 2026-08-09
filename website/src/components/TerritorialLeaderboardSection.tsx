"use client";

// The home-page section about the regional leaderboard.
//
// Same highlight shape as its siblings, content supplied as a [SiteHighlight]
// from the admin console. Worth keeping accurate: leaderboard standings are
// server-computed and identical for Basic and Premium, so this section must not
// imply that paying improves a rank.

import { useRef } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import { CtaButton } from "./CtaButton";
import { IphoneFrame } from "./IphoneFrame";
import type { SiteHighlight } from "@/lib/site-highlight";

const leaderboardRows = [
  ["1", "Mina", "850 XP"],
  ["2", "Alex", "790 XP"],
  ["3", "You", "760 XP"],
  ["4", "Ryan", "720 XP"],
];

const mapRegions = [
  {
    name: "Jurong East",
    x: "24%",
    y: "55%",
    selected: true,
  },
  {
    name: "Woodlands",
    x: "44%",
    y: "22%",
  },
  {
    name: "Queenstown",
    x: "42%",
    y: "61%",
  },
  {
    name: "Marina Bay",
    x: "61%",
    y: "66%",
  },
  {
    name: "Tampines",
    x: "78%",
    y: "46%",
  },
];

function PodiumIcon({ selected = false }: { selected?: boolean }) {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
      className={selected ? "text-white" : "text-[#4058b0]"}
    >
      <path
        d="M5 20v-5h4v5H5Z"
        fill="currentColor"
        opacity={selected ? 0.95 : 0.78}
      />
      <path d="M10 20V9h4v11h-4Z" fill="currentColor" />
      <path
        d="M15 20v-8h4v8h-4Z"
        fill="currentColor"
        opacity={selected ? 0.95 : 0.78}
      />
      <path
        d="M9 6.5 12 4l3 2.5-1.1 3.6h-3.8L9 6.5Z"
        fill="currentColor"
      />
    </svg>
  );
}

function PhoneLeaderboard() {
  return (
    <div className="relative mx-auto w-full max-w-[20.5rem] rounded-[2rem] border border-[#4058b0]/15 bg-[#001014] p-2 shadow-[0_34px_90px_-52px_rgba(0,30,98,0.72)] sm:max-w-[21.5rem]">
      <div className="overflow-hidden rounded-[1.55rem] bg-white">
        <div className="bg-[#4058b0] px-5 pb-5 pt-6 text-white">
          <div className="mx-auto mb-5 h-1.5 w-16 rounded-full bg-white/28" />
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-[11px] font-black uppercase tracking-[0.18em] text-white/72">
                Jurong East
              </p>
              <h3 className="mt-2 text-2xl font-black leading-none">
                Weekly XP
              </h3>
            </div>
            <span className="rounded-full bg-white/14 px-3 py-1 text-[10px] font-black uppercase tracking-[0.12em] text-white">
              Local
            </span>
          </div>
          <div className="mt-5 flex flex-wrap items-center gap-2">
            <span className="rounded-full bg-accent px-3 py-1 text-[10px] font-black uppercase tracking-[0.12em] text-white">
              Level 1-5 Division
            </span>
            <span className="rounded-full bg-white/14 px-3 py-1 text-[10px] font-black uppercase tracking-[0.12em] text-white">
              Same-level competition
            </span>
          </div>
        </div>

        <div className="px-5 py-5">
          <p className="text-[11px] font-black uppercase tracking-[0.18em] text-[#4058b0]">
            Weekly XP Leaderboard
          </p>
          <div className="mt-4 space-y-2.5">
            {leaderboardRows.map(([rank, name, xp]) => {
              const isYou = name === "You";

              return (
                <div
                  key={name}
                  className={`grid grid-cols-[2rem_1fr_auto] items-center gap-3 rounded-2xl px-3 py-3 text-sm font-bold ${
                    isYou
                      ? "bg-accent-soft text-foreground ring-1 ring-accent/20"
                      : "bg-brand-soft/55 text-foreground"
                  }`}
                >
                  <span
                    className={`grid h-7 w-7 place-items-center rounded-full text-xs font-black ${
                      rank === "1"
                        ? "bg-accent text-white"
                        : isYou
                          ? "bg-white text-accent"
                          : "bg-white text-[#4058b0]"
                    }`}
                  >
                    {rank}
                  </span>
                  <span>{name}</span>
                  <span className={isYou ? "text-accent" : "text-[#4058b0]"}>
                    {xp}
                  </span>
                </div>
              );
            })}
          </div>

          <div className="mt-5 flex items-center justify-between gap-3 border-t border-border/80 pt-4">
            <p className="text-xs font-bold text-muted">Updated weekly</p>
            <p className="text-xs font-black text-accent">Monthly XP ready</p>
          </div>
        </div>
      </div>
    </div>
  );
}

function SingaporeMap() {
  return (
    <div className="relative mx-auto w-full max-w-[38rem] overflow-hidden rounded-lg border border-border/80 bg-white p-4 shadow-[0_30px_80px_-58px_rgba(0,30,98,0.62)] sm:p-6">
      <div
        aria-hidden="true"
        className="absolute inset-4 rounded-lg bg-brand-soft/65 sm:inset-6"
      />

      <div className="relative z-10 flex items-center justify-between gap-3">
        <div>
          <p className="text-[11px] font-black uppercase tracking-[0.18em] text-[#4058b0]">
            Singapore Areas
          </p>
          <p className="mt-1 text-sm font-semibold text-muted">
            Local rankings by region and level
          </p>
        </div>
        <span className="rounded-full bg-white px-3 py-1 text-[10px] font-black uppercase tracking-[0.12em] text-accent shadow-sm">
          Mock map
        </span>
      </div>

      <div className="relative z-10 mt-6 h-64 sm:h-72 lg:h-80">
        <svg
          viewBox="0 0 620 310"
          className="absolute left-1/2 top-1/2 h-[82%] w-[118%] -translate-x-1/2 -translate-y-1/2 sm:w-[108%]"
          role="img"
          aria-label="Stylized Singapore map with regional leaderboard markers"
        >
          <defs>
            <filter
              id="leaderboardMapGlow"
              x="-20%"
              y="-30%"
              width="140%"
              height="160%"
            >
              <feGaussianBlur stdDeviation="8" result="blur" />
              <feColorMatrix
                in="blur"
                type="matrix"
                values="0 0 0 0 0.251 0 0 0 0 0.345 0 0 0 0 0.690 0 0 0 0.22 0"
              />
              <feMerge>
                <feMergeNode />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>
          <path
            d="M58 173C96 132 143 112 204 111c39-1 76-20 114-29 70-17 127 21 181 45 35 16 63 15 91 40 22 20 19 47-7 61-43 24-101 13-145 1-57-16-88-5-142 13-44 14-91 24-134 10-52-16-95-26-118-53-8-9-1-17 14-26Z"
            fill="#eef3ff"
            stroke="#4058b0"
            strokeOpacity="0.22"
            strokeWidth="3"
            filter="url(#leaderboardMapGlow)"
          />
          <path
            d="M487 108c31-4 62 7 82 28"
            stroke="#f26a3d"
            strokeOpacity="0.28"
            strokeWidth="4"
            strokeLinecap="round"
          />
          <path
            d="M103 190c64 18 124 21 185 2 64-20 121-20 177-2"
            stroke="#4058b0"
            strokeOpacity="0.16"
            strokeWidth="4"
            strokeLinecap="round"
          />
        </svg>

        {mapRegions.map((region) => (
          <div
            key={region.name}
            className="absolute z-20"
            style={{ left: region.x, top: region.y }}
          >
            <div className="-translate-x-1/2 -translate-y-1/2">
              <div
                className={`relative mx-auto grid place-items-center rounded-full border shadow-[0_18px_40px_-26px_rgba(0,30,98,0.7)] ${
                  region.selected
                    ? "h-14 w-14 border-white bg-accent ring-8 ring-accent/15"
                    : "h-11 w-11 border-white bg-white"
                }`}
              >
                <PodiumIcon selected={region.selected} />
                {region.selected && (
                  <span className="absolute -right-8 -top-3 rounded-full bg-white px-2.5 py-1 text-[9px] font-black uppercase tracking-[0.1em] text-accent shadow-sm">
                    Selected
                  </span>
                )}
              </div>
              <p
                className={`mt-2 whitespace-nowrap rounded-full bg-white/95 px-2.5 py-1 text-center text-[10px] font-black shadow-sm ${
                  region.selected ? "text-accent" : "text-[#4058b0]"
                }`}
              >
                {region.name}
              </p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export function TerritorialLeaderboardSection({
  content,
}: {
  content: SiteHighlight;
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
      id="territorial-leaderboard"
      ref={sectionRef}
      className="w-full max-w-full overflow-hidden bg-background px-6 py-24 sm:py-28 lg:py-32"
    >
      <div className="mx-auto grid w-full max-w-[92rem] min-w-0 items-center gap-12 lg:grid-cols-[0.82fr_1.18fr] lg:gap-20">
        <motion.div
          className="min-w-0 max-w-full sm:max-w-none lg:order-2"
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
            <CtaButton href="#territorial-leaderboard" variant="primary">
              {content.ctaLabel}
            </CtaButton>
          </motion.div>
        </motion.div>

        <motion.div
          className="relative mx-auto grid w-full min-w-0 max-w-[43rem] gap-5 overflow-hidden pb-2 sm:overflow-visible lg:order-1 lg:max-w-[48rem]"
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
            className="absolute inset-x-6 bottom-16 top-10 rounded-lg bg-brand-soft/70 shadow-[0_34px_90px_-62px_rgba(0,30,98,0.7)] sm:inset-x-12 lg:bottom-10"
          />

          <div className="relative grid gap-5 lg:grid-cols-[0.78fr_1fr] lg:items-center">
            <div className="order-2 lg:order-2">
              <SingaporeMap />
            </div>

            <div className="order-1 lg:order-1 lg:z-10 lg:-mr-14">
              <PhoneLeaderboard />
            </div>
          </div>
            </>
          )}
        </motion.div>
      </div>
    </section>
  );
}
