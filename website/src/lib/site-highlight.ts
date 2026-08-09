// Shared schema, deep-merge, and validation for the marketing site's
// "split highlight" sections (text on one side, an app-screenshot mockup on the
// other): XP progression, territorial leaderboard, and post-run summary. Each
// mirrors the shape of the personalized-plan section: editable eyebrow /
// heading / body / CTA, plus an optional screenshot (imageSrc) shown inside the
// iPhone frame. When imageSrc is empty the component renders its built-in
// illustration fallback, so the live page is unchanged until an admin sets one.
//
// IMPORTANT: these are marketing depictions of the app, fully decoupled from the
// real Flutter app screens they illustrate. Editing them never changes the app.
//
// Pure module (no Firebase / server imports), shared by the marketing render
// layer, the admin console model/mapping, and the save action's validators.

export type SiteHighlight = {
  eyebrow: string;
  heading: string;
  body: string;
  ctaLabel: string;
  imageSrc: string;
  imageAlt: string;
};

// Post-run summary adds a bullet list and a secondary (non-link) CTA pill.
export type SitePostRunSummary = SiteHighlight & {
  bullets: string[];
  ctaSecondaryLabel: string;
};

// --- shared helpers -----------------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function mergeString(raw: unknown, fallback: string): string {
  return typeof raw === "string" ? raw : fallback;
}

function mergeStringList(raw: unknown, fallback: string[]): string[] {
  if (Array.isArray(raw) && raw.every((item) => typeof item === "string")) {
    return raw as string[];
  }
  return fallback;
}

export function mergeHighlight(
  raw: unknown,
  defaults: SiteHighlight,
): SiteHighlight {
  const source = isRecord(raw) ? raw : {};
  return {
    eyebrow: mergeString(source.eyebrow, defaults.eyebrow),
    heading: mergeString(source.heading, defaults.heading),
    body: mergeString(source.body, defaults.body),
    ctaLabel: mergeString(source.ctaLabel, defaults.ctaLabel),
    // imageSrc defaults to "" (illustration fallback); a missing value stays "".
    imageSrc: mergeString(source.imageSrc, defaults.imageSrc),
    imageAlt: mergeString(source.imageAlt, defaults.imageAlt),
  };
}

export function mergePostRunSummary(
  raw: unknown,
  defaults: SitePostRunSummary,
): SitePostRunSummary {
  const base = mergeHighlight(raw, defaults);
  const source = isRecord(raw) ? raw : {};
  return {
    ...base,
    bullets: mergeStringList(source.bullets, defaults.bullets),
    ctaSecondaryLabel: mergeString(
      source.ctaSecondaryLabel,
      defaults.ctaSecondaryLabel,
    ),
  };
}

// --- validation ---------------------------------------------------------------

export type HighlightValidationResult = {
  valid: boolean;
  errors: string[];
};

function requireNonEmpty(
  errors: string[],
  value: unknown,
  label: string,
): void {
  if (typeof value !== "string" || value.trim().length === 0) {
    errors.push(`${label} must not be empty.`);
  }
}

// imageSrc is optional (empty = illustration fallback), but when set it must be
// an https:// URL or a root-relative /public path.
function validateImageSrc(
  errors: string[],
  value: unknown,
  label: string,
): void {
  if (value === undefined || value === null) {
    return;
  }
  if (typeof value !== "string") {
    errors.push(`${label} screenshot source must be text.`);
    return;
  }
  const trimmed = value.trim();
  if (
    trimmed.length > 0 &&
    !/^https?:\/\//.test(trimmed) &&
    !trimmed.startsWith("/")
  ) {
    errors.push(
      `${label} screenshot source must be a URL (https://…) or a /public path (/…).`,
    );
  }
}

export function validateHighlight(
  raw: unknown,
  label: string,
): HighlightValidationResult {
  const errors: string[] = [];
  if (!isRecord(raw)) {
    return { valid: false, errors: [`${label} content is missing.`] };
  }
  requireNonEmpty(errors, raw.eyebrow, `${label} eyebrow`);
  requireNonEmpty(errors, raw.heading, `${label} heading`);
  requireNonEmpty(errors, raw.body, `${label} body`);
  requireNonEmpty(errors, raw.ctaLabel, `${label} CTA label`);
  validateImageSrc(errors, raw.imageSrc, label);
  return { valid: errors.length === 0, errors };
}

export function validatePostRunSummary(
  raw: unknown,
  label: string,
): HighlightValidationResult {
  const base = validateHighlight(raw, label);
  const errors = [...base.errors];
  if (isRecord(raw)) {
    requireNonEmpty(errors, raw.ctaSecondaryLabel, `${label} secondary CTA`);
    if (!Array.isArray(raw.bullets)) {
      errors.push(`${label} bullets must be a list.`);
    } else {
      raw.bullets.forEach((bullet, index) => {
        if (typeof bullet !== "string" || bullet.trim().length === 0) {
          errors.push(`${label} bullet ${index + 1} must not be empty.`);
        }
      });
    }
  }
  return { valid: errors.length === 0, errors };
}

// --- per-section defaults + bound merge/validate ------------------------------

// The gamified home "adventure map": each weekday is a stepping-stone the runner
// moves along, with the character, streak flame, and today's guided-run tip.
// Beginner-friendly copy — this is what makes daily running feel like a game.
export const DEFAULT_SITE_JOURNEY_MAP: SiteHighlight = {
  eyebrow: "Your running adventure",
  heading: "Every run moves you along the map.",
  body: "Runiac turns your week into a friendly adventure map. Each day is a stepping stone — finish a run to move your character forward, keep your streak flame alive, and see in plain words exactly what today's run is before you head out.",
  ctaLabel: "Start Your Journey",
  imageSrc: "/home-stagemap-screenshot.png",
  imageAlt:
    "Runiac home adventure map showing the week as stepping stones with the runner's character",
};

export const mergeSiteJourneyMap = (raw: unknown) =>
  mergeHighlight(raw, DEFAULT_SITE_JOURNEY_MAP);
export const validateSiteJourneyMap = (raw: unknown) =>
  validateHighlight(raw, "Journey map");

export const DEFAULT_SITE_XP_PROGRESSION: SiteHighlight = {
  eyebrow: "Progression system",
  heading: "Turn every run into XP.",
  body: "Complete your plan, keep your streak alive, and earn XP from every valid run. Runiac turns consistency into levels, progress bars, and shareable achievements.",
  ctaLabel: "See Your Progress",
  imageSrc: "",
  imageAlt: "Runiac XP progression screen",
};

export const mergeSiteXpProgression = (raw: unknown) =>
  mergeHighlight(raw, DEFAULT_SITE_XP_PROGRESSION);
export const validateSiteXpProgression = (raw: unknown) =>
  validateHighlight(raw, "XP progression");

export const DEFAULT_SITE_TERRITORIAL: SiteHighlight = {
  eyebrow: "Territorial leaderboard",
  heading: "Compete with runners around you.",
  body: "Join local leaderboards across Singapore and compare your weekly XP with runners in your area and level division, not against advanced athletes worldwide.",
  ctaLabel: "View Local Rankings",
  imageSrc: "",
  imageAlt: "Runiac territorial leaderboard screen",
};

export const mergeSiteTerritorial = (raw: unknown) =>
  mergeHighlight(raw, DEFAULT_SITE_TERRITORIAL);
export const validateSiteTerritorial = (raw: unknown) =>
  validateHighlight(raw, "Territorial leaderboard");

export const DEFAULT_SITE_POST_RUN_SUMMARY: SitePostRunSummary = {
  eyebrow: "Post-run summary",
  heading: "Understand your run like a story.",
  body: "After each run, Runiac turns your pace, distance, and consistency into simple feedback that helps you understand what went well and what to focus on next.",
  ctaLabel: "Read Your Summary",
  ctaSecondaryLabel: "Beginner-friendly feedback",
  bullets: [
    "Plain-language explanation",
    "Highlights what went well",
    "Suggests a safe next focus",
    "Connects with streak and XP progress",
  ],
  imageSrc: "",
  imageAlt: "Runiac post-run summary screen",
};

export const mergeSitePostRunSummary = (raw: unknown) =>
  mergePostRunSummary(raw, DEFAULT_SITE_POST_RUN_SUMMARY);
export const validateSitePostRunSummary = (raw: unknown) =>
  validatePostRunSummary(raw, "Post-run summary");
