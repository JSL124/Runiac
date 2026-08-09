"use client";

import { useState, useTransition } from "react";
import { btnDanger, btnGhost, btnSecondary, inputBase } from "@/components/admin/button-styles";
import { clearUserAvatar, moderateUser, setUserSubscription } from "@/lib/actions/admin";
import type { AdminActionResult } from "@/lib/actions/admin";
import type { UserModerationAction, UserSubscriptionStatus } from "@/lib/firebase/firestore";

const MODERATION_OPTIONS: { value: UserModerationAction; label: string }[] = [
  { value: "warn", label: "Warn" },
  { value: "suspend", label: "Suspend" },
  { value: "ban", label: "Ban" },
  { value: "restore", label: "Restore" },
];

const CONFIRM_REQUIRED: UserModerationAction[] = ["suspend", "ban"];

// Two per-user operational domains, each with real, immediate effect and a
// full audit trail. Subscription status only gates Basic/Premium feature
// access (never XP/rank/leaderboard benefit); moderation actions map to
// accountStatus (warn records the event without changing state). Every
// action goes through the requireAdmin()-gated server actions in
// src/lib/actions/admin.ts, never a client write.
export function UserOperationsPanel({
  uid,
  displayName,
  subscriptionStatus,
  subscriptionExpiresAt,
  hasAvatar,
  onSuccess,
}: {
  uid: string;
  displayName: string;
  subscriptionStatus: UserSubscriptionStatus | string;
  subscriptionExpiresAt: string | null;
  hasAvatar: boolean;
  onSuccess: (message: string, result: AdminActionResult) => void;
}) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const [subValue, setSubValue] = useState<UserSubscriptionStatus>(
    subscriptionStatus === "premium" ? "premium" : "basic",
  );
  const [subReason, setSubReason] = useState("");
  const [subExpiresAt, setSubExpiresAt] = useState(
    subscriptionExpiresAt ? subscriptionExpiresAt.slice(0, 10) : "",
  );

  const [modAction, setModAction] = useState<UserModerationAction>("warn");
  const [modReason, setModReason] = useState("");
  const [modConfirming, setModConfirming] = useState(false);

  const [avatarReason, setAvatarReason] = useState("");
  const [avatarConfirming, setAvatarConfirming] = useState(false);

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

  function submitModeration() {
    runAction(
      () => moderateUser(uid, modAction, modReason),
      `Applied "${modAction}" moderation to ${displayName}`,
      () => {
        setModReason("");
        setModConfirming(false);
      },
    );
  }

  function submitAvatarClear() {
    runAction(
      () => clearUserAvatar(uid, avatarReason),
      `Cleared avatar for ${displayName}`,
      () => {
        setAvatarReason("");
        setAvatarConfirming(false);
      },
    );
  }

  return (
    <div className="mt-4 rounded-lg border border-border bg-white p-4">
      <h3 className="text-sm font-bold text-brand">User operations</h3>
      <p className="mt-1 text-xs text-muted">
        Subscription and moderation controls for {displayName}. Every action
        requires a reason and is fully audited.
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
        {/* Subscription */}
        <div className="rounded-lg border border-border p-3">
          <p className="text-xs font-bold uppercase tracking-[0.1em] text-muted">
            Subscription
          </p>
          <div className="mt-2 flex flex-col gap-2">
            <select
              value={subValue}
              disabled={isPending}
              onChange={(event) =>
                setSubValue(event.target.value as UserSubscriptionStatus)
              }
              className={`${inputBase} cursor-pointer pr-8`}
            >
              <option value="basic">Basic</option>
              <option value="premium">Premium</option>
            </select>
            {subValue === "premium" ? (
              <label className="flex flex-col gap-1">
                <span className="text-[0.7rem] font-bold uppercase tracking-[0.1em] text-muted">
                  Expires on (optional)
                </span>
                <input
                  type="date"
                  value={subExpiresAt}
                  disabled={isPending}
                  onChange={(event) => setSubExpiresAt(event.target.value)}
                  className={inputBase}
                />
                <span className="text-[0.7rem] text-muted">
                  {subExpiresAt
                    ? "Downgrades to Basic automatically after this date."
                    : "Leave empty for a Premium grant that never lapses."}
                </span>
              </label>
            ) : null}
            <input
              type="text"
              placeholder="Reason (required)"
              value={subReason}
              onChange={(event) => setSubReason(event.target.value)}
              className={inputBase}
            />
            <button
              type="button"
              className={btnSecondary}
              disabled={isPending || subReason.trim() === ""}
              onClick={() =>
                runAction(
                  () =>
                    setUserSubscription(
                      uid,
                      subValue,
                      subReason,
                      subValue === "premium" ? subExpiresAt : undefined,
                    ),
                  `Set subscription to ${subValue} for ${displayName}` +
                    (subValue === "premium" && subExpiresAt
                      ? ` until ${subExpiresAt}`
                      : ""),
                  () => setSubReason(""),
                )
              }
            >
              {isPending ? "Working..." : "Set subscription"}
            </button>
          </div>
        </div>

        {/* Moderation */}
        <div className="rounded-lg border border-border p-3">
          <p className="text-xs font-bold uppercase tracking-[0.1em] text-muted">
            Moderation
          </p>
          <div className="mt-2 flex flex-col gap-2">
            <select
              value={modAction}
              disabled={isPending}
              onChange={(event) => {
                setModAction(event.target.value as UserModerationAction);
                setModConfirming(false);
              }}
              className={`${inputBase} cursor-pointer pr-8`}
            >
              {MODERATION_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
            <input
              type="text"
              placeholder="Reason (required)"
              value={modReason}
              onChange={(event) => {
                setModReason(event.target.value);
                setModConfirming(false);
              }}
              className={inputBase}
            />
            {modConfirming ? (
              <div className="flex gap-2">
                <button
                  type="button"
                  className={btnDanger}
                  disabled={isPending}
                  onClick={submitModeration}
                >
                  {isPending ? "Working..." : `Confirm ${modAction}`}
                </button>
                <button
                  type="button"
                  className={btnGhost}
                  disabled={isPending}
                  onClick={() => setModConfirming(false)}
                >
                  Cancel
                </button>
              </div>
            ) : (
              <button
                type="button"
                className={
                  CONFIRM_REQUIRED.includes(modAction) ? btnDanger : btnSecondary
                }
                disabled={isPending || modReason.trim() === ""}
                onClick={() => {
                  if (CONFIRM_REQUIRED.includes(modAction)) {
                    setModConfirming(true);
                    return;
                  }
                  submitModeration();
                }}
              >
                {isPending
                  ? "Working..."
                  : MODERATION_OPTIONS.find((option) => option.value === modAction)
                      ?.label ?? "Apply"}
              </button>
            )}
          </div>
        </div>

        {/* Avatar takedown */}
        <div className="rounded-lg border border-border p-3">
          <p className="text-xs font-bold uppercase tracking-[0.1em] text-muted">
            Avatar
          </p>
          <p className="mt-1 text-xs text-muted">
            {hasAvatar
              ? "Deletes the stored profile photo from Cloud Storage (both the current and previous generation) and clears it from the profile. Deleting the object is the only way to actually revoke it — clearing the field alone leaves it fetchable by anyone holding the link."
              : `${displayName} has no profile photo set.`}
          </p>
          <div className="mt-2 flex flex-col gap-2">
            <input
              type="text"
              placeholder="Reason (required)"
              value={avatarReason}
              disabled={isPending || !hasAvatar}
              onChange={(event) => {
                setAvatarReason(event.target.value);
                setAvatarConfirming(false);
              }}
              className={inputBase}
            />
            {avatarConfirming ? (
              <div className="flex gap-2">
                <button
                  type="button"
                  className={btnDanger}
                  disabled={isPending}
                  onClick={submitAvatarClear}
                >
                  {isPending ? "Working..." : "Confirm clear avatar"}
                </button>
                <button
                  type="button"
                  className={btnGhost}
                  disabled={isPending}
                  onClick={() => setAvatarConfirming(false)}
                >
                  Cancel
                </button>
              </div>
            ) : (
              <button
                type="button"
                className={btnDanger}
                disabled={isPending || !hasAvatar || avatarReason.trim() === ""}
                onClick={() => setAvatarConfirming(true)}
              >
                Clear avatar
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
