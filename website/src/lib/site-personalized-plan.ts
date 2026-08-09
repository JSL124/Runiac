// Canonical schema, defaults, deep-merge, and validation for the marketing
// site's admin-editable "personalized plan" section
// (config/siteContent.personalizedPlan) — the "Start with a plan made for your
// level" block.
//
// IMPORTANT: this is a marketing section on the website, fully decoupled from
// the real Flutter app screen it depicts. Editing it here never changes the
// app. The card is shown as a screenshot image (imageSrc) so it can mirror the
// real app: when imageSrc is empty the component falls back to its built-in
// illustration, so the live page is unchanged until an admin sets a screenshot.
//
// Pure module (no Firebase / server imports), shared by the marketing render
// layer, the admin console model/mapping, and the save action's validator.

export type SitePersonalizedPlan = {
  eyebrow: string;
  heading: string;
  body: string;
  ctaLabel: string;
  // Screenshot of the real app plan screen — an absolute URL or a path to a
  // file in the site's /public folder. Empty string means "no screenshot set",
  // in which case the component renders its built-in illustration fallback.
  imageSrc: string;
  imageAlt: string;
};

export const DEFAULT_SITE_PERSONALIZED_PLAN: SitePersonalizedPlan = {
  eyebrow: "Personalized plan",
  heading: "Start with a plan made for your level.",
  body: "Runiac uses your goal, fitness level, running experience, and recent activity to create a weekly plan that balances running days, rest days, and realistic progression.",
  ctaLabel: "View Your Plan",
  imageSrc: "",
  imageAlt: "Runiac personalized weekly plan screen",
};

// --- deep-merge over defaults -------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function mergeString(raw: unknown, fallback: string): string {
  return typeof raw === "string" ? raw : fallback;
}

// Per-field deep-merge of an arbitrary stored value over
// DEFAULT_SITE_PERSONALIZED_PLAN. Always returns a fully-populated, render-safe
// object.
export function mergeSitePersonalizedPlan(
  raw: unknown,
): SitePersonalizedPlan {
  const source = isRecord(raw) ? raw : {};
  const defaults = DEFAULT_SITE_PERSONALIZED_PLAN;

  return {
    eyebrow: mergeString(source.eyebrow, defaults.eyebrow),
    heading: mergeString(source.heading, defaults.heading),
    body: mergeString(source.body, defaults.body),
    ctaLabel: mergeString(source.ctaLabel, defaults.ctaLabel),
    // imageSrc defaults to "" (illustration fallback), so a missing value must
    // stay "" rather than inheriting a non-empty default.
    imageSrc: mergeString(source.imageSrc, defaults.imageSrc),
    imageAlt: mergeString(source.imageAlt, defaults.imageAlt),
  };
}

// --- validation (used by the admin save action) -------------------------------

export type SitePersonalizedPlanValidationResult = {
  valid: boolean;
  errors: string[];
};

export function validateSitePersonalizedPlan(
  raw: unknown,
): SitePersonalizedPlanValidationResult {
  const errors: string[] = [];

  if (!isRecord(raw)) {
    return { valid: false, errors: ["Personalized plan content is missing."] };
  }

  const requireNonEmpty = (value: unknown, label: string) => {
    if (typeof value !== "string" || value.trim().length === 0) {
      errors.push(`${label} must not be empty.`);
    }
  };

  requireNonEmpty(raw.eyebrow, "Personalized plan eyebrow");
  requireNonEmpty(raw.heading, "Personalized plan heading");
  requireNonEmpty(raw.body, "Personalized plan body");
  requireNonEmpty(raw.ctaLabel, "Personalized plan CTA label");

  // imageSrc is optional (empty = use the illustration fallback), but when set
  // it must be a string that looks like a URL or a root-relative /public path.
  if (raw.imageSrc !== undefined && raw.imageSrc !== null) {
    if (typeof raw.imageSrc !== "string") {
      errors.push("Screenshot image source must be text.");
    } else {
      const trimmed = raw.imageSrc.trim();
      if (
        trimmed.length > 0 &&
        !/^https?:\/\//.test(trimmed) &&
        !trimmed.startsWith("/")
      ) {
        errors.push(
          "Screenshot image source must be a URL (https://…) or a /public path (/…).",
        );
      }
    }
  }

  return { valid: errors.length === 0, errors };
}
