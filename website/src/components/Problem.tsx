"use client";

import Image from "next/image";
import { useRef } from "react";
import { motion, useInView, useReducedMotion } from "motion/react";
import {
  Area,
  CartesianGrid,
  LabelList,
  Line,
  LineChart,
  ReferenceDot,
  XAxis,
  YAxis,
} from "recharts";
import { SectionShell } from "./SectionShell";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "./ui/chart";
import { chartAriaLabel, type SiteProblem } from "@/lib/site-problem";

const chartConfig = {
  dropOff: {
    label: "Not retained",
    color: "#4058b0",
  },
} satisfies ChartConfig;

const formatPercentLabel = (value: unknown) =>
  typeof value === "number" ? `${value.toFixed(1)}%` : `${value}%`;

export function Problem({ content }: { content: SiteProblem }) {
  const sectionRef = useRef(null);
  const isInView = useInView(sectionRef, {
    amount: 0.28,
    margin: "-8% 0px -12% 0px",
  });
  const reduceMotion = useReducedMotion();
  const show = Boolean(isInView || reduceMotion);

  // Recharts consumes one flat value per key; dropOff drives the line/label and
  // dropOffArea drives the shaded area (identical values). The highlighted
  // reference dot tracks the final point.
  const dropOffData = content.chartPoints.map((point) => ({
    label: point.label,
    dropOff: point.value,
    dropOffArea: point.value,
  }));
  const lastPoint = content.chartPoints[content.chartPoints.length - 1];

  return (
    <SectionShell
      id="problem"
      containerClassName="pt-0 max-w-[92rem]"
    >
      <div ref={sectionRef} className="space-y-8 sm:space-y-10">
        <article className="overflow-visible">
          <div className="relative grid gap-10 px-0 py-5 sm:py-7 lg:grid-cols-[1.15fr_0.85fr] lg:items-start lg:gap-20 lg:py-8 xl:gap-24">
            <motion.div
              className="min-w-0"
              initial={reduceMotion ? false : { opacity: 0, x: -34, filter: "blur(8px)" }}
              animate={
                show
                  ? { opacity: 1, x: 0, filter: "blur(0px)" }
                  : { opacity: 0, x: -34, filter: "blur(8px)" }
              }
              transition={{
                duration: 0.65,
                ease: [0.22, 1, 0.36, 1],
              }}
            >
              <div className="relative h-[190px] w-full overflow-hidden rounded-lg shadow-lg shadow-[#4058b0]/10 sm:h-[260px] lg:h-[300px] xl:h-[330px]">
                <Image
                  src="/problem-runner-track.jpeg"
                  alt="A runner lying on a track after a difficult run"
                  fill
                  sizes="(min-width: 1024px) 55vw, 100vw"
                  className="object-cover object-[center_38%]"
                />
                <div
                  aria-hidden="true"
                  className="pointer-events-none absolute inset-0 bg-gradient-to-b from-transparent to-background/10"
                />
              </div>

              <div
                className="relative mt-6 min-w-0 sm:mt-7"
                role="img"
                aria-label={chartAriaLabel(content)}
              >
                <motion.div
                  className="overflow-hidden rounded-2xl bg-brand-soft/60 p-2 sm:p-4"
                  initial={reduceMotion ? false : { opacity: 0, y: 20, scale: 0.98 }}
                  animate={
                    show
                      ? { opacity: 1, y: 0, scale: 1 }
                      : { opacity: 0, y: 20, scale: 0.98 }
                  }
                  transition={{
                    delay: reduceMotion ? 0 : 0.38,
                    duration: 0.55,
                    ease: [0.22, 1, 0.36, 1],
                  }}
                >
                <div className="px-3 pt-3 pb-1 sm:px-4 sm:pt-4">
                  <h3 className="text-sm font-semibold uppercase tracking-[0.08em] text-brand">
                    {content.chartTitle}
                  </h3>
                </div>
                <ChartContainer
                  config={chartConfig}
                  className="aspect-[1.28/1] min-h-[330px] min-w-0 w-full sm:aspect-[1.9/1] lg:min-h-[390px]"
                >
                  <LineChart
                    accessibilityLayer
                    data={dropOffData}
                    margin={{ top: 28, right: 26, left: 6, bottom: 22 }}
                  >
                    <defs>
                      <linearGradient id="dropOffFill" x1="0" y1="0" x2="0" y2="1">
                        <stop
                          offset="5%"
                          stopColor="var(--color-dropOff)"
                          stopOpacity={0.18}
                        />
                        <stop
                          offset="95%"
                          stopColor="var(--color-dropOff)"
                          stopOpacity={0.02}
                        />
                      </linearGradient>
                    </defs>
                    <CartesianGrid
                      stroke="#d9dbea"
                      strokeDasharray="4 4"
                      vertical={false}
                    />
                    <XAxis
                      dataKey="label"
                      axisLine={false}
                      tickLine={false}
                      tickMargin={12}
                      interval={0}
                    />
                    <YAxis
                      domain={[0, 100]}
                      ticks={[0, 25, 50, 75, 100]}
                      axisLine={false}
                      tickLine={false}
                      tickMargin={8}
                      width={34}
                      tickFormatter={(value) => `${value}`}
                    />
                    <ChartTooltip
                      cursor={{ stroke: "var(--border)", strokeWidth: 1.5 }}
                      content={(props) => {
                        const { content: _content, ...tooltipProps } = props;

                        return (
                          <ChartTooltipContent
                            {...tooltipProps}
                            payload={props.payload?.filter(
                              (item) => item.dataKey === "dropOff"
                            )}
                            hideLabel
                            formatter={(value) => (
                              <div className="flex min-w-32 items-center justify-between gap-4">
                                <span className="text-muted">Not retained</span>
                                <span className="font-mono font-semibold text-foreground">
                                  {Number(value).toFixed(1)}%
                                </span>
                              </div>
                            )}
                          />
                        );
                      }}
                    />
                    <Area
                      type="monotone"
                      dataKey="dropOffArea"
                      fill="url(#dropOffFill)"
                      stroke="none"
                      tooltipType="none"
                      isAnimationActive={!reduceMotion && show}
                      animationBegin={200}
                      animationDuration={900}
                    />
                    <Line
                      type="monotone"
                      dataKey="dropOff"
                      stroke="var(--color-dropOff)"
                      strokeWidth={5}
                      dot={{ r: 5, fill: "#4058b0", strokeWidth: 0 }}
                      activeDot={{ r: 7, fill: "var(--accent)", strokeWidth: 0 }}
                      isAnimationActive={!reduceMotion && show}
                      animationBegin={120}
                      animationDuration={1200}
                    >
                      <LabelList
                        dataKey="dropOff"
                        position="top"
                        offset={12}
                        formatter={formatPercentLabel}
                        className="fill-foreground text-sm font-bold"
                      />
                    </Line>
                    {lastPoint ? (
                      <ReferenceDot
                        x={lastPoint.label}
                        y={lastPoint.value}
                        r={7}
                        fill="var(--accent)"
                        stroke="var(--accent)"
                      />
                    ) : null}
                  </LineChart>
                </ChartContainer>
                </motion.div>
              </div>
            </motion.div>

            <motion.aside
              className="min-w-0 text-left lg:pl-4 xl:pl-8"
              initial={reduceMotion ? false : { opacity: 0, x: 34, filter: "blur(8px)" }}
              animate={
                show
                  ? { opacity: 1, x: 0, filter: "blur(0px)" }
                  : { opacity: 0, x: 34, filter: "blur(8px)" }
              }
              transition={{
                delay: reduceMotion ? 0 : 0.16,
                duration: 0.65,
                ease: [0.22, 1, 0.36, 1],
              }}
            >
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand sm:text-sm">
                {content.eyebrow}
              </p>
              <h3 className="mt-4 font-['Sprintura_Demo',var(--font-inter),sans-serif] text-3xl font-normal leading-[1.05] tracking-normal text-[#4058b0] sm:text-4xl lg:text-5xl">
                {content.heading}
              </h3>
              <div className="relative mt-6 h-[260px] max-w-[460px] overflow-hidden rounded-lg shadow-xl shadow-[#4058b0]/10 sm:h-[340px] lg:h-[360px] xl:h-[420px]">
                <Image
                  src="/problem-runner-recovery.jpeg"
                  alt="Runners recovering with water after a difficult run"
                  fill
                  sizes="(min-width: 1280px) 460px, (min-width: 1024px) 36vw, 100vw"
                  className="object-cover object-center"
                />
                <div
                  aria-hidden="true"
                  className="pointer-events-none absolute inset-0 bg-gradient-to-b from-background/10 to-transparent"
                />
              </div>
              <p className="mt-6 max-w-xl text-base leading-relaxed text-muted sm:text-lg">
                {content.body}
              </p>
              {content.source ? (
                <p className="mt-7 text-xs leading-relaxed text-muted">
                  {content.source}
                </p>
              ) : null}
            </motion.aside>
          </div>
        </article>
      </div>
    </SectionShell>
  );
}
