// Canonical schema, defaults, deep-merge, and validation for the marketing
// site's admin-editable "solution" section (config/siteContent.solution) — the
// "Built to keep beginners consistent" block with its numbered benefit list and
// "Learn more" CTA.
//
// Pure module (no Firebase / server imports), shared by the marketing render
// layer (src/lib/site-content.ts, Solution.tsx), the admin console model/mapping
// (src/lib/admin/*), and the save action's validator (src/lib/actions/admin.ts).
// DEFAULT_SITE_SOLUTION equals the literals that used to be hard-coded in
// Solution.tsx. The photograph and the CTA link target stay fixed and are not
// part of this schema (only the CTA label is editable).

export type SiteSolution = {
  eyebrow: string;
  heading: string;
  body: string;
  benefits: string[];
  ctaLabel: string;
};

export const DEFAULT_SITE_SOLUTION: SiteSolution = {
  eyebrow: "The solution",
  heading: "Built to keep beginners consistent.",
  body: "Runiac turns early running into a habit-building journey. Instead of only tracking pace and distance, it gives beginners clear guidance, visible progress, and motivation that feels achievable.",
  benefits: [
    "Personalized running plan",
    "Streak and consistency tracking",
    "Runner Level and XP Progression System",
    "Level-Based Territorial Leaderboard",
  ],
  ctaLabel: "Learn more",
};

// --- deep-merge over defaults -------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function mergeString(raw: unknown, fallback: string): string {
  return typeof raw === "string" ? raw : fallback;
}

// The benefit list is used only when it is an array whose every entry is a
// string; otherwise it falls back to the default list. An intentionally empty
// (but valid) array is respected.
function mergeStringList(raw: unknown, fallback: string[]): string[] {
  if (Array.isArray(raw) && raw.every((item) => typeof item === "string")) {
    return raw as string[];
  }
  return fallback;
}

// Per-field deep-merge of an arbitrary stored value over DEFAULT_SITE_SOLUTION.
// Always returns a fully-populated, render-safe SiteSolution.
export function mergeSiteSolution(raw: unknown): SiteSolution {
  const source = isRecord(raw) ? raw : {};
  const defaults = DEFAULT_SITE_SOLUTION;

  return {
    eyebrow: mergeString(source.eyebrow, defaults.eyebrow),
    heading: mergeString(source.heading, defaults.heading),
    body: mergeString(source.body, defaults.body),
    benefits: mergeStringList(source.benefits, defaults.benefits),
    ctaLabel: mergeString(source.ctaLabel, defaults.ctaLabel),
  };
}

// --- validation (used by the admin save action) -------------------------------

export type SiteSolutionValidationResult = {
  valid: boolean;
  errors: string[];
};

export function validateSiteSolution(
  raw: unknown,
): SiteSolutionValidationResult {
  const errors: string[] = [];

  if (!isRecord(raw)) {
    return { valid: false, errors: ["Solution content is missing."] };
  }

  const requireNonEmpty = (value: unknown, label: string) => {
    if (typeof value !== "string" || value.trim().length === 0) {
      errors.push(`${label} must not be empty.`);
    }
  };

  requireNonEmpty(raw.eyebrow, "Solution eyebrow");
  requireNonEmpty(raw.heading, "Solution heading");
  requireNonEmpty(raw.body, "Solution body");
  requireNonEmpty(raw.ctaLabel, "Solution CTA label");

  if (!Array.isArray(raw.benefits)) {
    errors.push("Solution benefits must be a list.");
    return { valid: errors.length === 0, errors };
  }

  if (raw.benefits.length === 0) {
    errors.push("Add at least one benefit.");
  }

  raw.benefits.forEach((benefit, index) => {
    if (typeof benefit !== "string" || benefit.trim().length === 0) {
      errors.push(`Benefit ${index + 1} must not be empty.`);
    }
  });

  return { valid: errors.length === 0, errors };
}
