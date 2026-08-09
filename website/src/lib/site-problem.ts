// Canonical schema, defaults, deep-merge, and validation for the marketing
// site's admin-editable "problem" section (config/siteContent.problem) — the
// "Most beginners stop in the first few weeks" block with its Early Drop-off
// chart at the top of the home page.
//
// Pure module (no Firebase / server imports), shared by the marketing render
// layer (src/lib/site-content.ts, Problem.tsx), the admin console model/mapping
// (src/lib/admin/*), and the save action's validator (src/lib/actions/admin.ts)
// — mirrors src/lib/site-pricing.ts / src/lib/site-testimonials.ts.
//
// DEFAULT_SITE_PROBLEM equals the literals that used to be hard-coded in
// Problem.tsx, so a missing/partial/malformed document renders exactly the same
// section as before. The two photographs stay fixed public assets and are not
// part of this schema.

export type ProblemChartPoint = {
  label: string;
  value: number;
};

export type SiteProblem = {
  eyebrow: string;
  heading: string;
  body: string;
  source: string;
  chartTitle: string;
  chartPoints: ProblemChartPoint[];
};

export const DEFAULT_SITE_PROBLEM: SiteProblem = {
  eyebrow: "The problem",
  heading: "Most Beginners stop in the first few weeks.",
  body: "Many new runners quit early because progress feels unclear, motivation drops, and traditional running apps focus more on performance than persistence.",
  source: "Source: OneSignal Mobile App Benchmarks 2024, Health & Fitness category.",
  chartTitle: "Early Drop-off Trend",
  chartPoints: [
    { label: "Install", value: 0 },
    { label: "Day 1", value: 72 },
    { label: "Day 7", value: 81.9 },
    { label: "Day 30", value: 91.5 },
  ],
};

// --- deep-merge over defaults -------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function mergeString(raw: unknown, fallback: string): string {
  return typeof raw === "string" ? raw : fallback;
}

// The chart points are used only when the stored value is an array whose every
// entry has a string label and a finite numeric value; otherwise it falls back
// to the default series so the chart never renders broken.
function mergeChartPoints(
  raw: unknown,
  fallback: ProblemChartPoint[],
): ProblemChartPoint[] {
  if (!Array.isArray(raw)) {
    return fallback;
  }

  const cleaned: ProblemChartPoint[] = [];
  for (const entry of raw) {
    if (
      isRecord(entry) &&
      typeof entry.label === "string" &&
      typeof entry.value === "number" &&
      Number.isFinite(entry.value)
    ) {
      cleaned.push({ label: entry.label, value: entry.value });
    } else {
      // Any malformed point invalidates the whole series (a chart with a
      // dropped point would be misleading), so fall back to the default.
      return fallback;
    }
  }

  return cleaned.length > 0 ? cleaned : fallback;
}

// Per-field deep-merge of an arbitrary stored value over DEFAULT_SITE_PROBLEM.
// Always returns a fully-populated, render-safe SiteProblem.
export function mergeSiteProblem(raw: unknown): SiteProblem {
  const source = isRecord(raw) ? raw : {};
  const defaults = DEFAULT_SITE_PROBLEM;

  return {
    eyebrow: mergeString(source.eyebrow, defaults.eyebrow),
    heading: mergeString(source.heading, defaults.heading),
    body: mergeString(source.body, defaults.body),
    source: mergeString(source.source, defaults.source),
    chartTitle: mergeString(source.chartTitle, defaults.chartTitle),
    chartPoints: mergeChartPoints(source.chartPoints, defaults.chartPoints),
  };
}

// Screen-reader summary for the chart, built from the current points so it
// stays accurate when an admin edits them.
export function chartAriaLabel(problem: SiteProblem): string {
  const series = problem.chartPoints
    .map((point) => `${point.label} ${point.value}%`)
    .join(", ");
  return `${problem.chartTitle}: ${series}.`;
}

// --- validation (used by the admin save action) -------------------------------

export type SiteProblemValidationResult = {
  valid: boolean;
  errors: string[];
};

export function validateSiteProblem(
  raw: unknown,
): SiteProblemValidationResult {
  const errors: string[] = [];

  if (!isRecord(raw)) {
    return { valid: false, errors: ["Problem content is missing."] };
  }

  const requireNonEmpty = (value: unknown, label: string) => {
    if (typeof value !== "string" || value.trim().length === 0) {
      errors.push(`${label} must not be empty.`);
    }
  };

  requireNonEmpty(raw.eyebrow, "Problem eyebrow");
  requireNonEmpty(raw.heading, "Problem heading");
  requireNonEmpty(raw.body, "Problem body");
  requireNonEmpty(raw.chartTitle, "Chart title");

  if (!Array.isArray(raw.chartPoints)) {
    errors.push("Chart points must be a list.");
    return { valid: errors.length === 0, errors };
  }

  if (raw.chartPoints.length < 2) {
    errors.push("Add at least two chart points.");
  }

  raw.chartPoints.forEach((point, index) => {
    const position = index + 1;
    if (!isRecord(point)) {
      errors.push(`Chart point ${position} is invalid.`);
      return;
    }
    if (typeof point.label !== "string" || point.label.trim().length === 0) {
      errors.push(`Chart point ${position} label must not be empty.`);
    }
    if (
      typeof point.value !== "number" ||
      !Number.isFinite(point.value) ||
      point.value < 0 ||
      point.value > 100
    ) {
      errors.push(`Chart point ${position} value must be between 0 and 100.`);
    }
  });

  return { valid: errors.length === 0, errors };
}
