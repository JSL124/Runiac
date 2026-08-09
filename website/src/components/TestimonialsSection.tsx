"use client";

import type { CSSProperties } from "react";
import { useRef } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import {
  arrangeIntoRows,
  initialsFor,
  type SiteTestimonial,
  type SiteTestimonials,
  type TestimonialRow,
} from "@/lib/site-testimonials";

function CardAvatar({ authorName }: { authorName: string }) {
  return (
    <span
      aria-hidden="true"
      className="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-brand-soft text-sm font-black uppercase tracking-wide text-brand"
    >
      {initialsFor(authorName)}
    </span>
  );
}

function TestimonialCard({ testimonial }: { testimonial: SiteTestimonial }) {
  return (
    <figure className="flex w-80 shrink-0 flex-col gap-4 rounded-lg border border-border bg-white p-6 shadow-[0_24px_70px_-56px_rgba(0,30,98,0.38)] sm:w-96">
      <blockquote className="text-base leading-relaxed text-foreground sm:text-lg">
        &ldquo;{testimonial.quote}&rdquo;
      </blockquote>
      <figcaption className="mt-auto flex items-center gap-4">
        <CardAvatar authorName={testimonial.authorName} />
        <span className="min-w-0">
          <span className="block truncate text-base font-bold text-foreground">
            {testimonial.authorName}
          </span>
          {testimonial.authorTitle ? (
            <span className="block truncate text-sm text-muted">
              {testimonial.authorTitle}
            </span>
          ) : null}
        </span>
      </figcaption>
    </figure>
  );
}

function HorizontalScroller({ row }: { row: TestimonialRow }) {
  const animationClass =
    row.direction === "right"
      ? "animate-scroll-horizontal-reverse"
      : "animate-scroll-horizontal";

  return (
    <div className="mask-fade w-full overflow-hidden">
      <div
        className={`flex w-max ${animationClass}`}
        style={{ "--scroll-duration": row.speed } as CSSProperties}
      >
        <div className="flex items-stretch gap-6 px-3">
          {row.items.map((testimonial, index) => (
            <TestimonialCard key={`a-${index}`} testimonial={testimonial} />
          ))}
        </div>
        <div className="flex items-stretch gap-6 px-3" aria-hidden="true">
          {row.items.map((testimonial, index) => (
            <TestimonialCard key={`b-${index}`} testimonial={testimonial} />
          ))}
        </div>
      </div>
    </div>
  );
}

export function TestimonialsSection({ content }: { content: SiteTestimonials }) {
  const sectionRef = useRef(null);
  const reduceMotion = useReducedMotion();
  const isInView = useInView(sectionRef, {
    amount: 0.18,
    margin: "-8% 0px -12% 0px",
  });
  const show = Boolean(isInView || reduceMotion);
  const rows = arrangeIntoRows(content.items);

  return (
    <section
      id="testimonials"
      ref={sectionRef}
      className="w-full max-w-full overflow-hidden bg-background px-6 py-24 sm:py-28 lg:py-32"
    >
      <motion.div
        className="mx-auto max-w-3xl text-center"
        initial={reduceMotion ? false : { opacity: 0, y: 22, filter: "blur(4px)" }}
        animate={
          show
            ? { opacity: 1, y: 0, filter: "blur(0px)" }
            : { opacity: 0, y: 22, filter: "blur(4px)" }
        }
        transition={{ duration: 0.68, ease: [0.22, 1, 0.36, 1] }}
      >
        <p className="text-xs font-semibold uppercase tracking-[0.22em] text-brand sm:text-sm">
          Testimonials
        </p>
        <h2 className="mx-auto mt-4 max-w-3xl break-words font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[1.72rem] font-normal uppercase leading-[1.08] tracking-normal text-[#4058b0] min-[430px]:text-[2.15rem] sm:text-5xl sm:leading-[1.03] lg:text-6xl">
          {content.title}
        </h2>
        {content.subtitle ? (
          <p className="mx-auto mt-7 max-w-2xl text-base leading-relaxed text-muted sm:text-lg">
            {content.subtitle}
          </p>
        ) : null}
      </motion.div>

      <div className="mx-auto mt-12 flex w-full max-w-[92rem] flex-col gap-6">
        {rows.map((row) => (
          <HorizontalScroller key={row.id} row={row} />
        ))}
      </div>
    </section>
  );
}
