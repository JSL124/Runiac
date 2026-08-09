"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  restoreProgressionConfig,
  saveProgressionConfig,
} from "@/lib/actions/admin";
import {
  DEFAULT_PROGRESSION_CONFIG,
  validateProgressionConfig,
} from "@/lib/admin/config-validation";
import {
  btnBrand,
  btnSecondary,
  inputBase,
} from "@/components/admin/button-styles";
import { Chip } from "@/components/admin/primitives";
import { Pager, usePagination } from "@/components/admin/pagination";
import { formatDate } from "@/lib/admin/format";
import { LEVELS_PER_BAND, bandRanges, levelThresholds } from "@/lib/admin/level-curve";
import type { ConfigVersionEntry, ProgressionConfig } from "@/lib/admin/types";

const numberInput = `${inputBase} w-24 text-right tabular-nums`;
const wideNumberInput = `${inputBase} w-28 text-right tabular-nums`;

type SaveState = "idle" | "confirm" | "saving" | "saved-live" | "saved-staged" | "error";

export function GamificationRules({
  progressionConfig,
  history,
}: {
  progressionConfig: ProgressionConfig;
  history: ConfigVersionEntry[];
}) {
  const router = useRouter();

  const [config, setConfig] = useState<ProgressionConfig>(progressionConfig);
  const [errors, setErrors] = useState<string[]>([]);
  const [saveState, setSaveState] = useState<SaveState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const [levelsExpanded, setLevelsExpanded] = useState(false);

  // Restoring re-applies an earlier audited snapshot as a NEW version. It is
  // armed per row (two-step confirm) because it changes every user's XP economy.
  const [restoreArmedId, setRestoreArmedId] = useState<string | null>(null);
  const [restoringId, setRestoringId] = useState<string | null>(null);
  const [restoreError, setRestoreError] = useState<string | null>(null);
  const [restoreNote, setRestoreNote] = useState<string | null>(null);

  // History grows with every save, so it pages instead of rendering in full.
  // Leaving a row armed while paging away would put a confirm prompt out of
  // sight on a version the admin can no longer see.
  const historyPages = usePagination(history, {
    onPageChange: () => setRestoreArmedId(null),
  });

  const thresholds = levelThresholds(config.levelIncrements, config.maxLevel);
  const bands = bandRanges(config.levelIncrements, config.maxLevel);
  const maxThreshold = thresholds[thresholds.length - 1];

  function updateField<K extends keyof ProgressionConfig>(
    key: K,
    value: ProgressionConfig[K],
  ) {
    setConfig((prev) => ({ ...prev, [key]: value }));
    setErrors([]);
    setSaveState("idle");
    setErrorMessage(null);
  }

  function updateCoolDown(key: "percent" | "min" | "max", value: number) {
    setConfig((prev) => ({
      ...prev,
      coolDown: { ...prev.coolDown, [key]: value },
    }));
    setErrors([]);
    setSaveState("idle");
    setErrorMessage(null);
  }

  function updateIncrement(index: number, value: number) {
    setConfig((prev) => ({
      ...prev,
      levelIncrements: prev.levelIncrements.map((increment, i) =>
        i === index ? value : increment,
      ),
    }));
    setErrors([]);
    setSaveState("idle");
    setErrorMessage(null);
  }

  function addIncrement() {
    setConfig((prev) => {
      const last = prev.levelIncrements[prev.levelIncrements.length - 1] ?? 100;
      return {
        ...prev,
        levelIncrements: [...prev.levelIncrements, last + 100],
      };
    });
    setSaveState("idle");
  }

  function removeIncrement(index: number) {
    setConfig((prev) => {
      if (prev.levelIncrements.length <= 1) {
        return prev;
      }
      return {
        ...prev,
        levelIncrements: prev.levelIncrements.filter((_, i) => i !== index),
      };
    });
    setSaveState("idle");
  }

  function updateStreakReward(
    index: number,
    key: "milestoneDays" | "bonusXp",
    value: number,
  ) {
    setConfig((prev) => ({
      ...prev,
      streakRewards: prev.streakRewards.map((reward, i) =>
        i === index ? { ...reward, [key]: value } : reward,
      ),
    }));
    setErrors([]);
    setSaveState("idle");
    setErrorMessage(null);
  }

  function addStreakReward() {
    setConfig((prev) => {
      const last = prev.streakRewards[prev.streakRewards.length - 1];
      return {
        ...prev,
        streakRewards: [
          ...prev.streakRewards,
          {
            milestoneDays: last ? last.milestoneDays + 7 : 3,
            bonusXp: last ? last.bonusXp + 100 : 30,
          },
        ],
      };
    });
    setErrors([]);
    setSaveState("idle");
    setErrorMessage(null);
  }

  function removeStreakReward(index: number) {
    setConfig((prev) => ({
      ...prev,
      streakRewards: prev.streakRewards.filter((_, i) => i !== index),
    }));
    setErrors([]);
    setSaveState("idle");
    setErrorMessage(null);
  }

  function handleResetToDefaults() {
    setConfig(DEFAULT_PROGRESSION_CONFIG);
    setErrors([]);
    setSaveState("idle");
    setErrorMessage(null);
  }

  function handleSaveClick() {
    const result = validateProgressionConfig(config);

    if (!result.valid) {
      setErrors([...result.errors]);
      setSaveState("idle");
      return;
    }

    setErrors([]);
    // Progression rules control every user's XP economy — confirm before
    // writing.
    setSaveState("confirm");
  }

  function handleCancelConfirm() {
    setSaveState("idle");
  }

  // One page-wide save: the progression config. Any failure aborts and is
  // surfaced instead of a success message.
  async function handleConfirmSave() {
    setSaveState("saving");
    setErrorMessage(null);

    const progressionResult = await saveProgressionConfig(config);

    if (!progressionResult.ok) {
      setSaveState("error");
      setErrorMessage(progressionResult.error);
      return;
    }

    if (progressionResult.live === true) {
      setSaveState("saved-live");
      router.refresh();
    } else {
      setSaveState("saved-staged");
    }
  }

  async function handleConfirmRestore(entry: ConfigVersionEntry) {
    setRestoringId(entry.id);
    setRestoreError(null);
    setRestoreNote(null);

    const result = await restoreProgressionConfig(entry.id);

    setRestoringId(null);
    setRestoreArmedId(null);

    if (!result.ok) {
      setRestoreError(result.error);
      return;
    }

    if (result.config) {
      // Resync the form to what was actually written.
      setConfig(result.config);
    }

    setErrors([]);
    setSaveState("idle");
    setErrorMessage(null);
    setRestoreNote(
      `Restored ${entry.version === null ? "that snapshot" : `v${entry.version}`} as a new version.`,
    );
    router.refresh();
  }

  return (
    <div className="space-y-6">
      <section className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
        <h2 className="text-base font-bold text-brand">XP rules</h2>
        <ul className="mt-4 divide-y divide-border">
          <li className="flex flex-col gap-2 py-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="min-w-0">
              <p className="text-sm font-bold text-foreground">Complete an activity</p>
              <p className="text-xs text-muted">Base XP awarded when an activity is completed</p>
            </div>
            <label className="flex items-center gap-2">
              <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">XP</span>
              <input
                type="number"
                min={0}
                value={config.baseCompletionXp}
                onChange={(event) => updateField("baseCompletionXp", Number(event.target.value))}
                className={numberInput}
              />
            </label>
          </li>
          <li className="flex flex-col gap-2 py-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="min-w-0">
              <p className="text-sm font-bold text-foreground">Distance covered</p>
              <p className="text-xs text-muted">XP awarded per kilometer</p>
            </div>
            <label className="flex items-center gap-2">
              <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">XP/km</span>
              <input
                type="number"
                min={0}
                value={config.xpPerKilometer}
                onChange={(event) => updateField("xpPerKilometer", Number(event.target.value))}
                className={numberInput}
              />
            </label>
          </li>
          <li className="flex flex-col gap-2 py-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="min-w-0">
              <p className="text-sm font-bold text-foreground">Active minutes</p>
              <p className="text-xs text-muted">XP awarded per ten active minutes</p>
            </div>
            <label className="flex items-center gap-2">
              <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">XP/10min</span>
              <input
                type="number"
                min={0}
                value={config.xpPerTenActiveMinutes}
                onChange={(event) => updateField("xpPerTenActiveMinutes", Number(event.target.value))}
                className={numberInput}
              />
            </label>
          </li>
          <li className="flex flex-col gap-2 py-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="min-w-0">
              <p className="text-sm font-bold text-foreground">Complete an assigned plan</p>
              <p className="text-xs text-muted">Bonus XP awarded when a plan is completed</p>
            </div>
            <label className="flex items-center gap-2">
              <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">Bonus XP</span>
              <input
                type="number"
                min={0}
                value={config.planCompletionBonusXp}
                onChange={(event) => updateField("planCompletionBonusXp", Number(event.target.value))}
                className={numberInput}
              />
            </label>
          </li>
        </ul>
      </section>

      <div className="grid gap-6 lg:grid-cols-2">
        <section className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
          <h2 className="text-base font-bold text-brand">Caps & limits</h2>
          <div className="mt-4 space-y-3">
            <label className="flex items-center justify-between gap-3">
              <span className="text-sm font-semibold text-foreground">Activity XP cap</span>
              <input
                type="number"
                min={0}
                value={config.activityXpCap}
                onChange={(event) => updateField("activityXpCap", Number(event.target.value))}
                className={wideNumberInput}
              />
            </label>
            <label className="flex items-center justify-between gap-3">
              <span className="text-sm font-semibold text-foreground">Daily XP cap</span>
              <input
                type="number"
                min={0}
                value={config.dailyXpCap}
                onChange={(event) => updateField("dailyXpCap", Number(event.target.value))}
                className={wideNumberInput}
              />
            </label>
            <label className="flex items-center justify-between gap-3">
              <span className="text-sm font-semibold text-foreground">Max level</span>
              <input
                type="number"
                min={1}
                value={config.maxLevel}
                onChange={(event) => updateField("maxLevel", Number(event.target.value))}
                className={wideNumberInput}
              />
            </label>
          </div>
        </section>

        <section className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
          <h2 className="text-base font-bold text-brand">Cool-down</h2>
          <div className="mt-4 space-y-3">
            <label className="flex items-center justify-between gap-3">
              <span className="text-sm font-semibold text-foreground">Percent (0–1)</span>
              <input
                type="number"
                min={0}
                max={1}
                step={0.01}
                value={config.coolDown.percent}
                onChange={(event) => updateCoolDown("percent", Number(event.target.value))}
                className={wideNumberInput}
              />
            </label>
            <label className="flex items-center justify-between gap-3">
              <span className="text-sm font-semibold text-foreground">Min</span>
              <input
                type="number"
                min={0}
                value={config.coolDown.min}
                onChange={(event) => updateCoolDown("min", Number(event.target.value))}
                className={wideNumberInput}
              />
            </label>
            <label className="flex items-center justify-between gap-3">
              <span className="text-sm font-semibold text-foreground">Max</span>
              <input
                type="number"
                min={0}
                value={config.coolDown.max}
                onChange={(event) => updateCoolDown("max", Number(event.target.value))}
                className={wideNumberInput}
              />
            </label>
          </div>
        </section>
      </div>

      <section className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
        <button
          type="button"
          className="flex w-full items-center justify-between gap-3 text-left"
          onClick={() => setLevelsExpanded((prev) => !prev)}
          aria-expanded={levelsExpanded}
        >
          <div className="min-w-0">
            <h2 className="text-base font-bold text-brand">Level increments</h2>
          </div>
          <span className="flex shrink-0 items-center gap-2 text-xs font-bold text-muted">
            {bands.length} bands &middot; levels 1&ndash;{thresholds.length} &middot; max
            threshold {formatThreshold(maxThreshold)}
            <span
              aria-hidden
              className={`inline-block transition-transform ${levelsExpanded ? "rotate-180" : ""}`}
            >
              ▾
            </span>
          </span>
        </button>
        {levelsExpanded ? (
          <>
            <ul className="mt-4 space-y-2">
              {config.levelIncrements.map((increment, index) => {
                const band = bands.find((candidate) => candidate.index === index);
                // Bands maxLevel does not yet reach (max level was lowered
                // below this band's natural range) still need a level range
                // to display; fall back to the natural, unclamped span. This
                // is also the "unreached" case called out below — keeps the
                // "{bands.length} bands" header count and this list in
                // agreement instead of silently rendering a row the header
                // doesn't count.
                const firstLevel = band
                  ? band.firstLevel
                  : index === 0
                    ? 2
                    : index * LEVELS_PER_BAND + 1;
                const lastLevel = band ? band.lastLevel : firstLevel + LEVELS_PER_BAND - 1;
                const unreached = band === undefined;

                return (
                  <li key={index} className="flex flex-col gap-1">
                    <div className="flex items-center justify-between gap-3">
                      <Chip tone={unreached ? "muted" : "brand"}>
                        Levels {firstLevel}&ndash;{lastLevel}
                      </Chip>
                      <div className="flex items-center gap-2">
                        <span className="text-xs text-muted">
                          +{increment} XP per level &middot; threshold{" "}
                          {formatThreshold(band?.thresholdAtLastLevel)}
                        </span>
                        <input
                          type="number"
                          min={1}
                          value={increment}
                          onChange={(event) => updateIncrement(index, Number(event.target.value))}
                          className={numberInput}
                        />
                        <button
                          type="button"
                          className="text-xs font-bold text-muted hover:text-[#b42318] disabled:cursor-not-allowed disabled:opacity-40"
                          onClick={() => removeIncrement(index)}
                          disabled={config.levelIncrements.length <= 1}
                          aria-label={`Remove band covering levels ${firstLevel} to ${lastLevel}`}
                        >
                          Remove
                        </button>
                      </div>
                    </div>
                    {unreached ? (
                      <p className="text-right text-xs italic text-muted">
                        Not reached at max level {config.maxLevel} — only the first{" "}
                        {bands.length} band{bands.length === 1 ? "" : "s"} above are currently
                        reachable.
                      </p>
                    ) : null}
                  </li>
                );
              })}
            </ul>
            <button type="button" className={`${btnSecondary} mt-4`} onClick={addIncrement}>
              Add band ({LEVELS_PER_BAND} levels)
            </button>
          </>
        ) : null}
      </section>

      <section className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
        <h2 className="text-base font-bold text-brand">Streak rewards</h2>
        <ul className="mt-4 space-y-2">
          {config.streakRewards.map((streak, index) => {
            // Deliberately NOT compared against dailyXpCap: the milestone bonus
            // is exempt from it. Flagging a 600 XP reward as "will be trimmed"
            // used to push admins into lowering a reward that pays in full.
            const exceedsActivityCap = streak.bonusXp > config.activityXpCap;
            return (
              <li key={index} className="flex flex-col gap-1.5">
                <div className="flex items-center justify-between gap-3">
                  <Chip tone="muted">Milestone {index + 1}</Chip>
                  <div className="flex items-center gap-2">
                    <label className="flex items-center gap-2">
                      <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">Days</span>
                      <input
                        type="number"
                        min={1}
                        value={streak.milestoneDays}
                        onChange={(event) =>
                          updateStreakReward(index, "milestoneDays", Number(event.target.value))
                        }
                        className={numberInput}
                      />
                    </label>
                    <label className="flex items-center gap-2">
                      <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">Bonus</span>
                      <input
                        type="number"
                        min={0}
                        value={streak.bonusXp}
                        onChange={(event) =>
                          updateStreakReward(index, "bonusXp", Number(event.target.value))
                        }
                        className={numberInput}
                      />
                    </label>
                    <button
                      type="button"
                      className="text-xs font-bold text-muted hover:text-[#b42318] disabled:cursor-not-allowed disabled:opacity-40"
                      onClick={() => removeStreakReward(index)}
                      aria-label={`Remove streak milestone ${index + 1}`}
                    >
                      Remove
                    </button>
                  </div>
                </div>
                {exceedsActivityCap ? (
                  <p className="text-right text-xs text-muted">
                    Larger than the {config.activityXpCap} XP per-activity cap. Paid in
                    full anyway — milestone bonuses are exempt from both caps.
                  </p>
                ) : null}
              </li>
            );
          })}
        </ul>
        <button type="button" className={`${btnSecondary} mt-4`} onClick={addStreakReward}>
          Add streak milestone
        </button>
      </section>

      <section className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
        <h2 className="text-base font-bold text-brand">Configuration history</h2>
        {history.length === 0 ? (
          <p className="mt-4 text-sm text-muted">
            No configuration history has been recorded yet. The first save will
            appear here.
          </p>
        ) : (
          <ul className="mt-4 space-y-2">
            {historyPages.visible.map((entry) => (
              <li
                key={entry.id}
                className="flex flex-wrap items-center gap-3 rounded-lg border border-border px-3 py-2.5"
              >
                <Chip tone={entry.active ? "accent" : "muted"}>
                  {entry.version === null ? "—" : `v${entry.version}`}
                </Chip>
                <div className="min-w-0">
                  <p className="text-sm font-semibold text-foreground">
                    {entry.actor}
                    {entry.restored ? (
                      <span className="ml-2 text-xs font-bold uppercase tracking-[0.12em] text-accent">
                        Restored
                      </span>
                    ) : null}
                  </p>
                  <p className="text-xs text-muted">
                    {formatDate(entry.savedAt)} &middot;{" "}
                    {summarizeChangedFields(entry.changedFields)}
                  </p>
                </div>
                {entry.active ? (
                  <span className="ml-auto text-xs font-bold text-[#0f6b4e]">
                    Currently applied
                  </span>
                ) : restoreArmedId === entry.id ? (
                  <span className="ml-auto flex flex-wrap items-center gap-2">
                    <span className="text-xs font-semibold text-foreground">
                      This changes the XP economy for every user. Confirm restore?
                    </span>
                    <button
                      type="button"
                      className={btnBrand}
                      onClick={() => handleConfirmRestore(entry)}
                      disabled={restoringId !== null}
                    >
                      {restoringId === entry.id ? "Restoring…" : "Confirm restore"}
                    </button>
                    <button
                      type="button"
                      className={btnSecondary}
                      onClick={() => setRestoreArmedId(null)}
                      disabled={restoringId !== null}
                    >
                      Cancel
                    </button>
                  </span>
                ) : (
                  <button
                    type="button"
                    className={`${btnSecondary} ml-auto`}
                    onClick={() => {
                      setRestoreError(null);
                      setRestoreNote(null);
                      setRestoreArmedId(entry.id);
                    }}
                    disabled={restoringId !== null}
                  >
                    Restore this version
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}
        <div className="mt-4">
          <Pager
            pagination={historyPages}
            label="Configuration history pages"
          />
        </div>
        {restoreNote ? (
          <p className="mt-3 text-sm font-semibold text-[#0f6b4e]">{restoreNote}</p>
        ) : null}
        {restoreError ? (
          <p className="mt-3 text-sm font-semibold text-[#b42318]">{restoreError}</p>
        ) : null}
      </section>

      {errors.length > 0 ? (
        <div className="rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm text-[#b42318]">
          <p className="font-bold">Fix these before saving:</p>
          <ul className="mt-1 list-disc space-y-0.5 pl-5">
            {errors.map((error) => (
              <li key={error}>{error}</li>
            ))}
          </ul>
        </div>
      ) : null}

      <div className="flex flex-wrap items-center gap-3">
        {saveState === "confirm" ? (
          <>
            <span className="text-sm font-semibold text-foreground">
              This changes the XP economy for every user. Confirm save?
            </span>
            <button type="button" className={btnBrand} onClick={handleConfirmSave}>
              Confirm save
            </button>
            <button type="button" className={btnSecondary} onClick={handleCancelConfirm}>
              Cancel
            </button>
          </>
        ) : (
          <>
            <button
              type="button"
              className={btnBrand}
              onClick={handleSaveClick}
              disabled={saveState === "saving"}
            >
              {saveState === "saving" ? "Saving…" : "Save all changes"}
            </button>
            <button type="button" className={btnSecondary} onClick={handleResetToDefaults}>
              Reset to defaults
            </button>
          </>
        )}
        {saveState === "saved-live" ? (
          <span className="text-sm font-semibold text-[#0f6b4e]">
            Saved. Live in config/progression.
          </span>
        ) : saveState === "saved-staged" ? (
          <span className="text-sm font-semibold text-accent">
            Saved locally. Firebase is not connected, so this has not been
            written to a live backend.
          </span>
        ) : saveState === "error" && errorMessage ? (
          <span className="text-sm font-semibold text-[#b42318]">{errorMessage}</span>
        ) : null}
      </div>
    </div>
  );
}

// Compact one-line summary of the fields an audit entry recorded as changed.
function summarizeChangedFields(fields: string[]): string {
  if (fields.length === 0) {
    return "No field changes recorded";
  }

  const shown = fields.slice(0, 3).join(", ");
  const remaining = fields.length - 3;
  return remaining > 0 ? `${shown} +${remaining} more` : shown;
}

function formatThreshold(value: number | undefined): string {
  if (value === undefined) {
    return "-";
  }
  return value.toLocaleString("en-GB");
}
