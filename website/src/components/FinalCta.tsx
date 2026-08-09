import { CtaButton } from "./CtaButton";

export function FinalCta() {
  return (
    <section id="cta" className="w-full px-6 py-24 sm:py-28">
      <div className="relative mx-auto max-w-6xl overflow-hidden rounded-3xl bg-brand px-8 py-20 text-center text-white shadow-[0_30px_80px_-40px_rgba(0,30,98,0.65)] sm:px-12 sm:py-24">
        <div
          className="pointer-events-none absolute -right-24 -top-24 h-64 w-64 rounded-full bg-accent/35 blur-3xl"
          aria-hidden="true"
        />
        <div
          className="pointer-events-none absolute -left-24 -bottom-24 h-64 w-64 rounded-full bg-[#485CC7]/45 blur-3xl"
          aria-hidden="true"
        />
        <p className="text-xs font-semibold uppercase tracking-[0.2em] text-white/70">
          Start small. Stay consistent.
        </p>
        <h2 className="mx-auto mt-4 max-w-2xl text-3xl font-semibold leading-[1.15] tracking-tight sm:text-4xl lg:text-5xl">
          Start with one run. Keep going with Runiac.
        </h2>
        <p className="mx-auto mt-5 max-w-xl text-sm leading-relaxed text-white/80 sm:text-base">
          A quieter, more encouraging way to build a running habit — one step
          at a time.
        </p>
        <div className="mt-8 flex justify-center">
          <CtaButton href="#" variant="primary" className="px-7 py-3.5">
            View Prototype
          </CtaButton>
        </div>
      </div>
    </section>
  );
}
