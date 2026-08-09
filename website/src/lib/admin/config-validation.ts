// Pure config types, defaults, and validators for the admin console's
// backend-owned configuration documents (config/progression,
// config/leaderboard, config/featureAccess).
//
// These mirror the backend contract in
// functions/src/config/configLoader.ts field-for-field, default-for-default,
// and rule-for-rule. Keep the two files in sync: the Cloud Functions runtime
// is the source of truth for what is actually enforced server-side; this file
// lets the admin console validate/preview the same config shape before it is
// written to Firestore. This module has no Firebase/Next dependency so it can
// be unit tested in isolation.

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
// purple (Ivy). The character is display-only cosmetic personalization stored
// locally on the device, so this gate sells presentation value only and is
// enforced client-side. This doc lets the admin console reconfigure which
// characters are premium. Mirrors functions/src/config/configLoader.ts.
export type CharacterAccessConfig = {
  readonly premiumOnlyCharacters: readonly string[];
  readonly version: number;
};

export type ConfigValidationResult = {
  readonly valid: boolean;
  readonly errors: readonly string[];
};

// The DEFAULT_* constants are handed out directly (getLiveProgressionConfig
// returns them on a missing/invalid document, and deepMerge copies only the top
// level so an untouched nested key like `coolDown` is still the constant's own
// object). They are `readonly` in the type system, which is erased at runtime,
// so freeze them for real — a mutation would otherwise change the defaults for
// every later request this server process handles.
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
  // competitive edge — so premium runners earn XP under the same rules as
  // Basic runners. Mirrors functions/src/config/configLoader.ts.
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
  // they rank on the same board. Mirrors functions/src/config/configLoader.ts.
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
// Mirrors functions/src/config/configLoader.ts.
//
// `goalPlan` was RETIRED from this catalog on 2026-07-25: the
// onboarding-generated beginner plan is the app's core beginner experience,
// which premium must never gate, so offering a switch that could move it to
// Premium was itself the risk.
//
// `healthWorkoutImport` was RETIRED on 2026-08-13 for the opposite reason:
// there is nothing left to gate. `65b41c49` deleted the whole HealthKit import
// surface, so no code has read this key since. A catalog entry with no gate
// behind it is worse than no entry: this console rendered a tier control that
// silently did nothing. The stored document outranks this default, so dropping
// it here was not enough on its own — the key was also deleted from the live
// `config/featureAccess` document, which the console itself cannot do (it
// writes back the merged document it read, re-persisting the key). Re-add only
// alongside a real import gate.
//
// Every remaining key is wired to a real gate — flipping a tier here changes
// what the app does, not just what the upsell lists:
//   - advancedAnalysis  app-side gate (analysis is computed on-device); also
//                       governs the post-run coaching card
//   - aiHomeCoach       homeGuideAgent callable; a denied Basic runner keeps
//                       the app's on-device plan read-out (today's workout
//                       and its steps, composed with no model call). Moving
//                       this back to Basic re-opens OpenAI spend for every
//                       consenting Basic account.
//   - activityFeedback  activityFeedbackAgent callable
//   - workoutBriefing   workoutBriefingAgent callable; the sparkle explainer on
//                       a planned workout's detail screen. A denied Basic
//                       runner still sees the whole session — metrics,
//                       breakdown, effort guide — because the briefing explains
//                       that screen rather than unlocking it. Moving this to
//                       Basic opens OpenAI spend on the most reachable surface
//                       in the app, since it needs no completed run.
//   - shareRouteToFeed  publishActivityToFeed callable
//   - shareCards        app-side gate (achievement + rank card exports)
export const DEFAULT_FEATURE_ACCESS_CONFIG: FeatureAccessConfig = deepFreeze({
  features: {
    advancedAnalysis: { minimumTier: "premium", enabled: true },
    aiHomeCoach: { minimumTier: "premium", enabled: true },
    activityFeedback: { minimumTier: "premium", enabled: true },
    workoutBriefing: { minimumTier: "premium", enabled: true },
    // "basic" as of 2026-08-05, matching functions/src/config/configLoader.ts:
    // the stored document has held "basic" since 2026-07-25 and the loader
    // merges stored over default, so a "premium" default described an
    // environment that does not exist. Publishing a run to the Feed costs no
    // model spend, unlike the three OpenAI-backed keys above.
    shareRouteToFeed: { minimumTier: "basic", enabled: true },
    shareCards: { minimumTier: "basic", enabled: true },
  },
  version: 1,
});

// Mirrors functions/src/config/configLoader.ts. Every scheduled sweep
// defaults to running; automation gating exists so an admin can pause a
// single sweep during an incident, not so a fresh environment starts with
// platform automation silently off.
export const DEFAULT_AUTOMATION_CONFIG: AutomationConfig = deepFreeze({
  autoHide: {
    enabled: false,
    reportThreshold: 3,
  },
  staleReportEscalation: {
    enabled: true,
    pendingDays: 7,
  },
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
// the character picker. Mirrors functions/src/config/configLoader.ts.
export const DEFAULT_CHARACTER_ACCESS_CONFIG: CharacterAccessConfig = deepFreeze({
  premiumOnlyCharacters: ["cap", "purple"],
  version: 1,
});

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

/**
 * Merges `partial` over `defaults`, field by field. Nested plain objects are
 * merged recursively so that omitted nested fields fall back to the default
 * value (e.g. a stored `{ coolDown: { percent: 0.3 } }` keeps the default
 * `coolDown.min`/`coolDown.max`). Arrays are replaced wholesale, never merged
 * element-by-element. Kept identical to the backend's deepMerge so admin
 * previews match what the backend will actually load.
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

export function validateProgressionConfig(
  config: ProgressionConfig,
): ConfigValidationResult {
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

  if (
    isFiniteNumber(config.dailyXpCap) &&
    isFiniteNumber(config.activityXpCap) &&
    config.dailyXpCap < config.activityXpCap
  ) {
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
  } else if (
    !config.levelIncrements.every((increment) => isFiniteNumber(increment) && increment > 0)
  ) {
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

      if (
        !isFiniteNumber(milestoneDays) ||
        !Number.isInteger(milestoneDays) ||
        milestoneDays < 1
      ) {
        errors.push(
          `streakRewards[${index}].milestoneDays must be an integer greater than or equal to 1`,
        );
      } else {
        if (previousMilestoneDays !== undefined && milestoneDays <= previousMilestoneDays) {
          errors.push(
            `streakRewards[${index}].milestoneDays must be greater than the previous milestoneDays`,
          );
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

export function validateLeaderboardConfig(
  config: LeaderboardConfig,
): ConfigValidationResult {
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

export function validateFeatureAccessConfig(
  config: FeatureAccessConfig,
): ConfigValidationResult {
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

export function validateAutomationConfig(
  config: AutomationConfig,
): ConfigValidationResult {
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
