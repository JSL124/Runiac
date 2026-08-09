"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  saveAutomationConfig,
  saveChallengeAccessConfig,
  saveCharacterAccessConfig,
  saveFeatureAccessConfig,
} from "@/lib/actions/admin";
import {
  DEFAULT_AUTOMATION_CONFIG,
  DEFAULT_CHALLENGE_ACCESS_CONFIG,
  DEFAULT_CHARACTER_ACCESS_CONFIG,
  validateAutomationConfig,
  validateChallengeAccessConfig,
  validateCharacterAccessConfig,
  validateFeatureAccessConfig,
  type ChallengeAccessConfig,
  type CharacterAccessConfig,
} from "@/lib/admin/config-validation";
import { btnBrand, btnSecondary, inputBase } from "@/components/admin/button-styles";
import type { AutomationConfig, FeatureAccessConfig } from "@/lib/admin/types";

type FeatureSaveState = "idle" | "saving" | "saved-live" | "saved-staged" | "error";
// Automation saves get a two-step confirm because auto-hide can delete user
// content — mirrors GamificationRules' SaveState machine.
type AutomationSaveState =
  | "idle"
  | "confirm"
  | "saving"
  | "saved-live"
  | "saved-staged"
  | "error";

const TIER_LABELS: Record<"basic" | "premium", string> = {
  basic: "Basic",
  premium: "Premium",
};

// Human-readable labels for the feature-access catalog, matching the app's
// real user-facing surface (see the catalog comment in config-validation.ts).
// Unknown keys fall back to the raw key so a backend catalog addition or a
// legacy stored entry never renders blank.
const FEATURE_LABELS: Record<string, { label: string; description: string }> = {
  advancedAnalysis: {
    label: "Advanced run analysis",
    description:
      "Post-run Advanced Analysis screen: performance score, pace, heart-rate zones, elevation, and splits.",
  },
  aiHomeCoach: {
    label: "AI home coach",
    description:
      "The AI guide bubble on the home stage map. Basic users keep the built-in rule-based guide if this is premium-gated.",
  },
  activityFeedback: {
    label: "AI activity feedback",
    description: "AI-generated character feedback on the post-run summary.",
  },
  workoutBriefing: {
    label: "AI workout briefing",
    description:
      "The sparkle explainer on a planned workout's detail screen. Basic users still see the full session details.",
  },
  shareRouteToFeed: {
    label: "Share route to feed",
    description: "Publishing a completed run's route card to the social feed.",
  },
  shareCards: {
    label: "Share cards",
    description: "Achievement and leaderboard-rank share-card exports.",
  },
};

// The nine-tier challenge catalog (functions/src/challenge/challengeCatalog.ts)
// with its fixed English difficulty labels. Display order only.
const CHALLENGE_TIERS: ReadonlyArray<{ tierId: string; difficulty: string }> = [
  { tierId: "10K", difficulty: "Beginner" },
  { tierId: "20K", difficulty: "Easy" },
  { tierId: "42K", difficulty: "Normal" },
  { tierId: "100K", difficulty: "Challenging" },
  { tierId: "200K", difficulty: "Hard" },
  { tierId: "250K", difficulty: "Hard+" },
  { tierId: "300K", difficulty: "Very Hard" },
  { tierId: "500K", difficulty: "Extreme" },
  { tierId: "1000K", difficulty: "Legend" },
];

// The four guide characters (the app's RunnerCharacter enum ids in
// core/characters/runner_character.dart) with their display names. Display
// order only. The character is cosmetic, device-local personalization, so
// gating it never affects XP, rank, or leaderboard standing.
const RUNIAC_CHARACTERS: ReadonlyArray<{ characterId: string; name: string }> = [
  { characterId: "blue", name: "Bolt" },
  { characterId: "cap", name: "Cap" },
  { characterId: "pink", name: "Mila" },
  { characterId: "purple", name: "Ivy" },
];

// An automation rule is a switch plus the single threshold that switch reads.
// They are modelled together because neither half means anything alone: the
// threshold is dead while the switch is off, and the switch silently reuses
// whatever threshold was last saved. Rendering them as one card keeps that
// pairing visible instead of splitting it across two sections.
//
// The `scheduled.*` toggles (leaderboard snapshot refresh, subscription expiry
// sweep, push notification dispatch) were deliberately removed from this
// screen. They are not policy — they are kill-switches for jobs that should
// always run, and pausing one is invisible everywhere else in the console. The
// stored values ride along in `automationDraft` untouched on save, so the
// Cloud Functions that read them (monthlyLeaderboard.ts,
// subscriptionExpirySchedule.ts, scheduledPushDispatch.ts) are unaffected.
type AutomationRule = {
  key: string;
  label: string;
  description: string;
  enabled: (config: AutomationConfig) => boolean;
  setEnabled: (config: AutomationConfig, value: boolean) => AutomationConfig;
  threshold: {
    label: string;
    description: string;
    inactiveHint: string;
    unit: string;
    min: number;
    max: number;
    ariaLabel: string;
    value: (config: AutomationConfig) => number;
    setValue: (config: AutomationConfig, value: number) => AutomationConfig;
  };
};

const AUTOMATION_RULES: AutomationRule[] = [
  {
    key: "autoHide",
    label: "Auto-hide reported posts",
    description:
      "When a published feed post reaches the report threshold below, a removal command is enqueued automatically — the same moderation command an administrator issues from the Exception Queue.",
    enabled: (config) => config.autoHide.enabled,
    setEnabled: (config, value) => ({
      ...config,
      autoHide: { ...config.autoHide, enabled: value },
    }),
    threshold: {
      label: "Report threshold",
      description:
        "Distinct reports required before a feed post is hidden automatically. The minimum is 2, so a single reporter can never remove content on their own.",
      inactiveHint:
        "Turn this rule on to change the threshold. The saved value applies the moment auto-hide is enabled.",
      unit: "reports",
      min: 2,
      max: 100,
      ariaLabel: "Auto-hide report threshold",
      value: (config) => config.autoHide.reportThreshold,
      setValue: (config, value) => ({
        ...config,
        autoHide: { ...config.autoHide, reportThreshold: value },
      }),
    },
  },
  {
    key: "staleReportEscalation",
    label: "Escalate stale reports",
    description:
      "A daily sweep raises a dashboard notification when reports stay unresolved longer than the configured number of days.",
    enabled: (config) => config.staleReportEscalation.enabled,
    setEnabled: (config, value) => ({
      ...config,
      staleReportEscalation: { ...config.staleReportEscalation, enabled: value },
    }),
    threshold: {
      label: "Escalation age",
      description:
        "Reports unresolved longer than this many days are escalated to the Overview dashboard by the daily sweep.",
      inactiveHint:
        "Turn this rule on to change the age. The saved value applies the moment escalation is enabled.",
      unit: "day(s)",
      min: 1,
      max: 365,
      ariaLabel: "Stale report escalation age in days",
      value: (config) => config.staleReportEscalation.pendingDays,
      setValue: (config, value) => ({
        ...config,
        staleReportEscalation: {
          ...config.staleReportEscalation,
          pendingDays: value,
        },
      }),
    },
  },
];

export function PolicySettings({
  featureAccessConfig,
  automationConfig,
  challengeAccessConfig,
  characterAccessConfig,
}: {
  featureAccessConfig: FeatureAccessConfig;
  automationConfig: AutomationConfig;
  challengeAccessConfig: ChallengeAccessConfig;
  characterAccessConfig: CharacterAccessConfig;
}) {
  const router = useRouter();

  const [featureConfig, setFeatureConfig] = useState<FeatureAccessConfig>(
    featureAccessConfig,
  );
  const [featureErrors, setFeatureErrors] = useState<string[]>([]);
  const [featureSaveState, setFeatureSaveState] = useState<FeatureSaveState>("idle");
  const [featureErrorMessage, setFeatureErrorMessage] = useState<string | null>(null);

  const [challengeDraft, setChallengeDraft] = useState<ChallengeAccessConfig>(
    challengeAccessConfig,
  );
  const [challengeErrors, setChallengeErrors] = useState<string[]>([]);
  const [challengeSaveState, setChallengeSaveState] = useState<FeatureSaveState>("idle");
  const [challengeErrorMessage, setChallengeErrorMessage] = useState<string | null>(null);

  const [characterDraft, setCharacterDraft] = useState<CharacterAccessConfig>(
    characterAccessConfig,
  );
  const [characterErrors, setCharacterErrors] = useState<string[]>([]);
  const [characterSaveState, setCharacterSaveState] = useState<FeatureSaveState>("idle");
  const [characterErrorMessage, setCharacterErrorMessage] = useState<string | null>(null);

  const [automationDraft, setAutomationDraft] = useState<AutomationConfig>(
    automationConfig,
  );
  const [automationErrors, setAutomationErrors] = useState<string[]>([]);
  const [automationSaveState, setAutomationSaveState] =
    useState<AutomationSaveState>("idle");
  const [automationErrorMessage, setAutomationErrorMessage] = useState<string | null>(
    null,
  );

  // Compare with `version` zeroed out on both sides: saveAdminConfig bumps the
  // stored version server-side, so after a save + router.refresh() the prop
  // carries N+1 while the draft still holds N — without this the page would
  // read as dirty forever after the first save.
  const automationDirty =
    JSON.stringify({ ...automationDraft, version: 0 }) !==
    JSON.stringify({ ...automationConfig, version: 0 });

  function updateFeatureEntry(
    featureName: string,
    patch: Partial<FeatureAccessConfig["features"][string]>,
  ) {
    setFeatureConfig((prev) => ({
      ...prev,
      features: {
        ...prev.features,
        [featureName]: { ...prev.features[featureName], ...patch },
      },
    }));
    setFeatureErrors([]);
    setFeatureSaveState("idle");
    setFeatureErrorMessage(null);
  }

  async function handleSaveFeatureAccess() {
    const result = validateFeatureAccessConfig(featureConfig);

    if (!result.valid) {
      setFeatureErrors([...result.errors]);
      setFeatureSaveState("idle");
      return;
    }

    setFeatureErrors([]);
    setFeatureSaveState("saving");
    setFeatureErrorMessage(null);

    const saveResult = await saveFeatureAccessConfig(featureConfig);

    if (!saveResult.ok) {
      setFeatureSaveState("error");
      setFeatureErrorMessage(saveResult.error);
      return;
    }

    if (saveResult.live) {
      setFeatureSaveState("saved-live");
      router.refresh();
    } else {
      setFeatureSaveState("saved-staged");
    }
  }

  function setTierPremiumOnly(tierId: string, premiumOnly: boolean) {
    setChallengeDraft((prev) => {
      const next = new Set(prev.premiumOnlyTiers);
      if (premiumOnly) {
        next.add(tierId);
      } else {
        next.delete(tierId);
      }
      // Persist in catalog display order so saved lists are stable/diffable.
      return {
        ...prev,
        premiumOnlyTiers: CHALLENGE_TIERS.filter((tier) => next.has(tier.tierId)).map(
          (tier) => tier.tierId,
        ),
      };
    });
    setChallengeErrors([]);
    setChallengeSaveState("idle");
    setChallengeErrorMessage(null);
  }

  async function handleSaveChallengeAccess() {
    const result = validateChallengeAccessConfig(challengeDraft);

    if (!result.valid) {
      setChallengeErrors([...result.errors]);
      setChallengeSaveState("idle");
      return;
    }

    setChallengeErrors([]);
    setChallengeSaveState("saving");
    setChallengeErrorMessage(null);

    const saveResult = await saveChallengeAccessConfig(challengeDraft);

    if (!saveResult.ok) {
      setChallengeSaveState("error");
      setChallengeErrorMessage(saveResult.error);
      return;
    }

    if (saveResult.live) {
      setChallengeSaveState("saved-live");
      router.refresh();
    } else {
      setChallengeSaveState("saved-staged");
    }
  }

  function handleChallengeResetToDefaults() {
    setChallengeDraft(structuredClone(DEFAULT_CHALLENGE_ACCESS_CONFIG));
    setChallengeErrors([]);
    setChallengeSaveState("idle");
    setChallengeErrorMessage(null);
  }

  function setCharacterPremiumOnly(characterId: string, premiumOnly: boolean) {
    setCharacterDraft((prev) => {
      const next = new Set(prev.premiumOnlyCharacters);
      if (premiumOnly) {
        next.add(characterId);
      } else {
        next.delete(characterId);
      }
      // Persist in catalog display order so saved lists are stable/diffable.
      return {
        ...prev,
        premiumOnlyCharacters: RUNIAC_CHARACTERS.filter((character) =>
          next.has(character.characterId),
        ).map((character) => character.characterId),
      };
    });
    setCharacterErrors([]);
    setCharacterSaveState("idle");
    setCharacterErrorMessage(null);
  }

  async function handleSaveCharacterAccess() {
    const result = validateCharacterAccessConfig(characterDraft);

    if (!result.valid) {
      setCharacterErrors([...result.errors]);
      setCharacterSaveState("idle");
      return;
    }

    setCharacterErrors([]);
    setCharacterSaveState("saving");
    setCharacterErrorMessage(null);

    const saveResult = await saveCharacterAccessConfig(characterDraft);

    if (!saveResult.ok) {
      setCharacterSaveState("error");
      setCharacterErrorMessage(saveResult.error);
      return;
    }

    if (saveResult.live) {
      setCharacterSaveState("saved-live");
      router.refresh();
    } else {
      setCharacterSaveState("saved-staged");
    }
  }

  function handleCharacterResetToDefaults() {
    setCharacterDraft(structuredClone(DEFAULT_CHARACTER_ACCESS_CONFIG));
    setCharacterErrors([]);
    setCharacterSaveState("idle");
    setCharacterErrorMessage(null);
  }

  function updateAutomation(next: AutomationConfig) {
    setAutomationDraft(next);
    setAutomationErrors([]);
    setAutomationSaveState("idle");
    setAutomationErrorMessage(null);
  }

  function handleAutomationSaveClick() {
    const result = validateAutomationConfig(automationDraft);

    if (!result.valid) {
      setAutomationErrors([...result.errors]);
      setAutomationSaveState("idle");
      return;
    }

    setAutomationErrors([]);
    // Auto-hide can remove user content automatically — confirm before writing.
    setAutomationSaveState("confirm");
  }

  function handleAutomationCancelConfirm() {
    setAutomationSaveState("idle");
  }

  async function handleAutomationConfirmSave() {
    setAutomationSaveState("saving");
    setAutomationErrorMessage(null);

    const saveResult = await saveAutomationConfig(automationDraft);

    if (!saveResult.ok) {
      setAutomationSaveState("error");
      setAutomationErrorMessage(saveResult.error);
      return;
    }

    if (saveResult.live) {
      setAutomationSaveState("saved-live");
      router.refresh();
    } else {
      setAutomationSaveState("saved-staged");
    }
  }

  function handleAutomationResetToDefaults() {
    updateAutomation(structuredClone(DEFAULT_AUTOMATION_CONFIG));
  }

  // Each rule renders as one box: the switch on top, its threshold directly
  // underneath. The threshold is a dependent control — it only means anything
  // while its own switch is on — so when the switch is off the slider collapses
  // to a read-only value with an Inactive badge and the page never offers an
  // affordance that changes nothing.
  //
  // Two deliberate details. (1) `active` is read from `automationDraft`, not
  // from the saved `automationConfig` prop, so an admin can flip the switch on
  // and retune the threshold in the SAME save — keying off the saved value
  // would force enable-then-save-then-retune, briefly running auto-hide at the
  // old threshold. (2) Collapsing the slider never touches `automationDraft`:
  // the value stays in state and is still written on save. This is an editing
  // affordance, not a reset.
  function renderAutomationRule(rule: AutomationRule) {
    const active = rule.enabled(automationDraft);
    const value = rule.threshold.value(automationDraft);

    return (
      <li
        key={rule.key}
        className="rounded-lg border border-border px-3 py-2.5"
      >
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="text-sm font-bold text-foreground">{rule.label}</p>
            <p className="text-xs text-muted">{rule.description}</p>
          </div>
          <label className="inline-flex cursor-pointer items-center gap-2">
            <span className="text-xs font-semibold text-muted">
              {active ? "On" : "Off"}
            </span>
            <input
              type="checkbox"
              checked={active}
              onChange={(event) =>
                updateAutomation(
                  rule.setEnabled(automationDraft, event.target.checked),
                )
              }
              className="h-4 w-4 accent-[#001e62]"
            />
          </label>
        </div>

        <div className="mt-2.5 border-t border-border pt-2.5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-xs font-bold text-foreground">
              {rule.threshold.label}
            </p>
            <div className="flex items-center gap-2">
              {active ? null : (
                <span className="rounded-full border border-border px-2 py-0.5 text-[0.65rem] font-bold uppercase tracking-[0.12em] text-muted">
                  Inactive
                </span>
              )}
              <span
                className={`font-mono text-sm font-bold tabular-nums ${
                  active ? "text-brand" : "text-muted"
                }`}
              >
                {value} {rule.threshold.unit}
              </span>
            </div>
          </div>
          <p className="mt-0.5 text-xs text-muted">
            {rule.threshold.description}
          </p>
          {active ? (
            <>
              <input
                type="range"
                min={rule.threshold.min}
                max={rule.threshold.max}
                step={1}
                value={value}
                onChange={(event) =>
                  updateAutomation(
                    rule.threshold.setValue(
                      automationDraft,
                      Math.round(Number(event.target.value)),
                    ),
                  )
                }
                aria-label={rule.threshold.ariaLabel}
                className="mt-2 w-full accent-[#001e62]"
              />
              <div className="flex justify-between text-[0.7rem] text-muted">
                <span>{rule.threshold.min}</span>
                <span>{rule.threshold.max}</span>
              </div>
            </>
          ) : (
            <p className="mt-2 text-xs text-muted">
              {rule.threshold.inactiveHint}
            </p>
          )}
        </div>
      </li>
    );
  }

  return (
    <div className="space-y-6">
      <section className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
        <h2 className="text-base font-bold text-brand">Feature access</h2>
        <ul className="mt-4 space-y-2">
          {Object.entries(featureConfig.features).map(([featureName, entry]) => (
            <li
              key={featureName}
              className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border px-3 py-2.5"
            >
              <div className="min-w-0">
                <p className="text-sm font-bold text-foreground">
                  {FEATURE_LABELS[featureName]?.label ?? featureName}
                </p>
                <p className="text-xs text-muted">
                  {FEATURE_LABELS[featureName]?.description ?? featureName}
                </p>
              </div>
              <div className="flex items-center gap-4">
                <label className="flex items-center gap-2">
                  <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
                    Minimum tier
                  </span>
                  <select
                    value={entry.minimumTier}
                    onChange={(event) =>
                      updateFeatureEntry(featureName, {
                        minimumTier: event.target.value as "basic" | "premium",
                      })
                    }
                    className={`${inputBase} w-32`}
                  >
                    {(Object.keys(TIER_LABELS) as Array<"basic" | "premium">).map(
                      (tier) => (
                        <option key={tier} value={tier}>
                          {TIER_LABELS[tier]}
                        </option>
                      ),
                    )}
                  </select>
                </label>
                {/* `enabled` means "this tier rule is active", not "this
                    feature exists": clearing it releases the gate so everyone
                    keeps the feature. The app and Cloud Functions apply the
                    same reading. */}
                <label
                  className="inline-flex cursor-pointer items-center gap-2"
                  title="Tier rule active. Unchecking releases the gate — the feature stays available to everyone."
                >
                  <span className="text-xs font-semibold text-muted">
                    {entry.enabled ? "Tier rule on" : "Tier rule off"}
                  </span>
                  <input
                    type="checkbox"
                    checked={entry.enabled}
                    onChange={(event) =>
                      updateFeatureEntry(featureName, { enabled: event.target.checked })
                    }
                    className="h-4 w-4 accent-[#001e62]"
                  />
                </label>
              </div>
            </li>
          ))}
        </ul>

        {featureErrors.length > 0 ? (
          <div className="mt-4 rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm text-[#b42318]">
            <p className="font-bold">Fix these before saving:</p>
            <ul className="mt-1 list-disc space-y-0.5 pl-5">
              {featureErrors.map((error) => (
                <li key={error}>{error}</li>
              ))}
            </ul>
          </div>
        ) : null}

        <div className="mt-4 flex flex-wrap items-center gap-3">
          <button
            type="button"
            className={btnBrand}
            onClick={handleSaveFeatureAccess}
            disabled={featureSaveState === "saving"}
          >
            {featureSaveState === "saving" ? "Saving…" : "Save feature access"}
          </button>
          {featureSaveState === "saved-live" ? (
            <span className="text-sm font-semibold text-[#0f6b4e]">
              Saved. Live in config/featureAccess.
            </span>
          ) : featureSaveState === "saved-staged" ? (
            <span className="text-sm font-semibold text-accent">
              Saved locally. Firebase is not connected, so this has not been
              written to a live backend.
            </span>
          ) : featureSaveState === "error" && featureErrorMessage ? (
            <span className="text-sm font-semibold text-[#b42318]">
              {featureErrorMessage}
            </span>
          ) : null}
        </div>
      </section>

      <section className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
        <h2 className="text-base font-bold text-brand">Challenge tier access</h2>
        <ul className="mt-4 space-y-2">
          {CHALLENGE_TIERS.map((tier) => {
            const premiumOnly = challengeDraft.premiumOnlyTiers.includes(tier.tierId);
            return (
              <li
                key={tier.tierId}
                className="flex items-center justify-between gap-3 rounded-lg border border-border px-3 py-2.5"
              >
                <div className="min-w-0">
                  <p className="text-sm font-bold text-foreground">{tier.tierId}</p>
                  <p className="text-xs text-muted">{tier.difficulty}</p>
                </div>
                <label className="inline-flex cursor-pointer items-center gap-2">
                  <span className="text-xs font-semibold text-muted">
                    {premiumOnly ? "Premium only" : "Open to all"}
                  </span>
                  <input
                    type="checkbox"
                    checked={premiumOnly}
                    onChange={(event) =>
                      setTierPremiumOnly(tier.tierId, event.target.checked)
                    }
                    className="h-4 w-4 accent-[#001e62]"
                  />
                </label>
              </li>
            );
          })}
        </ul>

        {challengeErrors.length > 0 ? (
          <div className="mt-4 rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm text-[#b42318]">
            <p className="font-bold">Fix these before saving:</p>
            <ul className="mt-1 list-disc space-y-0.5 pl-5">
              {challengeErrors.map((error) => (
                <li key={error}>{error}</li>
              ))}
            </ul>
          </div>
        ) : null}

        <div className="mt-4 flex flex-wrap items-center gap-3">
          <button
            type="button"
            className={btnBrand}
            onClick={handleSaveChallengeAccess}
            disabled={challengeSaveState === "saving"}
          >
            {challengeSaveState === "saving" ? "Saving…" : "Save challenge access"}
          </button>
          <button
            type="button"
            className={btnSecondary}
            onClick={handleChallengeResetToDefaults}
          >
            Reset to defaults
          </button>
          {challengeSaveState === "saved-live" ? (
            <span className="text-sm font-semibold text-[#0f6b4e]">
              Saved. Live in config/challengeAccess.
            </span>
          ) : challengeSaveState === "saved-staged" ? (
            <span className="text-sm font-semibold text-accent">
              Saved locally. Firebase is not connected, so this has not been
              written to a live backend.
            </span>
          ) : challengeSaveState === "error" && challengeErrorMessage ? (
            <span className="text-sm font-semibold text-[#b42318]">
              {challengeErrorMessage}
            </span>
          ) : null}
        </div>
      </section>

      <section className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
        <h2 className="text-base font-bold text-brand">Character access</h2>
        <ul className="mt-4 space-y-2">
          {RUNIAC_CHARACTERS.map((character) => {
            const premiumOnly = characterDraft.premiumOnlyCharacters.includes(
              character.characterId,
            );
            return (
              <li
                key={character.characterId}
                className="flex items-center justify-between gap-3 rounded-lg border border-border px-3 py-2.5"
              >
                <div className="min-w-0">
                  <p className="text-sm font-bold text-foreground">{character.name}</p>
                </div>
                <label className="inline-flex cursor-pointer items-center gap-2">
                  <span className="text-xs font-semibold text-muted">
                    {premiumOnly ? "Premium only" : "Open to all"}
                  </span>
                  <input
                    type="checkbox"
                    checked={premiumOnly}
                    onChange={(event) =>
                      setCharacterPremiumOnly(character.characterId, event.target.checked)
                    }
                    className="h-4 w-4 accent-[#001e62]"
                  />
                </label>
              </li>
            );
          })}
        </ul>

        {characterErrors.length > 0 ? (
          <div className="mt-4 rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm text-[#b42318]">
            <p className="font-bold">Fix these before saving:</p>
            <ul className="mt-1 list-disc space-y-0.5 pl-5">
              {characterErrors.map((error) => (
                <li key={error}>{error}</li>
              ))}
            </ul>
          </div>
        ) : null}

        <div className="mt-4 flex flex-wrap items-center gap-3">
          <button
            type="button"
            className={btnBrand}
            onClick={handleSaveCharacterAccess}
            disabled={characterSaveState === "saving"}
          >
            {characterSaveState === "saving" ? "Saving…" : "Save character access"}
          </button>
          <button
            type="button"
            className={btnSecondary}
            onClick={handleCharacterResetToDefaults}
          >
            Reset to defaults
          </button>
          {characterSaveState === "saved-live" ? (
            <span className="text-sm font-semibold text-[#0f6b4e]">
              Saved. Live in config/characterAccess.
            </span>
          ) : characterSaveState === "saved-staged" ? (
            <span className="text-sm font-semibold text-accent">
              Saved locally. Firebase is not connected, so this has not been
              written to a live backend.
            </span>
          ) : characterSaveState === "error" && characterErrorMessage ? (
            <span className="text-sm font-semibold text-[#b42318]">
              {characterErrorMessage}
            </span>
          ) : null}
        </div>
      </section>

      <section className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
        <h2 className="text-base font-bold text-brand">Moderation automation</h2>
        <ul className="mt-4 space-y-3">
          {AUTOMATION_RULES.map((rule) => renderAutomationRule(rule))}
        </ul>
      </section>

      {/* The Notification rules card (alert-on-error-groups, alert-on-new-
          reports, minimum severity) was removed from this screen. The values
          still live in config/automation.notifications and are carried through
          `automationDraft` untouched on every save — only the admin controls
          are gone, so Cloud Functions keep reading whatever is stored. */}

      {automationErrors.length > 0 ? (
        <div className="rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm text-[#b42318]">
          <p className="font-bold">Fix these before saving:</p>
          <ul className="mt-1 list-disc space-y-0.5 pl-5">
            {automationErrors.map((error) => (
              <li key={error}>{error}</li>
            ))}
          </ul>
        </div>
      ) : null}

      <div className="flex flex-wrap items-center gap-3">
        {automationSaveState === "confirm" ? (
          <>
            <span className="text-sm font-semibold text-foreground">
              This changes live automation for every user — auto-hide can remove
              content without further review. Confirm save?
            </span>
            <button
              type="button"
              className={btnBrand}
              onClick={handleAutomationConfirmSave}
            >
              Confirm save
            </button>
            <button
              type="button"
              className={btnSecondary}
              onClick={handleAutomationCancelConfirm}
            >
              Cancel
            </button>
          </>
        ) : (
          <>
            <button
              type="button"
              className={btnBrand}
              onClick={handleAutomationSaveClick}
              disabled={automationSaveState === "saving" || !automationDirty}
            >
              {automationSaveState === "saving" ? "Saving…" : "Save automation settings"}
            </button>
            <button
              type="button"
              className={btnSecondary}
              onClick={handleAutomationResetToDefaults}
            >
              Reset to defaults
            </button>
          </>
        )}
        {automationDirty && automationSaveState === "idle" ? (
          <span className="text-sm text-muted">Unsaved changes</span>
        ) : automationSaveState === "saved-live" ? (
          <span className="text-sm font-semibold text-[#0f6b4e]">
            Saved. Live in config/automation.
          </span>
        ) : automationSaveState === "saved-staged" ? (
          <span className="text-sm font-semibold text-accent">
            Saved locally. Firebase is not connected, so this has not been
            written to a live backend.
          </span>
        ) : automationSaveState === "error" && automationErrorMessage ? (
          <span className="text-sm font-semibold text-[#b42318]">
            {automationErrorMessage}
          </span>
        ) : null}
      </div>
    </div>
  );
}
