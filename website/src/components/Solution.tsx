"use client";

import Image from "next/image";
import { useRef } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import type { Variants } from "motion/react";
import { CtaButton } from "./CtaButton";
import type { SiteSolution } from "@/lib/site-solution";

const benefitListVariants: Variants = {
  hidden: {},
  show: {
    transition: {
      delayChildren: 0.28,
      staggerChildren: 0.11,
    },
  },
};

const benefitItemVariants: Variants = {
  hidden: {
    opacity: 0,
    y: 22,
    scale: 0.985,
    filter: "blur(3px)",
  },
  show: {
    opacity: 1,
    y: 0,
    scale: 1,
    filter: "blur(0px)",
    transition: {
      type: "spring",
      stiffness: 240,
      damping: 26,
      mass: 0.9,
    },
  },
};

const ctaRevealVariants: Variants = {
  hidden: {
    opacity: 0,
    y: 16,
    scale: 0.98,
    filter: "blur(3px)",
  },
  show: {
    opacity: 1,
    y: 0,
    scale: 1,
    filter: "blur(0px)",
    transition: {
      type: "spring",
      stiffness: 230,
      damping: 24,
      mass: 0.85,
    },
  },
};

function SolutionImage({
  show,
  reduceMotion,
}: {
  show: boolean;
  reduceMotion: boolean | null;
}) {
  return (
    <motion.div
      className="relative mx-auto h-full w-full max-w-[520px] overflow-hidden rounded-lg bg-white"
      initial={reduceMotion ? false : { opacity: 0, x: 34, scale: 0.96 }}
      animate={
        show
          ? { opacity: 1, x: 0, scale: 1 }
          : { opacity: 0, x: 34, scale: 0.96 }
      }
      transition={{
        delay: reduceMotion ? 0 : 0.22,
        duration: 0.7,
        ease: [0.22, 1, 0.36, 1],
      }}
    >
      <Image
        src="/solution-runners.jpeg"
        alt="Group of runners sprinting through a city street"
        width={736}
        height={920}
        sizes="(min-width: 1024px) 38vw, 92vw"
        className="aspect-[4/5] w-full object-cover object-center lg:h-full lg:aspect-auto"
      />
    </motion.div>
  );
}

export function Solution({ content }: { content: SiteSolution }) {
  const sectionRef = useRef(null);
  const isInView = useInView(sectionRef, {
    amount: 0.2,
    margin: "-6% 0px -10% 0px",
    initial: true,
  });
  const reduceMotion = useReducedMotion();
  const show = Boolean(isInView || reduceMotion);

  return (
    <section
      id="solution"
      ref={sectionRef}
      className="relative w-full overflow-hidden bg-background px-6 py-24 sm:py-28 lg:py-32"
    >
      <div className="mx-auto max-w-[92rem]">
        <div className="grid items-center gap-14 lg:grid-cols-[1fr_0.88fr] lg:items-stretch lg:gap-20">
          <motion.div
            className="min-w-0 max-w-3xl"
            initial={reduceMotion ? false : { opacity: 0, x: -28 }}
            animate={show ? { opacity: 1, x: 0 } : { opacity: 0, x: -28 }}
            transition={{
              duration: 0.65,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            <p className="text-xs font-semibold uppercase tracking-[0.22em] text-brand sm:text-sm">
              {content.eyebrow}
            </p>
            <h2 className="mt-4 max-w-4xl font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[2.35rem] font-normal leading-[1.02] tracking-normal text-[#4058b0] sm:text-6xl lg:text-7xl">
              {content.heading}
            </h2>
            <p className="mt-7 max-w-2xl text-base leading-relaxed text-muted sm:text-lg">
              {content.body}
            </p>

            <motion.div
              className="mt-8 grid gap-3 sm:max-w-xl"
              initial={reduceMotion ? false : "hidden"}
              animate={show ? "show" : "hidden"}
              variants={reduceMotion ? undefined : benefitListVariants}
            >
              {content.benefits.map((benefit, index) => (
                <motion.div
                  key={`${index}-${benefit}`}
                  className="group flex min-w-0 items-center gap-3 rounded-lg border border-border bg-white px-4 py-3 shadow-sm transition-all duration-200 hover:-translate-y-0.5 hover:border-[#4058b0]/30 hover:bg-brand-soft/45 hover:shadow-md"
                  variants={reduceMotion ? undefined : benefitItemVariants}
                >
                  <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-brand-soft text-xs font-bold text-brand transition-colors duration-200 group-hover:bg-[#4058b0] group-hover:text-white">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <span className="min-w-0 text-sm font-bold leading-snug text-foreground transition-colors duration-200 group-hover:text-brand sm:text-base">
                    {benefit}
                  </span>
                </motion.div>
              ))}
              <motion.div
                className="mt-3"
                variants={reduceMotion ? undefined : ctaRevealVariants}
              >
                <CtaButton
                  href="#brand-difference"
                  variant="primary"
                  className="px-5 py-2.5 text-sm"
                >
                  {content.ctaLabel}
                </CtaButton>
              </motion.div>
            </motion.div>
          </motion.div>

          <div className="relative min-w-0">
            <SolutionImage show={show} reduceMotion={reduceMotion} />
          </div>
        </div>
      </div>
    </section>
  );
}
