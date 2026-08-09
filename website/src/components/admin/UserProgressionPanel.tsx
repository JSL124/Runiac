"use client";

import { useMemo, useState, useTransition } from "react";
import { btnDanger, btnGhost, btnSecondary, inputBase } from "@/components/admin/button-styles";
import {
  adjustUserXp,
  resetUserProgression,
  setUserLevel,
  setUserXp,
} from "@/lib/actions/admin";
import type { AdminActionResult } from "@/lib/actions/admin";
import { formatNumber } from "@/lib/admin/format";
import { levelForTotalXp, xpForLevel } from "@/lib/admin/progression-curve";
import { DEFAULT_PROGRESSION_CONFIG } from "@/lib/admin/config-validation";

// Parses a raw input string into a finite number, or null when the input is
// empty/unparseable. Used to gate live previews so they only render once the
// admin has typed something that would actually be accepted.
function parseFiniteNumber(raw: string): number | null {
  const trimmed = raw.trim();

  if (trimmed === "") {
    return null;
  }

  const value = Number(trimmed);
  return Number.isFinite(value) ? value : null;
}

// Direct per-user progression administration. This is a privileged, audited
// override path (support/correction scenarios) — it always goes through the
// Admin-SDK server actions in src/lib/actions/admin.ts, never a client write.
// Set/Adjust XP recompute level from the current progression curve; Set Level
// backfills the level's minimum total XP on the same curve; Reset zeroes both.
export function UserProgressionPanel({
  uid,
  displayName,
  totalXp,
  level,
  monthlyXp,
  onSuccess,
}: {
  uid: string;
  displayName: string;
  totalXp: number | null;
  level: number | null;
  monthlyXp: number | null;
  onSuccess: (message: string, result: AdminActionResult) => void;
}) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const [xpValue, setXpValue] = useState("");
  const [xpReason, setXpReason] = useState("");
  const [xpConfirming, setXpConfirming] = useState(false);

  const [deltaValue, setDeltaValue] = useState("");
  const [deltaReason, setDeltaReason] = useState("");

  const [levelValue, setLevelValue] = useState("");
  const [levelReason, setLevelReason] = useState("");
  const [levelConfirming, setLevelConfirming] = useState(false);

  const [resetReason, setResetReason] = useState("");
  const [resetConfirming, setResetConfirming] = useState(false);

  // Previews always use the default progression config — the same one
  // setUserXp()/adjustUserXp()/setUserLevel() actually call levelForTotalXp()
  // with — so the preview never disagrees with what the write will do, even
  // if the live Firestore progression config differs from the default.
  const setXpPreview = useMemo(() => {
    const parsed = parseFiniteNumber(xpValue);

    if (parsed === null || parsed < 0) {
      return null;
    }

    const nextXp = Math.floor(parsed);
    const currentLevel = levelForTotalXp(totalXp ?? 0, DEFAULT_PROGRESSION_CONFIG);
    const nextLevel = levelForTotalXp(nextXp, DEFAULT_PROGRESSION_CONFIG);

    return { nextXp, currentLevel, nextLevel };
  }, [xpValue, totalXp]);

  const adjustXpPreview = useMemo(() => {
    const parsed = parseFiniteNumber(deltaValue);

    if (parsed === null) {
      return null;
    }

    const nextXp = Math.max(0, (totalXp ?? 0) + Math.floor(parsed));
    const currentLevel = levelForTotalXp(totalXp ?? 0, DEFAULT_PROGRESSION_CONFIG);
    const nextLevel = levelForTotalXp(nextXp, DEFAULT_PROGRESSION_CONFIG);

    return { nextXp, currentLevel, nextLevel };
  }, [deltaValue, totalXp]);

  const setLevelPreview = useMemo(() => {
    const parsed = parseFiniteNumber(levelValue);

    if (parsed === null || parsed < 1) {
      return null;
    }

    const nextLevel = Math.min(
      Math.floor(parsed),
      DEFAULT_PROGRESSION_CONFIG.maxLevel,
    );
    const nextXp = xpForLevel(nextLevel, DEFAULT_PROGRESSION_CONFIG);

    return { nextLevel, nextXp };
  }, [levelValue]);

  function runAction(
    action: () => Promise<AdminActionResult>,
    successMessage: string,
    onOk: () => void,
  ) {
    setError(null);
    startTransition(async () => {
      const result = await action();

      if (!result.ok) {
        setError(result.error);
        return;
      }

      onOk();
      onSuccess(successMessage, result);
    });
  }

  const currentStateParts: string[] = [];
  if (level !== null) {
    currentStateParts.push(`Level ${level}`);
  }
  if (totalXp !== null) {
    currentStateParts.push(`${formatNumber(totalXp)} XP total`);
  }
  if (monthlyXp !== null) {
    currentStateParts.push(`${formatNumber(monthlyXp)} XP this month`);
  }

  return (
    <div className="mt-4 rounded-lg border border-border bg-white p-4">
      <h3 className="text-sm font-bold text-brand">Progression management</h3>
      <p className="mt-1 text-xs text-muted">
        Direct XP/level corrections for {displayName}. Every action is
        audited with a reason and cannot be performed by the client app.
      </p>

      <p className="mt-2 text-xs font-semibold text-foreground">
        {currentStateParts.length > 0
          ? currentStateParts.join(" · ")
          : "No progression recorded yet."}
      </p>

      {error ? (
        <p
          role="alert"
          className="mt-3 rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-3 py-2 text-xs font-semibold text-[#b42318]"
        >
          {error}
        </p>
      ) : null}

      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        {/* Set XP (exact) */}
        <div className="rounded-lg border border-border p-3">
          <p className="text-xs font-bold uppercase tracking-[0.1em] text-muted">
            Set XP (exact)
          </p>
          <div className="mt-2 flex flex-col gap-2">
            <input
              type="number"
              min={0}
              step={1}
              placeholder="Total XP"
              value={xpValue}
              onChange={(event) => {
                setXpValue(event.target.value);
                setXpConfirming(false);
              }}
              className={inputBase}
            />
            {setXpPreview ? (
              <p className="text-xs text-muted">
                {formatNumber(totalXp ?? 0)} &rarr;{" "}
                {formatNumber(setXpPreview.nextXp)} XP &middot; Level{" "}
                {setXpPreview.currentLevel} &rarr; {setXpPreview.nextLevel}
              </p>
            ) : null}
            <input
              type="text"
              placeholder="Reason (required)"
              value={xpReason}
              onChange={(event) => {
                setXpReason(event.target.value);
                setXpConfirming(false);
              }}
              className={inputBase}
            />
            {xpConfirming ? (
              <div className="flex gap-2">
                <button
                  type="button"
                  className={btnDanger}
                  disabled={isPending}
                  onClick={() =>
                    runAction(
                      () => setUserXp(uid, Number(xpValue), xpReason),
                      `Set XP to ${xpValue} for ${displayName}`,
                      () => {
                        setXpValue("");
                        setXpReason("");
                        setXpConfirming(false);
                      },
                    )
                  }
                >
                  {isPending ? "Working..." : "Confirm set XP"}
                </button>
                <button
                  type="button"
                  className={btnGhost}
                  disabled={isPending}
                  onClick={() => setXpConfirming(false)}
                >
                  Cancel
                </button>
              </div>
            ) : (
              <button
                type="button"
                className={btnSecondary}
                disabled={isPending || xpValue.trim() === "" || xpReason.trim() === ""}
                onClick={() => setXpConfirming(true)}
              >
                Set XP
              </button>
            )}
          </div>
        </div>

        {/* Adjust XP (delta) */}
        <div className="rounded-lg border border-border p-3">
          <p className="text-xs font-bold uppercase tracking-[0.1em] text-muted">
            Adjust XP (+/-)
          </p>
          <div className="mt-2 flex flex-col gap-2">
            <input
              type="number"
              step={1}
              placeholder="Delta, e.g. -50 or 50"
              value={deltaValue}
              onChange={(event) => setDeltaValue(event.target.value)}
              className={inputBase}
            />
            {adjustXpPreview ? (
              <p className="text-xs text-muted">
                {formatNumber(totalXp ?? 0)} &rarr;{" "}
                {formatNumber(adjustXpPreview.nextXp)} XP &middot; Level{" "}
                {adjustXpPreview.currentLevel} &rarr; {adjustXpPreview.nextLevel}
              </p>
            ) : null}
            <input
              type="text"
              placeholder="Reason (required)"
              value={deltaReason}
              onChange={(event) => setDeltaReason(event.target.value)}
              className={inputBase}
            />
            <button
              type="button"
              className={btnSecondary}
              disabled={
                isPending || deltaValue.trim() === "" || deltaReason.trim() === ""
              }
              onClick={() =>
                runAction(
                  () => adjustUserXp(uid, Number(deltaValue), deltaReason),
                  `Adjusted XP by ${deltaValue} for ${displayName}`,
                  () => {
                    setDeltaValue("");
                    setDeltaReason("");
                  },
                )
              }
            >
              {isPending ? "Working..." : "Adjust XP"}
            </button>
          </div>
        </div>

        {/* Set Level (override) */}
        <div className="rounded-lg border border-border p-3">
          <p className="text-xs font-bold uppercase tracking-[0.1em] text-muted">
            Set level (explicit override)
          </p>
          <div className="mt-2 flex flex-col gap-2">
            <input
              type="number"
              min={1}
              step={1}
              placeholder="Level"
              value={levelValue}
              onChange={(event) => {
                setLevelValue(event.target.value);
                setLevelConfirming(false);
              }}
              className={inputBase}
            />
            {setLevelPreview ? (
              <p className="text-xs text-muted">
                Level {level ?? "—"} &rarr; {setLevelPreview.nextLevel}{" "}
                &middot; total XP {totalXp !== null ? formatNumber(totalXp) : "—"}{" "}
                &rarr; {formatNumber(setLevelPreview.nextXp)} (level minimum)
              </p>
            ) : null}
            <input
              type="text"
              placeholder="Reason (required)"
              value={levelReason}
              onChange={(event) => {
                setLevelReason(event.target.value);
                setLevelConfirming(false);
              }}
              className={inputBase}
            />
            {levelConfirming ? (
              <div className="flex gap-2">
                <button
                  type="button"
                  className={btnDanger}
                  disabled={isPending}
                  onClick={() =>
                    runAction(
                      () => setUserLevel(uid, Number(levelValue), levelReason),
                      `Set level to ${levelValue} for ${displayName}`,
                      () => {
                        setLevelValue("");
                        setLevelReason("");
                        setLevelConfirming(false);
                      },
                    )
                  }
                >
                  {isPending ? "Working..." : "Confirm set level"}
                </button>
                <button
                  type="button"
                  className={btnGhost}
                  disabled={isPending}
                  onClick={() => setLevelConfirming(false)}
                >
                  Cancel
                </button>
              </div>
            ) : (
              <button
                type="button"
                className={btnSecondary}
                disabled={
                  isPending || levelValue.trim() === "" || levelReason.trim() === ""
                }
                onClick={() => setLevelConfirming(true)}
              >
                Set level
              </button>
            )}
          </div>
        </div>

        {/* Reset progression */}
        <div className="rounded-lg border border-border p-3">
          <p className="text-xs font-bold uppercase tracking-[0.1em] text-muted">
            Reset progression
          </p>
          <p className="mt-1 text-xs text-muted">
            Sets total XP, level, and monthly XP back to their starting
            values.
          </p>
          <div className="mt-2 flex flex-col gap-2">
            <input
              type="text"
              placeholder="Reason (required)"
              value={resetReason}
              onChange={(event) => {
                setResetReason(event.target.value);
                setResetConfirming(false);
              }}
              className={inputBase}
            />
            {resetConfirming ? (
              <div className="flex gap-2">
                <button
                  type="button"
                  className={btnDanger}
                  disabled={isPending}
                  onClick={() =>
                    runAction(
                      () => resetUserProgression(uid, resetReason),
                      `Reset progression for ${displayName}`,
                      () => {
                        setResetReason("");
                        setResetConfirming(false);
                      },
                    )
                  }
                >
                  {isPending ? "Working..." : "Confirm reset"}
                </button>
                <button
                  type="button"
                  className={btnGhost}
                  disabled={isPending}
                  onClick={() => setResetConfirming(false)}
                >
                  Cancel
                </button>
              </div>
            ) : (
              <button
                type="button"
                className={btnDanger}
                disabled={isPending || resetReason.trim() === ""}
                onClick={() => setResetConfirming(true)}
              >
                Reset progression
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
