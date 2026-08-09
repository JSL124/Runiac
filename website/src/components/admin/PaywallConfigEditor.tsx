"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  restorePaywallConfig,
  savePaywallConfig,
} from "@/lib/actions/admin";
import {
  DEFAULT_PAYWALL_CONFIG,
  PAYWALL_MAX_FEATURES,
  validatePaywallConfig,
  type PaywallConfig,
  type PaywallFeature,
  type PaywallFooter,
  type PaywallPrice,
} from "@/lib/admin/paywall-config";
import {
  btnBrand,
  btnSecondary,
  inputBase,
} from "@/components/admin/button-styles";
import { Chip } from "@/components/admin/primitives";
import { Pager, usePagination } from "@/components/admin/pagination";
import { formatDate } from "@/lib/admin/format";
import type { ConfigVersionEntry } from "@/lib/admin/types";

const fieldLabel =
  "text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted";
const sectionCard =
  "rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6";

type SaveState = "idle" | "confirm" | "saving" | "saved-live" | "saved-staged" | "error";

export function PaywallConfigEditor({
  paywallConfig,
  history,
}: {
  paywallConfig: PaywallConfig;
  history: ConfigVersionEntry[];
}) {
  const router = useRouter();

  const [config, setConfig] = useState<PaywallConfig>(paywallConfig);
  const [errors, setErrors] = useState<string[]>([]);
  const [saveState, setSaveState] = useState<SaveState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Restoring re-applies an earlier audited snapshot as a NEW version. It is
  // armed per row (two-step confirm) because the copy is user-visible in the
  // app immediately.
  const [restoreArmedId, setRestoreArmedId] = useState<string | null>(null);
  const [restoringId, setRestoringId] = useState<string | null>(null);
  const [restoreError, setRestoreError] = useState<string | null>(null);
  const [restoreNote, setRestoreNote] = useState<string | null>(null);

  const historyPages = usePagination(history, {
    onPageChange: () => setRestoreArmedId(null),
  });

  function markDirty() {
    setErrors([]);
    setSaveState("idle");
    setErrorMessage(null);
  }

  function updateField<K extends keyof PaywallConfig>(
    key: K,
    value: PaywallConfig[K],
  ) {
    setConfig((prev) => ({ ...prev, [key]: value }));
    markDirty();
  }

  function updatePrice(
    plan: "monthly" | "yearly",
    key: keyof PaywallPrice,
    value: string,
  ) {
    setConfig((prev) => ({
      ...prev,
      [plan]: { ...prev[plan], [key]: value },
    }));
    markDirty();
  }

  function updateFooter<K extends keyof PaywallFooter>(
    key: K,
    value: PaywallFooter[K],
  ) {
    setConfig((prev) => ({
      ...prev,
      footer: { ...prev.footer, [key]: value },
    }));
    markDirty();
  }

  function updateFeature(
    index: number,
    key: keyof PaywallFeature,
    value: string,
  ) {
    setConfig((prev) => ({
      ...prev,
      features: prev.features.map((feature, i) =>
        i === index ? { ...feature, [key]: value } : feature,
      ),
    }));
    markDirty();
  }

  function addFeature() {
    setConfig((prev) => {
      if (prev.features.length >= PAYWALL_MAX_FEATURES) {
        return prev;
      }
      return {
        ...prev,
        features: [...prev.features, { title: "", subtitle: "" }],
      };
    });
    markDirty();
  }

  function removeFeature(index: number) {
    setConfig((prev) => {
      if (prev.features.length <= 1) {
        return prev;
      }
      return {
        ...prev,
        features: prev.features.filter((_, i) => i !== index),
      };
    });
    markDirty();
  }

  // The app highlights features top-to-bottom in this exact order, so order
  // is content — hence explicit move controls instead of sort-on-save.
  function moveFeature(index: number, delta: -1 | 1) {
    setConfig((prev) => {
      const target = index + delta;
      if (target < 0 || target >= prev.features.length) {
        return prev;
      }
      const features = [...prev.features];
      const [moved] = features.splice(index, 1);
      features.splice(target, 0, moved);
      return { ...prev, features };
    });
    markDirty();
  }

  function handleResetToDefaults() {
    setConfig(DEFAULT_PAYWALL_CONFIG);
    markDirty();
  }

  function handleSaveClick() {
    const result = validatePaywallConfig(config);

    if (!result.valid) {
      setErrors([...result.errors]);
      setSaveState("idle");
      return;
    }

    setErrors([]);
    // This copy is shown to every Basic user in the app — confirm before
    // writing.
    setSaveState("confirm");
  }

  async function handleConfirmSave() {
    setSaveState("saving");
    setErrorMessage(null);

    const result = await savePaywallConfig(config);

    if (!result.ok) {
      setSaveState("error");
      setErrorMessage(result.error);
      return;
    }

    if (result.live === true) {
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

    const result = await restorePaywallConfig(entry.id);

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
      <section className={sectionCard}>
        <h2 className="text-base font-bold text-brand">Plan info</h2>
        <div className="mt-4 space-y-3">
          <label className="flex items-center justify-between gap-3 rounded-lg border border-border p-3">
            <span className="min-w-0">
              <span className="block text-sm font-bold text-foreground">
                Paywall enabled
              </span>
              <span className="block text-xs text-muted">
                When off, tapping a premium feature no longer opens the upsell
                sheet (UX kill switch — backend enforcement is unaffected).
              </span>
            </span>
            <input
              type="checkbox"
              checked={config.enabled}
              onChange={() => updateField("enabled", !config.enabled)}
              className="h-4 w-4 accent-[#001e62]"
            />
          </label>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block">
              <span className={fieldLabel}>Title</span>
              <input
                type="text"
                value={config.title}
                onChange={(event) => updateField("title", event.target.value)}
                className={`${inputBase} mt-1`}
              />
            </label>
            <label className="block">
              <span className={fieldLabel}>Badge (empty hides the pill)</span>
              <input
                type="text"
                value={config.badge}
                onChange={(event) => updateField("badge", event.target.value)}
                className={`${inputBase} mt-1`}
              />
            </label>
          </div>
        </div>
      </section>

      <section className={sectionCard}>
        <h2 className="text-base font-bold text-brand">Features</h2>
        <ul className="mt-4 space-y-2">
          {config.features.map((feature, index) => (
            <li
              key={index}
              className="rounded-lg border border-border p-3"
            >
              <div className="flex flex-wrap items-start gap-3">
                <Chip tone="muted">{index + 1}</Chip>
                <div className="min-w-0 flex-1 space-y-2">
                  <label className="block">
                    <span className={fieldLabel}>Title</span>
                    <input
                      type="text"
                      value={feature.title}
                      onChange={(event) =>
                        updateFeature(index, "title", event.target.value)
                      }
                      className={`${inputBase} mt-1`}
                    />
                  </label>
                  <label className="block">
                    <span className={fieldLabel}>Subtitle (optional)</span>
                    <input
                      type="text"
                      value={feature.subtitle}
                      onChange={(event) =>
                        updateFeature(index, "subtitle", event.target.value)
                      }
                      className={`${inputBase} mt-1`}
                    />
                  </label>
                </div>
                <div className="flex items-center gap-1">
                  <button
                    type="button"
                    className={btnSecondary}
                    onClick={() => moveFeature(index, -1)}
                    disabled={index === 0}
                    aria-label={`Move feature ${index + 1} up`}
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    className={btnSecondary}
                    onClick={() => moveFeature(index, 1)}
                    disabled={index === config.features.length - 1}
                    aria-label={`Move feature ${index + 1} down`}
                  >
                    ↓
                  </button>
                  <button
                    type="button"
                    className="ml-1 text-xs font-bold text-muted hover:text-[#b42318] disabled:cursor-not-allowed disabled:opacity-40"
                    onClick={() => removeFeature(index)}
                    disabled={config.features.length <= 1}
                    aria-label={`Remove feature ${index + 1}`}
                  >
                    Remove
                  </button>
                </div>
              </div>
            </li>
          ))}
        </ul>
        <button
          type="button"
          className={`${btnSecondary} mt-4`}
          onClick={addFeature}
          disabled={config.features.length >= PAYWALL_MAX_FEATURES}
        >
          Add feature
        </button>
      </section>

      <div className="grid gap-6 lg:grid-cols-2">
        {(
          [
            ["monthly", "Monthly plan"],
            ["yearly", "Yearly plan"],
          ] as const
        ).map(([plan, heading]) => (
          <section key={plan} className={sectionCard}>
            <h2 className="text-base font-bold text-brand">{heading}</h2>
            <div className="mt-4 space-y-3">
              <div className="grid gap-3 sm:grid-cols-2">
                <label className="block">
                  <span className={fieldLabel}>Price</span>
                  <input
                    type="text"
                    value={config[plan].price}
                    onChange={(event) =>
                      updatePrice(plan, "price", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
                <label className="block">
                  <span className={fieldLabel}>Period label</span>
                  <input
                    type="text"
                    value={config[plan].period}
                    onChange={(event) =>
                      updatePrice(plan, "period", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
              </div>
              <label className="block">
                <span className={fieldLabel}>Note (optional, shown when selected)</span>
                <input
                  type="text"
                  value={config[plan].note}
                  onChange={(event) =>
                    updatePrice(plan, "note", event.target.value)
                  }
                  className={`${inputBase} mt-1`}
                />
              </label>
            </div>
          </section>
        ))}
      </div>

      <section className={sectionCard}>
        <h2 className="text-base font-bold text-brand">Subscribe button & footer</h2>
        <div className="mt-4 space-y-3">
          <label className="block">
            <span className={fieldLabel}>Button label</span>
            <input
              type="text"
              value={config.ctaLabel}
              onChange={(event) => updateField("ctaLabel", event.target.value)}
              className={`${inputBase} mt-1`}
            />
          </label>
          {(
            [
              ["showTerms", "termsLabel", "Terms link"],
              ["showPrivacy", "privacyLabel", "Privacy link"],
            ] as const
          ).map(([toggleKey, labelKey, heading]) => (
            <div
              key={toggleKey}
              className="flex flex-wrap items-center gap-3 rounded-lg border border-border p-3"
            >
              <label className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={config.footer[toggleKey]}
                  onChange={() =>
                    updateFooter(toggleKey, !config.footer[toggleKey])
                  }
                  className="h-4 w-4 accent-[#001e62]"
                />
                <span className="text-sm font-bold text-foreground">
                  {heading}
                </span>
              </label>
              <input
                type="text"
                value={config.footer[labelKey]}
                onChange={(event) =>
                  updateFooter(labelKey, event.target.value)
                }
                disabled={!config.footer[toggleKey]}
                className={`${inputBase} min-w-40 flex-1`}
              />
            </div>
          ))}
        </div>
      </section>

      <section className={sectionCard}>
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
                      Basic users see this copy on their next paywall open.
                      Confirm restore?
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
          <Pager pagination={historyPages} label="Configuration history pages" />
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
              Basic users see this copy on their next paywall open. Confirm
              save?
            </span>
            <button type="button" className={btnBrand} onClick={handleConfirmSave}>
              Confirm save
            </button>
            <button
              type="button"
              className={btnSecondary}
              onClick={() => setSaveState("idle")}
            >
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
            <button
              type="button"
              className={btnSecondary}
              onClick={handleResetToDefaults}
            >
              Reset to defaults
            </button>
          </>
        )}
        {saveState === "saved-live" ? (
          <span className="text-sm font-semibold text-[#0f6b4e]">
            Saved. Live in config/paywall.
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
