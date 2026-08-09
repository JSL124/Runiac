"use client";

import { useRef, useState } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import { CtaButton } from "./CtaButton";
import { DEFAULT_SITE_PRICING, type SitePricing } from "@/lib/site-pricing";

type BillingCycle = "monthly" | "annual";

// Billing toggle labels and the two static column headers remain fixed page
// chrome (not admin-editable); everything inside the cards is driven by the
// admin-configurable SitePricing content below.
const billingOptions: { label: string; value: BillingCycle }[] = [
  { label: "Monthly", value: "monthly" },
  { label: "Annual", value: "annual" },
];

// The pricing cards render this structured content. It maps 1:1 to
// config/siteContent.pricing; when a caller omits it (or omits any field), the
// literal defaults keep the page identical to before.
export type PricingSectionContent = SitePricing;

function CheckIcon() {
  return (
    <svg
      width="14"
      height="14"
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

function FeatureList({ items }: { items: string[] }) {
  return (
    <ul className="mt-4 space-y-2.5 text-sm font-semibold leading-relaxed text-muted">
      {items.map((item) => (
        <li key={item} className="flex min-w-0 items-start gap-3">
          <span className="mt-1 grid h-5 w-5 shrink-0 place-items-center text-accent">
            <CheckIcon />
          </span>
          <span className="break-words">{item}</span>
        </li>
      ))}
    </ul>
  );
}

type PricingSectionProps = {
  showIntro?: boolean;
  content?: PricingSectionContent;
};

export function PricingSection({ showIntro = true, content }: PricingSectionProps) {
  const sectionRef = useRef(null);
  const [billingCycle, setBillingCycle] = useState<BillingCycle>("monthly");
  const reduceMotion = useReducedMotion();
  const isInView = useInView(sectionRef, {
    amount: 0.18,
    margin: "-8% 0px -12% 0px",
  });
  const show = Boolean(isInView || reduceMotion);
  const pricing = content ?? DEFAULT_SITE_PRICING;
  const free = pricing.free;
  const premium = pricing.premium;
  const selectedPremiumPrice = premium.premiumPrice[billingCycle];

  return (
    <section
      id="pricing"
      ref={sectionRef}
      className={`w-full max-w-full overflow-hidden bg-background px-6 ${
        showIntro
          ? "py-24 sm:py-28 lg:py-32"
          : "pb-24 pt-8 sm:pb-28 sm:pt-10 lg:pb-32 lg:pt-12"
      }`}
    >
      <div className="mx-auto w-full max-w-[92rem]">
        {showIntro && (
          <motion.div
            className="mx-auto max-w-4xl text-center"
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
              duration: 0.68,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            <p className="text-xs font-semibold uppercase tracking-[0.22em] text-brand sm:text-sm">
              PRICING
            </p>
            <h2 className="mx-auto mt-4 max-w-[22rem] break-words font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[1.72rem] font-normal uppercase leading-[1.08] tracking-normal text-[#4058b0] min-[430px]:text-[2.15rem] sm:max-w-4xl sm:text-6xl sm:leading-[1.03] lg:text-7xl">
              GO FURTHER WITH PREMIUM.
            </h2>
            <p className="mx-auto mt-7 max-w-3xl text-base leading-relaxed text-muted sm:text-lg">
              Runiac keeps the core habit-building experience free, while Premium
              adds deeper insights, milestone preparation, and richer feedback for
              runners who are ready for more.
            </p>
          </motion.div>
        )}

        <motion.div
          className={`mx-auto flex max-w-md rounded-[1.1rem] bg-[#f1f0ee] p-1 shadow-inner transition-all duration-300 hover:bg-[#eceae7] hover:shadow-[0_18px_50px_-38px_rgba(0,0,0,0.72)] hover:ring-1 hover:ring-black/10 ${
            showIntro ? "mt-9" : ""
          }`}
          initial={reduceMotion ? false : { opacity: 0, y: 18, scale: 0.98 }}
          animate={
            show
              ? { opacity: 1, y: 0, scale: 1 }
              : { opacity: 0, y: 18, scale: 0.98 }
          }
          whileHover={reduceMotion ? undefined : { y: -2 }}
          transition={{
            delay: reduceMotion ? 0 : 0.14,
            duration: 0.55,
            ease: [0.22, 1, 0.36, 1],
          }}
        >
          {billingOptions.map((option) => {
            const isSelected = billingCycle === option.value;

            return (
              <button
                key={option.value}
                type="button"
                aria-pressed={isSelected}
                onClick={() => setBillingCycle(option.value)}
                className={`min-w-0 flex-1 rounded-[0.9rem] px-5 py-3 text-sm font-black transition-all sm:text-base ${
                  isSelected
                    ? "bg-white text-foreground shadow-[0_8px_24px_-18px_rgba(0,16,20,0.65)] ring-1 ring-black/5"
                    : "text-muted hover:text-foreground"
                }`}
              >
                {option.label}
              </button>
            );
          })}
        </motion.div>

        <div className="mx-auto mt-8 grid max-w-4xl gap-5 lg:grid-cols-2">
          <motion.article
            className="flex min-w-0 flex-col overflow-hidden rounded-[1.25rem] border border-border bg-white shadow-[0_24px_70px_-56px_rgba(0,30,98,0.38)] transition-colors duration-300 hover:border-brand/30 hover:shadow-[0_34px_86px_-58px_rgba(0,30,98,0.45)]"
            initial={reduceMotion ? false : { opacity: 0, x: -22, y: 20, scale: 0.98 }}
            animate={
              show
                ? { opacity: 1, x: 0, y: 0, scale: 1 }
                : { opacity: 0, x: -22, y: 20, scale: 0.98 }
            }
            whileHover={reduceMotion ? undefined : { y: -8, scale: 1.01 }}
            transition={{
              delay: reduceMotion ? 0 : 0.24,
              duration: 0.65,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            <div className="flex flex-col p-5 sm:p-6 lg:min-h-[24rem]">
              <div>
                <span className="inline-flex rounded-full bg-brand-soft px-3 py-1 text-[11px] font-black uppercase tracking-[0.14em] text-brand">
                  {free.badge}
                </span>
                <h3 className="mt-4 text-2xl font-black leading-none text-foreground sm:text-3xl">
                  {free.title}
                </h3>
                <p className="mt-2 text-base font-semibold leading-snug text-muted">
                  {free.subtitle}
                </p>
              </div>

              <div className="mt-6 flex flex-wrap items-end gap-x-3 gap-y-1">
                <p className="text-4xl font-black leading-none text-foreground sm:text-5xl">
                  {free.price}
                </p>
                <p className="pb-1 text-sm font-semibold text-muted">
                  {free.priceNote}
                </p>
              </div>

            </div>

            <div className="border-t border-border bg-white px-5 py-5 sm:px-6">
              <p className="text-xs font-black uppercase tracking-[0.12em] text-foreground">
                Included in Free
              </p>
              <FeatureList items={free.features} />
            </div>
          </motion.article>

          <motion.article
            className="flex min-w-0 flex-col overflow-hidden rounded-[1.25rem] border border-border bg-white shadow-[0_24px_70px_-56px_rgba(0,30,98,0.38)] transition-colors duration-300 hover:border-accent/35 hover:shadow-[0_34px_86px_-58px_rgba(242,106,61,0.42)]"
            initial={reduceMotion ? false : { opacity: 0, x: 22, y: 20, scale: 0.98 }}
            animate={
              show
                ? { opacity: 1, x: 0, y: 0, scale: 1 }
                : { opacity: 0, x: 22, y: 20, scale: 0.98 }
            }
            whileHover={reduceMotion ? undefined : { y: -8, scale: 1.01 }}
            transition={{
              delay: reduceMotion ? 0 : 0.32,
              duration: 0.65,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            <div className="flex flex-col p-5 sm:p-6 lg:min-h-[24rem]">
              <div>
                <span className="inline-flex rounded-full bg-accent px-3 py-1 text-[11px] font-black uppercase tracking-[0.14em] text-white">
                  {premium.badge}
                </span>
                <h3 className="mt-4 text-2xl font-black leading-none text-foreground sm:text-3xl">
                  {premium.title}
                </h3>
                <p className="mt-2 text-base font-semibold leading-snug text-muted">
                  {premium.subtitle}
                </p>
              </div>

              <div className="mt-6">
                <motion.div
                  key={billingCycle}
                  className="flex flex-wrap items-end gap-x-3 gap-y-1"
                  initial={reduceMotion ? false : { opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{
                    duration: 0.24,
                    ease: [0.22, 1, 0.36, 1],
                  }}
                >
                  <p className="text-4xl font-black leading-none text-foreground sm:text-5xl">
                    {selectedPremiumPrice.price}
                  </p>
                  <p className="pb-1 text-base font-bold text-muted">
                    {selectedPremiumPrice.period}
                  </p>
                </motion.div>
                <div className="mt-4 grid gap-2.5 text-sm font-black text-muted">
                  <motion.div
                    key={selectedPremiumPrice.note}
                    className="rounded-lg border border-border bg-white px-4 py-3"
                    initial={reduceMotion ? false : { opacity: 0, y: 6 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{
                      duration: 0.24,
                      ease: [0.22, 1, 0.36, 1],
                    }}
                  >
                    {selectedPremiumPrice.note}
                  </motion.div>
                </div>
              </div>

              <div className="mt-auto pt-6">
                <CtaButton
                  href="#cta"
                  variant="primary"
                  className="w-full px-6 py-3"
                >
                  {premium.ctaLabel}
                </CtaButton>
              </div>
            </div>

            <div className="border-t border-border bg-white px-5 py-5 sm:px-6">
              <p className="text-xs font-black uppercase tracking-[0.12em] text-foreground">
                Premium adds
              </p>
              <FeatureList items={premium.features} />
            </div>
          </motion.article>
        </div>
      </div>
    </section>
  );
}
