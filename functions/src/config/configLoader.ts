import type { Firestore } from "firebase-admin/firestore";
import { reportBackendError } from "../errors/reportBackendError.js";

export type ProgressionCoolDownConfig = {
  readonly percent: number;
  readonly min: number;
  readonly max: number;
};

export type StreakRewardConfig = {
  readonly milestoneDays: number;
  readonly bonusXp: number;
};

export type ProgressionConfig = {
  readonly baseCompletionXp: number;
  readonly xpPerKilometer: number;
  readonly xpPerTenActiveMinutes: number;
  readonly planCompletionBonusXp: number;
  readonly activityXpCap: number;
  readonly dailyXpCap: number;
  readonly premiumEarnsXp: boolean;
  readonly maxLevel: number;
  readonly coolDown: ProgressionCoolDownConfig;
  readonly levelIncrements: readonly number[];
  readonly streakRewards: readonly StreakRewardConfig[];
  readonly version: number;
};

export type LeaderboardConfig = {
  readonly minRunsToQualify: number;
  readonly excludePremium: boolean;
  readonly seasonLengthDays: number;
  readonly version: number;
};

export type FeatureAccessEntry = {
  readonly minimumTier: "basic" | "premium";
  readonly enabled: boolean;
};

export type FeatureAccessConfig = {
  readonly features: Readonly<Record<string, FeatureAccessEntry>>;
  readonly version: number;
};

export type AutomationConfig = {
  readonly autoHide: { readonly enabled: boolean; readonly reportThreshold: number };
  readonly staleReportEscalation: { readonly enabled: boolean; readonly pendingDays: number };
  readonly scheduled: {
    readonly leaderboardSnapshotRefresh: boolean;
    readonly subscriptionExpirySweep: boolean;
    readonly pushNotificationDispatch: boolean;
  };
  readonly notifications: {
    readonly notifyErrorGroups: boolean;
    readonly minimumErrorSeverity: "high" | "critical";
    readonly notifyNewReports: boolean;
  };
  readonly version: number;
};

// Which Challenge tiers require a premium subscription to CREATE a lobby for.
// Tier ids must match the nine-tier catalog in challenge/challengeCatalog.ts.
// Challenges award badges only — never XP, level, rank, or leaderboard score —
// so tier gating sells difficulty-tier access without touching competitive
// standing (the premium-parity rule).
export type ChallengeAccessConfig = {
  readonly premiumOnlyTiers: readonly string[];
  readonly version: number;
};

// Which guide characters require a premium subscription to SELECT. Character
// ids must match the four-value RunnerCharacter enum in the app
// (core/characters/runner_character.dart): blue (Bolt), cap (Cap), pink (Mila),
// purple (Ivy). The character is display-only cosmetic personalization — it is
// stored locally on the device and never writes XP, level, rank, streak, or
// leaderboard score — so this gate sells presentation value only and is
// enforced client-side (there is no server operation to protect, unlike
// shareRouteToFeed or challenge lobby creation). This doc exists so the admin
// console can reconfigure which characters are premium.
export type CharacterAccessConfig = {
  readonly premiumOnlyCharacters: readonly string[];
  readonly version: number;
};

export type ConfigValidationResult = {
  readonly valid: boolean;
  readonly errors: readonly string[];
};

// The DEFAULT_* constants are handed out directly (the validation fallback
// returns them, `deepMerge` copies only the top level so an untouched nested
// key like `coolDown` is still the constant's own object, and the per-field
// repair resets to them). Anything that mutated one would corrupt the defaults
// for the lifetime of the Functions instance — a process-wide change caused by
// a single request. They are `readonly` in the type system, which is erased at
// runtime, so freeze them for real.
function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const nested of Object.values(value as Record<string, unknown>)) {
      deepFreeze(nested);
    }
  }
  return value;
}

export const DEFAULT_PROGRESSION_CONFIG: ProgressionConfig = deepFreeze({
  baseCompletionXp: 20,
  xpPerKilometer: 10,
  xpPerTenActiveMinutes: 5,
  planCompletionBonusXp: 20,
  activityXpCap: 100,
  dailyXpCap: 200,
  // Premium buys coaching, analysis, and presentation value — never a
  // competitive edge. Premium runners therefore earn XP under exactly the same
  // rules as Basic runners; suppressing it instead froze their level, division,
  // and leaderboard standing, which reads as a penalty for paying.
  premiumEarnsXp: true,
  maxLevel: 100,
  coolDown: {
    percent: 0.2,
    min: 5,
    max: 20,
  },
  levelIncrements: [100, 150, 220, 300, 400, 520, 660, 820, 1000, 1200],
  streakRewards: [
    { milestoneDays: 3, bonusXp: 30 },
    { milestoneDays: 7, bonusXp: 90 },
    { milestoneDays: 14, bonusXp: 220 },
    { milestoneDays: 30, bonusXp: 600 },
  ],
  version: 1,
});

export const DEFAULT_LEADERBOARD_CONFIG: LeaderboardConfig = deepFreeze({
  minRunsToQualify: 1,
  // Paired with `premiumEarnsXp: true`: premium runners accrue XP normally, so
  // they rank on the same board under the same formula. Flipping this to `true`
  // without also clearing `premiumEarnsXp` would rank them at a permanent zero.
  excludePremium: false,
  seasonLengthDays: 30,
  version: 1,
});

// Catalog of premium-convertible features administered via the console,
// grounded in the app's real user-facing surface (audited 2026-07-22 against
// mobile/). Only features that may legitimately differ by subscription tier
// are listed: leaderboard, challenges, feed, friends, run tracking,
// cool-down, and XP/progress surfaces are deliberately ABSENT because premium
// must never change competitive standing or gate core beginner/social
// infrastructure.
//
// `goalPlan` was RETIRED from this catalog on 2026-07-25: the
// onboarding-generated beginner plan is the app's core beginner experience,
// which premium must never gate, so offering the admin a switch that could
// move it to Premium was itself the risk.
//
// `healthWorkoutImport` was RETIRED on 2026-08-13 for the opposite reason:
// there is nothing left to gate. `65b41c49` ("remove the unimplemented
// HealthKit import surface") deleted the whole surface — the
// RuniacHealthKitImportChannel method channel, the HealthKit entitlement,
// AppleHealthWorkoutImportRepository and its mock, the imported-workout
// mapper, and the Watch and Health Apps screen — so no code has read this key
// since. A catalog entry with no gate behind it is worse than no entry: the
// console rendered a tier control that silently did nothing, which is exactly
// the "hiding UI is not enforcement" failure the tier model exists to avoid.
// Re-add it in the same commit that re-adds a real import gate, never before.
//
// Every remaining key is wired to a real gate — a console flip changes what
// the app does, not just what the upsell lists:
//   - advancedAnalysis  client-only gate (analysis is computed on-device);
//                       also governs the post-run coaching card
//   - aiHomeCoach       homeGuideAgent callable; a denied Basic runner keeps
//                       the app's offline rule-based guide copy
//   - activityFeedback  activityFeedbackAgent callable
//   - workoutBriefing   workoutBriefingAgent callable; the sparkle explainer on
//                       a planned workout's detail screen. A denied Basic
//                       runner still sees the whole session — metrics,
//                       breakdown, effort guide — because the briefing explains
//                       that screen rather than unlocking it.
//   - shareRouteToFeed  publishActivityToFeed callable
//   - shareCards        client-only gate (achievement + rank card exports)
// Server-side gating goes through assertFeatureEntitlement()
// (config/featureEntitlement.ts); the app applies the identical rule for its
// paywall interception, which is UX only.
export const DEFAULT_FEATURE_ACCESS_CONFIG: FeatureAccessConfig = deepFreeze({
  features: {
    advancedAnalysis: { minimumTier: "premium", enabled: true },
    // "premium" as of 2026-07-29. The AI home coach is the second of the two
    // OpenAI-backed features, and a "basic" default meant every consenting
    // Basic runner spent model calls on the ambient Home bubble. Basic now
    // gets the on-device plan read-out (PlanBriefHomeGuideAgent) instead,
    // which composes the same plan copy with no network call. This remains a
    // console-flippable tier by deliberate choice: setting it back to "basic"
    // re-opens the AI guide — and the OpenAI spend — for Basic accounts.
    aiHomeCoach: { minimumTier: "premium", enabled: true },
    // "premium" as of 2026-07-25: the callable used to hardcode a premium
    // check that overrode this catalog, so a "basic" default would have
    // handed every Basic runner a paid AI feature the moment the hardcode
    // was replaced by the config read. The default now states the shipped
    // intent; the console can open it deliberately.
    activityFeedback: { minimumTier: "premium", enabled: true },
    // "premium" from the day it shipped (2026-07-29). This is the third
    // OpenAI-backed feature, and it is the only one a runner can invoke
    // repeatedly without first completing a run, so a "basic" default would
    // have opened model spend on the most reachable surface in the app.
    workoutBriefing: { minimumTier: "premium", enabled: true },
    // "basic" as of 2026-08-05, correcting a default that had contradicted
    // production since 2026-07-25: the live `config/featureAccess` document
    // has stored "basic" for this key since then, and deepMerge means the
    // stored value wins, so the "premium" default described an environment
    // that does not exist. Sharing a completed run to the Feed is core social
    // participation rather than a paid convenience — unlike the three
    // OpenAI-backed keys above, it costs no model spend — so Basic keeps it.
    // Still console-flippable: setting "premium" re-locks publishing
    // immediately, with no redeploy.
    shareRouteToFeed: { minimumTier: "basic", enabled: true },
    shareCards: { minimumTier: "basic", enabled: true },
  },
  version: 1,
});

export const DEFAULT_AUTOMATION_CONFIG: AutomationConfig = deepFreeze({
  autoHide: {
    enabled: false,
    reportThreshold: 3,
  },
  staleReportEscalation: {
    enabled: true,
    pendingDays: 7,
  },
  // Every scheduled sweep defaults to running. Automation gating exists so an
  // admin can pause a single sweep during an incident, not so a fresh
  // environment starts with platform automation silently off.
  scheduled: {
    leaderboardSnapshotRefresh: true,
    subscriptionExpirySweep: true,
    pushNotificationDispatch: true,
  },
  notifications: {
    notifyErrorGroups: true,
    minimumErrorSeverity: "critical",
    notifyNewReports: false,
  },
  version: 1,
});

// The first three tiers (10K, 20K, 42K) stay open to every account; the six
// higher tiers require premium (user decision 2026-07-23). Enforced at lobby
// creation in challenge/challengeLobbyCore.ts.
export const DEFAULT_CHALLENGE_ACCESS_CONFIG: ChallengeAccessConfig = deepFreeze({
  premiumOnlyTiers: ["100K", "200K", "250K", "300K", "500K", "1000K"],
  version: 1,
});

// Bolt (blue) and Mila (pink) stay open to every account; Cap (cap) and Ivy
// (purple) require premium (user decision 2026-07-24). Enforced client-side in
// the character picker — a cosmetic, device-local choice has no server value to
// protect.
export const DEFAULT_CHARACTER_ACCESS_CONFIG: CharacterAccessConfig = deepFreeze({
  premiumOnlyCharacters: ["cap", "purple"],
  version: 1,
});

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Merges `partial` over `defaults`, field by field. Nested plain objects are
 * merged recursively so that omitted nested fields fall back to the default
 * value (e.g. a stored `{ coolDown: { percent: 0.3 } }` keeps the default
 * `coolDown.min`/`coolDown.max`). Arrays are replaced wholesale, never merged
 * element-by-element.
 */
export function deepMerge<T>(defaults: T, partial: unknown): T {
  if (!isPlainObject(partial) || !isPlainObject(defaults)) {
    return defaults;
  }

  const merged: Record<string, unknown> = { ...(defaults as Record<string, unknown>) };

  for (const key of Object.keys(partial)) {
    const partialValue = partial[key];
    const defaultValue = (defaults as Record<string, unknown>)[key];

    if (partialValue === undefined) {
      continue;
    }

    if (isPlainObject(defaultValue) && isPlainObject(partialValue)) {
      merged[key] = deepMerge(defaultValue, partialValue);
    } else {
      merged[key] = partialValue;
    }
  }

  return merged as T;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

export function validateProgressionConfig(config: ProgressionConfig): ConfigValidationResult {
  const errors: string[] = [];

  const nonNegativeFields: Array<[string, number]> = [
    ["baseCompletionXp", config.baseCompletionXp],
    ["xpPerKilometer", config.xpPerKilometer],
    ["xpPerTenActiveMinutes", config.xpPerTenActiveMinutes],
    ["planCompletionBonusXp", config.planCompletionBonusXp],
    ["activityXpCap", config.activityXpCap],
    ["dailyXpCap", config.dailyXpCap],
  ];

  for (const [name, value] of nonNegativeFields) {
    if (!isFiniteNumber(value) || value < 0) {
      errors.push(`${name} must be a non-negative finite number`);
    }
  }

  if (isFiniteNumber(config.dailyXpCap) && isFiniteNumber(config.activityXpCap) && config.dailyXpCap < config.activityXpCap) {
    errors.push("dailyXpCap must be greater than or equal to activityXpCap");
  }

  if (!isFiniteNumber(config.maxLevel) || config.maxLevel <= 0) {
    errors.push("maxLevel must be a positive finite number");
  }

  if (!isPlainObject(config.coolDown)) {
    errors.push("coolDown must be an object");
  } else {
    const { percent, min, max } = config.coolDown;

    if (!isFiniteNumber(percent) || percent < 0 || percent > 1) {
      errors.push("coolDown.percent must be between 0 and 1");
    }

    if (!isFiniteNumber(min) || !isFiniteNumber(max) || min > max) {
      errors.push("coolDown.min must be less than or equal to coolDown.max");
    }
  }

  if (!Array.isArray(config.levelIncrements) || config.levelIncrements.length === 0) {
    errors.push("levelIncrements must be a non-empty array");
  } else if (!config.levelIncrements.every((increment) => isFiniteNumber(increment) && increment > 0)) {
    errors.push("levelIncrements must contain only finite positive numbers");
  }

  // Same reasoning as excludePremium: a stored "false" string would be truthy
  // and silently keep premium XP suppressed, or a stored 0 would silently
  // suppress it, with no error surfaced to the admin who saved it.
  if (typeof config.premiumEarnsXp !== "boolean") {
    errors.push("premiumEarnsXp must be a boolean");
  }

  if (!Array.isArray(config.streakRewards)) {
    errors.push("streakRewards must be an array");
  } else {
    let previousMilestoneDays: number | undefined;

    for (const [index, reward] of config.streakRewards.entries()) {
      if (!isPlainObject(reward)) {
        errors.push(`streakRewards[${index}] must be an object`);
        continue;
      }

      const milestoneDays = reward["milestoneDays"];
      const bonusXp = reward["bonusXp"];

      if (!isFiniteNumber(milestoneDays) || !Number.isInteger(milestoneDays) || milestoneDays < 1) {
        errors.push(`streakRewards[${index}].milestoneDays must be an integer greater than or equal to 1`);
      } else {
        if (previousMilestoneDays !== undefined && milestoneDays <= previousMilestoneDays) {
          errors.push(`streakRewards[${index}].milestoneDays must be greater than the previous milestoneDays`);
        }

        previousMilestoneDays = milestoneDays;
      }

      if (!isFiniteNumber(bonusXp) || bonusXp < 0) {
        errors.push(`streakRewards[${index}].bonusXp must be a non-negative finite number`);
      }
    }
  }

  return { valid: errors.length === 0, errors };
}

export function validateLeaderboardConfig(config: LeaderboardConfig): ConfigValidationResult {
  const errors: string[] = [];

  if (!isFiniteNumber(config.minRunsToQualify) || config.minRunsToQualify < 0) {
    errors.push("minRunsToQualify must be a non-negative finite number");
  }

  if (!isFiniteNumber(config.seasonLengthDays) || config.seasonLengthDays <= 0) {
    errors.push("seasonLengthDays must be a positive finite number");
  }

  // Type-checked explicitly because deepMerge passes stored values through
  // verbatim and this flag is read as a plain truthiness test. A Firestore
  // write of the STRING "false" is truthy, which would silently switch premium
  // exclusion back on with no error anywhere.
  if (typeof config.excludePremium !== "boolean") {
    errors.push("excludePremium must be a boolean");
  }

  return { valid: errors.length === 0, errors };
}

export function validateFeatureAccessConfig(config: FeatureAccessConfig): ConfigValidationResult {
  const errors: string[] = [];

  if (!isPlainObject(config.features)) {
    errors.push("features must be an object");
    return { valid: false, errors };
  }

  for (const [featureName, entry] of Object.entries(config.features)) {
    if (!isPlainObject(entry)) {
      errors.push(`features.${featureName} must be an object`);
      continue;
    }

    if (entry["minimumTier"] !== "basic" && entry["minimumTier"] !== "premium") {
      errors.push(`features.${featureName}.minimumTier must be "basic" or "premium"`);
    }

    if (typeof entry["enabled"] !== "boolean") {
      errors.push(`features.${featureName}.enabled must be a boolean`);
    }
  }

  return { valid: errors.length === 0, errors };
}

export function validateAutomationConfig(config: AutomationConfig): ConfigValidationResult {
  const errors: string[] = [];

  if (!isPlainObject(config.autoHide)) {
    errors.push("autoHide must be an object");
  } else {
    if (typeof config.autoHide.enabled !== "boolean") {
      errors.push("autoHide.enabled must be a boolean");
    }

    if (
      !isFiniteNumber(config.autoHide.reportThreshold) ||
      !Number.isInteger(config.autoHide.reportThreshold) ||
      config.autoHide.reportThreshold < 2 ||
      config.autoHide.reportThreshold > 100
    ) {
      errors.push("autoHide.reportThreshold must be an integer between 2 and 100.");
    }
  }

  if (!isPlainObject(config.staleReportEscalation)) {
    errors.push("staleReportEscalation must be an object");
  } else {
    if (typeof config.staleReportEscalation.enabled !== "boolean") {
      errors.push("staleReportEscalation.enabled must be a boolean");
    }

    if (
      !isFiniteNumber(config.staleReportEscalation.pendingDays) ||
      !Number.isInteger(config.staleReportEscalation.pendingDays) ||
      config.staleReportEscalation.pendingDays < 1 ||
      config.staleReportEscalation.pendingDays > 365
    ) {
      errors.push("staleReportEscalation.pendingDays must be an integer between 1 and 365.");
    }
  }

  if (!isPlainObject(config.scheduled)) {
    errors.push("scheduled must be an object");
  } else {
    // Type-checked explicitly, same reasoning as premiumEarnsXp/excludePremium:
    // deepMerge passes stored values through verbatim, and a stored STRING
    // "false" is truthy, which would silently re-enable a sweep an admin
    // believed they had paused.
    for (const key of ["leaderboardSnapshotRefresh", "subscriptionExpirySweep", "pushNotificationDispatch"] as const) {
      if (typeof config.scheduled[key] !== "boolean") {
        errors.push(`scheduled.${key} must be a boolean`);
      }
    }
  }

  if (!isPlainObject(config.notifications)) {
    errors.push("notifications must be an object");
  } else {
    if (typeof config.notifications.notifyErrorGroups !== "boolean") {
      errors.push("notifications.notifyErrorGroups must be a boolean");
    }

    if (config.notifications.minimumErrorSeverity !== "high" && config.notifications.minimumErrorSeverity !== "critical") {
      errors.push('notifications.minimumErrorSeverity must be "high" or "critical"');
    }

    if (typeof config.notifications.notifyNewReports !== "boolean") {
      errors.push("notifications.notifyNewReports must be a boolean");
    }
  }

  return { valid: errors.length === 0, errors };
}

export function validateChallengeAccessConfig(config: ChallengeAccessConfig): ConfigValidationResult {
  const errors: string[] = [];

  // Inline copy of the nine catalog tier ids (challenge/challengeCatalog.ts).
  // Kept inside the validator body so the cross-repo drift check covers it.
  const knownTierIds = ["10K", "20K", "42K", "100K", "200K", "250K", "300K", "500K", "1000K"];

  if (!Array.isArray(config.premiumOnlyTiers)) {
    errors.push("premiumOnlyTiers must be an array of challenge tier ids");
  } else {
    for (const tierId of config.premiumOnlyTiers) {
      if (typeof tierId !== "string" || !knownTierIds.includes(tierId)) {
        errors.push(`premiumOnlyTiers contains an unknown tier id: ${String(tierId)}`);
      }
    }

    if (new Set(config.premiumOnlyTiers).size !== config.premiumOnlyTiers.length) {
      errors.push("premiumOnlyTiers must not contain duplicate tier ids");
    }
  }

  return { valid: errors.length === 0, errors };
}

export function validateCharacterAccessConfig(config: CharacterAccessConfig): ConfigValidationResult {
  const errors: string[] = [];

  // Inline copy of the four RunnerCharacter enum ids (the app's
  // core/characters/runner_character.dart). Kept inside the validator body so
  // the cross-repo drift check covers it.
  const knownCharacterIds = ["blue", "cap", "pink", "purple"];

  if (!Array.isArray(config.premiumOnlyCharacters)) {
    errors.push("premiumOnlyCharacters must be an array of character ids");
  } else {
    for (const characterId of config.premiumOnlyCharacters) {
      if (typeof characterId !== "string" || !knownCharacterIds.includes(characterId)) {
        errors.push(`premiumOnlyCharacters contains an unknown character id: ${String(characterId)}`);
      }
    }

    if (new Set(config.premiumOnlyCharacters).size !== config.premiumOnlyCharacters.length) {
      errors.push("premiumOnlyCharacters must not contain duplicate character ids");
    }
  }

  return { valid: errors.length === 0, errors };
}

// Reports a non-fatal degraded event: config doc validation failure, a
// per-field repair, or a read failure. Deliberately NOT called for the
// "config doc is missing" branches below — absent config is the designed
// default state, not a fault, and reporting it would fire constantly in
// fresh environments. reportBackendError never throws, so this can be
// awaited unconditionally without its own try/catch. `error` is the actual
// caught error for read failures, or a synthetic Error carrying the same
// message already sent to console.warn for validation/repair events.
async function reportConfigFallback(functionName: string, error: unknown): Promise<void> {
  await reportBackendError({ functionName, error, fatal: false });
}

async function readConfigDoc(db: Firestore, docPath: string): Promise<unknown> {
  const snapshot = await db.doc(docPath).get();

  if (!snapshot.exists) {
    return undefined;
  }

  return snapshot.data();
}


/**
 * Repairs a merged config by resetting ONLY the fields the validator rejected
 * back to their defaults, instead of discarding the whole document.
 *
 * The all-or-nothing fallback meant a single bad value — say a
 * `premiumEarnsXp: "false"` string written by hand — silently reverted every
 * other tuned field in the same document (XP rates, caps, the level curve,
 * streak rewards) with only a console.warn as the signal. An admin fixing a
 * typo would have found their whole configuration gone.
 *
 * Error strings are formatted "<field> must ..." / "<field>.<sub> must ..." /
 * "<field>[i].<sub> must ...", so the leading segment names the top-level key
 * to reset. Resetting the whole top-level key (rather than the exact nested
 * leaf) is deliberate: a partially-valid array or nested object is harder to
 * reason about than a known-good default.
 *
 * Falls back to `defaults` if the repair does not produce a valid config.
 *
 * Note what this does and does not guarantee. It cannot widen what
 * VALIDATION accepts — the repaired candidate is re-validated. It does widen
 * what the runtime HONOURS compared with the previous all-or-nothing
 * fallback: a document with one bad field used to run entirely on defaults,
 * and now its remaining valid-but-extreme values take effect. Validation has
 * no upper bounds, so `{ xpPerKilometer: 100000, premiumEarnsXp: "false" }`
 * previously ran at the default 10 XP/km and now runs at 100000.
 *
 * Cross-field rules are attributed to a single key, so the repair can also
 * satisfy a rule in a direction the admin did not intend: stored
 * `{ activityXpCap: 150, dailyXpCap: 120 }` fails "dailyXpCap must be >=
 * activityXpCap", resets `dailyXpCap` to 200, and ends up honouring a raised
 * per-run cap against a daily cap nobody wrote.
 *
 * Both are acceptable because the supported writer — the admin console —
 * validates with the mirrored ruleset and refuses an invalid save outright,
 * so a document reaching this path came from a direct Firestore edit or
 * predates the contract.
 */
function repairInvalidConfigFields<T>(
  merged: T,
  errors: readonly string[],
  defaults: T,
  validate: (candidate: T) => ConfigValidationResult,
): { readonly config: T; readonly resetFields: readonly string[] } | null {
  const resetFields = new Set<string>();

  for (const error of errors) {
    const field = error.split(" ")[0]?.split(".")[0]?.split("[")[0];
    if (field !== undefined && field.length > 0 && field in (defaults as object)) {
      resetFields.add(field);
    }
  }

  if (resetFields.size === 0) {
    return null;
  }

  const repaired = { ...(merged as Record<string, unknown>) };
  for (const field of resetFields) {
    // Cloned, not referenced. Several defaults are objects or arrays
    // (`coolDown`, `levelIncrements`, `streakRewards`), and handing back the
    // module-level constant would let anything that mutates the returned
    // config corrupt DEFAULT_*_CONFIG for the lifetime of the Functions
    // instance — a process-wide change from a single request.
    repaired[field] = structuredClone((defaults as Record<string, unknown>)[field]);
  }

  const candidate = repaired as T;
  return validate(candidate).valid
    ? { config: candidate, resetFields: [...resetFields] }
    : null;
}

export async function loadProgressionConfig(db: Firestore): Promise<ProgressionConfig> {
  try {
    const stored = await readConfigDoc(db, "config/progression");

    if (stored === undefined) {
      console.warn("configLoader: config/progression is missing; using DEFAULT_PROGRESSION_CONFIG");
      return DEFAULT_PROGRESSION_CONFIG;
    }

    const merged = deepMerge(DEFAULT_PROGRESSION_CONFIG, stored);
    const result = validateProgressionConfig(merged);

    if (!result.valid) {
      const repaired = repairInvalidConfigFields(
        merged,
        result.errors,
        DEFAULT_PROGRESSION_CONFIG,
        validateProgressionConfig,
      );

      if (repaired !== null) {
        const message = `configLoader: config/progression failed validation (${result.errors.join(", ")}); reset ${repaired.resetFields.join(", ")} to defaults and kept the rest`;
        console.warn(message);
        await reportConfigFallback("loadProgressionConfig", new Error(message));
        return repaired.config;
      }

      const message = `configLoader: config/progression failed validation (${result.errors.join(", ")}); using DEFAULT_PROGRESSION_CONFIG`;
      console.warn(message);
      await reportConfigFallback("loadProgressionConfig", new Error(message));
      return DEFAULT_PROGRESSION_CONFIG;
    }

    return merged;
  } catch (error) {
    console.warn("configLoader: failed to read config/progression; using DEFAULT_PROGRESSION_CONFIG", error);
    await reportConfigFallback("loadProgressionConfig", error);
    return DEFAULT_PROGRESSION_CONFIG;
  }
}

export async function loadLeaderboardConfig(db: Firestore): Promise<LeaderboardConfig> {
  try {
    const stored = await readConfigDoc(db, "config/leaderboard");

    if (stored === undefined) {
      console.warn("configLoader: config/leaderboard is missing; using DEFAULT_LEADERBOARD_CONFIG");
      return DEFAULT_LEADERBOARD_CONFIG;
    }

    const merged = deepMerge(DEFAULT_LEADERBOARD_CONFIG, stored);
    const result = validateLeaderboardConfig(merged);

    if (!result.valid) {
      const repaired = repairInvalidConfigFields(
        merged,
        result.errors,
        DEFAULT_LEADERBOARD_CONFIG,
        validateLeaderboardConfig,
      );

      if (repaired !== null) {
        const message = `configLoader: config/leaderboard failed validation (${result.errors.join(", ")}); reset ${repaired.resetFields.join(", ")} to defaults and kept the rest`;
        console.warn(message);
        await reportConfigFallback("loadLeaderboardConfig", new Error(message));
        return repaired.config;
      }

      const message = `configLoader: config/leaderboard failed validation (${result.errors.join(", ")}); using DEFAULT_LEADERBOARD_CONFIG`;
      console.warn(message);
      await reportConfigFallback("loadLeaderboardConfig", new Error(message));
      return DEFAULT_LEADERBOARD_CONFIG;
    }

    return merged;
  } catch (error) {
    console.warn("configLoader: failed to read config/leaderboard; using DEFAULT_LEADERBOARD_CONFIG", error);
    await reportConfigFallback("loadLeaderboardConfig", error);
    return DEFAULT_LEADERBOARD_CONFIG;
  }
}

export async function loadFeatureAccessConfig(db: Firestore): Promise<FeatureAccessConfig> {
  try {
    const stored = await readConfigDoc(db, "config/featureAccess");

    if (stored === undefined) {
      console.warn("configLoader: config/featureAccess is missing; using DEFAULT_FEATURE_ACCESS_CONFIG");
      return DEFAULT_FEATURE_ACCESS_CONFIG;
    }

    const merged = deepMerge(DEFAULT_FEATURE_ACCESS_CONFIG, stored);
    const result = validateFeatureAccessConfig(merged);

    if (!result.valid) {
      const message = `configLoader: config/featureAccess failed validation (${result.errors.join(", ")}); using DEFAULT_FEATURE_ACCESS_CONFIG`;
      console.warn(message);
      await reportConfigFallback("loadFeatureAccessConfig", new Error(message));
      return DEFAULT_FEATURE_ACCESS_CONFIG;
    }

    return merged;
  } catch (error) {
    console.warn("configLoader: failed to read config/featureAccess; using DEFAULT_FEATURE_ACCESS_CONFIG", error);
    await reportConfigFallback("loadFeatureAccessConfig", error);
    return DEFAULT_FEATURE_ACCESS_CONFIG;
  }
}

// `reportFallback: false` suppresses the reportConfigFallback() error-report on
// degraded config. It exists for exactly one caller: the errorGroupWritten
// trigger watches `errorGroups`, and reportConfigFallback() itself writes an
// `errorGroups` document — so a reporting load from inside that trigger would
// turn every degraded-config read into a self-sustaining write-notify loop on
// the watched collection. Every other caller must leave reporting on.
export async function loadAutomationConfig(
  db: Firestore,
  options?: { readonly reportFallback?: boolean },
): Promise<AutomationConfig> {
  const reportFallback = options?.reportFallback !== false;
  try {
    const stored = await readConfigDoc(db, "config/automation");

    if (stored === undefined) {
      console.warn("configLoader: config/automation is missing; using DEFAULT_AUTOMATION_CONFIG");
      return DEFAULT_AUTOMATION_CONFIG;
    }

    const merged = deepMerge(DEFAULT_AUTOMATION_CONFIG, stored);
    const result = validateAutomationConfig(merged);

    if (!result.valid) {
      const repaired = repairInvalidConfigFields(
        merged,
        result.errors,
        DEFAULT_AUTOMATION_CONFIG,
        validateAutomationConfig,
      );

      if (repaired !== null) {
        const message = `configLoader: config/automation failed validation (${result.errors.join(", ")}); reset ${repaired.resetFields.join(", ")} to defaults and kept the rest`;
        console.warn(message);
        if (reportFallback) {
          await reportConfigFallback("loadAutomationConfig", new Error(message));
        }
        return repaired.config;
      }

      const message = `configLoader: config/automation failed validation (${result.errors.join(", ")}); using DEFAULT_AUTOMATION_CONFIG`;
      console.warn(message);
      if (reportFallback) {
        await reportConfigFallback("loadAutomationConfig", new Error(message));
      }
      return DEFAULT_AUTOMATION_CONFIG;
    }

    return merged;
  } catch (error) {
    console.warn("configLoader: failed to read config/automation; using DEFAULT_AUTOMATION_CONFIG", error);
    if (reportFallback) {
      await reportConfigFallback("loadAutomationConfig", error);
    }
    return DEFAULT_AUTOMATION_CONFIG;
  }
}

export async function loadChallengeAccessConfig(db: Firestore): Promise<ChallengeAccessConfig> {
  try {
    const stored = await readConfigDoc(db, "config/challengeAccess");

    if (stored === undefined) {
      console.warn("configLoader: config/challengeAccess is missing; using DEFAULT_CHALLENGE_ACCESS_CONFIG");
      return DEFAULT_CHALLENGE_ACCESS_CONFIG;
    }

    // deepMerge treats arrays as leaf values, so a stored premiumOnlyTiers
    // array REPLACES the default list rather than unioning with it — an admin
    // clearing every checkbox genuinely opens every tier.
    const merged = deepMerge(DEFAULT_CHALLENGE_ACCESS_CONFIG, stored);
    const result = validateChallengeAccessConfig(merged);

    if (!result.valid) {
      const message = `configLoader: config/challengeAccess failed validation (${result.errors.join(", ")}); using DEFAULT_CHALLENGE_ACCESS_CONFIG`;
      console.warn(message);
      await reportConfigFallback("loadChallengeAccessConfig", new Error(message));
      return DEFAULT_CHALLENGE_ACCESS_CONFIG;
    }

    return merged;
  } catch (error) {
    console.warn("configLoader: failed to read config/challengeAccess; using DEFAULT_CHALLENGE_ACCESS_CONFIG", error);
    await reportConfigFallback("loadChallengeAccessConfig", error);
    return DEFAULT_CHALLENGE_ACCESS_CONFIG;
  }
}

export async function loadCharacterAccessConfig(db: Firestore): Promise<CharacterAccessConfig> {
  try {
    const stored = await readConfigDoc(db, "config/characterAccess");

    if (stored === undefined) {
      console.warn("configLoader: config/characterAccess is missing; using DEFAULT_CHARACTER_ACCESS_CONFIG");
      return DEFAULT_CHARACTER_ACCESS_CONFIG;
    }

    // deepMerge treats arrays as leaf values, so a stored premiumOnlyCharacters
    // array REPLACES the default list rather than unioning with it — an admin
    // clearing every checkbox genuinely opens every character.
    const merged = deepMerge(DEFAULT_CHARACTER_ACCESS_CONFIG, stored);
    const result = validateCharacterAccessConfig(merged);

    if (!result.valid) {
      const message = `configLoader: config/characterAccess failed validation (${result.errors.join(", ")}); using DEFAULT_CHARACTER_ACCESS_CONFIG`;
      console.warn(message);
      await reportConfigFallback("loadCharacterAccessConfig", new Error(message));
      return DEFAULT_CHARACTER_ACCESS_CONFIG;
    }

    return merged;
  } catch (error) {
    console.warn("configLoader: failed to read config/characterAccess; using DEFAULT_CHARACTER_ACCESS_CONFIG", error);
    await reportConfigFallback("loadCharacterAccessConfig", error);
    return DEFAULT_CHARACTER_ACCESS_CONFIG;
  }
}
