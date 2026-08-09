"use client";

import { useRouter } from "next/navigation";
import { useMemo, useRef, useState } from "react";
import {
  btnDanger,
  btnPrimary,
  btnSecondary,
} from "@/components/admin/button-styles";
import {
  getModerationCommandStatus,
  requestFeedPostRemoval,
  resolveReport as resolveReportAction,
  setUserAccountStatus as setUserAccountStatusAction,
} from "@/lib/actions/admin";
import {
  Chip,
  EmptyState,
  SeverityBadge,
  WorkflowStatusBadge,
} from "@/components/admin/primitives";
import {
  EXCEPTION_TYPE_OPTIONS,
  exceptionSourceLabel,
  exceptionTypeLabel,
  formatDateTime,
} from "@/lib/admin/format";
import type {
  ExceptionCase,
  ExceptionStatus,
  Severity,
} from "@/lib/admin/types";

// Only the two severities an exception case can actually carry.
// toReportSeverity() (src/lib/admin/live-data.ts) returns "high" when the
// report reason mentions harassment/abuse/unsafe and "medium" otherwise —
// "low" and "critical" are unreachable here. They stay in the shared
// `Severity` union because the Errors & Crashes and Feedback pages do use
// them; listing them in THIS filter only ever produced an empty result.
const SEVERITIES: Severity[] = ["medium", "high"];
// "reviewing" is kept even though no console action produces it any more
// (the Escalate button that did is gone). Unlike the route/plan case types,
// this one is not hypothetical: production `reports` already holds a document
// in that state, and both the type union and this filter must keep
// representing it honestly rather than silently re-reading it as "pending".
const STATUSES: ExceptionStatus[] = [
  "pending",
  "reviewing",
  "resolved",
  "dismissed",
];

const selectClass =
  "h-9 w-auto min-w-[9rem] cursor-pointer rounded-lg border border-border bg-white px-3 pr-8 text-sm font-semibold text-foreground outline-none transition-colors duration-150 hover:border-brand/30 focus:border-brand focus:ring-2 focus:ring-brand/15";

const noteClass =
  "w-full min-h-[4.5rem] rounded-lg border border-border bg-white px-3 py-2 text-sm font-semibold text-foreground outline-none transition-colors duration-150 placeholder:text-muted/60 hover:border-brand/30 focus:border-brand focus:ring-2 focus:ring-brand/15 disabled:cursor-not-allowed disabled:opacity-60";

// Bounded polling for the moderationCommands document "Remove post" writes:
// the moderationCommandCreated Cloud Function trigger
// (functions/src/moderation/moderationCommand.ts) consumes it asynchronously,
// so the console has to poll rather than block on a single round trip.
// Mirrors the recalc() polling idiom in LeaderboardOversight.tsx. Polling
// stops after maxPollAttempts rather than running forever.
const maxPollAttempts = 15;
const pollIntervalMs = 2000;
// Iterated with for...of below instead of a mutable `let i; i += 1` counter,
// so no loop variable is reassigned across the closures the polling loop
// hands to the setRemovePostState functional updater.
const pollAttempts = Array.from({ length: maxPollAttempts }, (_, index) => index + 1);

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Every variant here is read by the render below: "requesting"/"polling"
// drive the busy state, "completed" pins the button label, "timed-out" is the
// one terminal state with no outcome text of its own. Failure paths return to
// "idle" — the button becomes retryable and the Outcome list already carries
// the error message, so separate "failed"/"error"/"not-live" states were
// written but never read.
type RemovePostState =
  | { kind: "idle" }
  | { kind: "requesting" }
  | { kind: "polling"; attempt: number }
  | { kind: "completed" }
  | { kind: "timed-out" };

// A real outcome derived from a server action's result — not an optimistic
// local string. Replaces the old demo `actionLog`, whose own comment admitted
// non-user cases "record the intent locally for the demo".
type CaseOutcome = {
  id: string;
  label: string;
  message: string;
  tone: "success" | "error";
  timestamp: string;
};

// Decides who "Suspend user" acts on for a given case, and — when it cannot —
// why. A `reports` document for a feed post never stores the post's author
// uid, so that case only becomes suspendable once live-data.ts has resolved
// `authorUid` server-side (see src/lib/admin/live-data.ts#getLiveExceptionCases).
function suspensionTarget(
  item: ExceptionCase,
): { uid: string; reason: null } | { uid: null; reason: string } {
  if (item.targetType === "user" && item.targetId) {
    return { uid: item.targetId, reason: null };
  }

  if (item.type === "reported-feed-post") {
    if (item.authorUid) {
      return { uid: item.authorUid, reason: null };
    }

    return {
      uid: null,
      reason:
        "Suspend unavailable — the reported post's author could not be resolved. The post may already be gone with no recorded removal author.",
    };
  }

  return {
    uid: null,
    reason:
      "Suspend user is only available for reported users, or reported feed posts with a resolvable author.",
  };
}

export function ExceptionQueue({ cases }: { cases: ExceptionCase[] }) {
  const router = useRouter();
  const [items, setItems] = useState<ExceptionCase[]>(cases);
  const [typeFilter, setTypeFilter] = useState<string>("all");
  const [severityFilter, setSeverityFilter] = useState<string>("all");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [pendingIds, setPendingIds] = useState<Set<string>>(new Set());
  const [noteDrafts, setNoteDrafts] = useState<Record<string, string>>({});
  const [noteErrors, setNoteErrors] = useState<Record<string, string | null>>(
    {},
  );
  // Keyed by case id rather than reset from `cases`, so a router.refresh()
  // (which passes fresh server data and re-syncs `items` below) does not
  // wipe out the outcome history the admin just produced.
  const [outcomes, setOutcomes] = useState<Record<string, CaseOutcome[]>>({});
  const [removePostState, setRemovePostState] = useState<
    Record<string, RemovePostState>
  >({});
  // Outcome ids only need to be unique within a render session; a ref counter
  // (rather than Date.now()/Math.random()) keeps recordOutcome() from
  // calling an impure function.
  const outcomeSeqRef = useRef(0);

  // Live mode: after router.refresh() the server passes fresh report data
  // (including any resolved authorUid / duplicateReportCount); re-sync local
  // items. Mock props are stable, so this only ever fires once in mock mode.
  const [prevCases, setPrevCases] = useState(cases);
  if (prevCases !== cases) {
    setPrevCases(cases);
    setItems(cases);
  }

  const filtered = useMemo(
    () =>
      items.filter(
        (item) =>
          (typeFilter === "all" || item.type === typeFilter) &&
          (severityFilter === "all" || item.severity === severityFilter) &&
          (statusFilter === "all" || item.status === statusFilter),
      ),
    [items, typeFilter, severityFilter, statusFilter],
  );

  function isPending(itemId: string): boolean {
    return pendingIds.has(itemId);
  }

  function setPending(itemId: string, pending: boolean) {
    setPendingIds((prev) => {
      const next = new Set(prev);
      if (pending) {
        next.add(itemId);
      } else {
        next.delete(itemId);
      }
      return next;
    });
  }

  function recordOutcome(
    itemId: string,
    label: string,
    message: string,
    tone: "success" | "error",
  ) {
    outcomeSeqRef.current += 1;
    const entry: CaseOutcome = {
      id: `${itemId}-${outcomeSeqRef.current}`,
      label,
      message,
      tone,
      timestamp: new Date().toISOString(),
    };
    setOutcomes((prev) => ({
      ...prev,
      [itemId]: [...(prev[itemId] ?? []), entry],
    }));
  }

  // Both remaining callers are terminal actions that require a note, so the
  // note requirement is unconditional here rather than a parameter — Escalate
  // was the only caller that passed false.
  function runResolutionAction(
    item: ExceptionCase,
    label: string,
    nextStatus: ExceptionStatus,
  ) {
    const trimmedNote = (noteDrafts[item.id] ?? "").trim();

    if (!trimmedNote) {
      setNoteErrors((prev) => ({
        ...prev,
        [item.id]: "A note is required before resolving or dismissing this case.",
      }));
      return;
    }

    setNoteErrors((prev) => ({ ...prev, [item.id]: null }));
    setActionError(null);
    setPending(item.id, true);

    void (async () => {
      const result = await resolveReportAction(
        item.id,
        nextStatus,
        trimmedNote || undefined,
      );

      setPending(item.id, false);

      if (!result.ok) {
        setActionError(result.error);
        recordOutcome(item.id, label, result.error, "error");
        return;
      }

      setItems((prev) =>
        prev.map((current) =>
          current.id === item.id ? { ...current, status: nextStatus } : current,
        ),
      );
      recordOutcome(
        item.id,
        label,
        result.live
          ? `${label} recorded at ${formatDateTime(new Date().toISOString())}.`
          : `${label} recorded locally — no backend configured.`,
        "success",
      );

      if (result.live) {
        router.refresh();
      }
    })();
  }

  function suspendUser(item: ExceptionCase) {
    const target = suspensionTarget(item);

    if (!target.uid) {
      return;
    }

    const uid = target.uid;
    setActionError(null);
    setPending(item.id, true);

    void (async () => {
      const result = await setUserAccountStatusAction(uid, "suspended");

      setPending(item.id, false);

      if (!result.ok) {
        setActionError(result.error);
        recordOutcome(item.id, "Suspend user", result.error, "error");
        return;
      }

      recordOutcome(
        item.id,
        "Suspend user",
        result.live
          ? `User ${uid} suspended.`
          : "Suspend recorded locally — no backend configured.",
        "success",
      );

      if (result.live) {
        router.refresh();
      }
    })();
  }

  // Mirrors the recalc() polling idiom in LeaderboardOversight.tsx: write the
  // command, then poll getModerationCommandStatus() for the terminal state
  // (status "completed" | "failed") the moderationCommandCreated trigger
  // writes back, bounded to maxPollAttempts so this never polls forever.
  async function removePost(item: ExceptionCase) {
    if (!item.targetId) {
      return;
    }

    setActionError(null);
    setRemovePostState((prev) => ({
      ...prev,
      [item.id]: { kind: "requesting" },
    }));

    const requestResult = await requestFeedPostRemoval(item.targetId);

    if (!requestResult.ok) {
      setRemovePostState((prev) => ({ ...prev, [item.id]: { kind: "idle" } }));
      recordOutcome(item.id, "Remove post", requestResult.error, "error");
      return;
    }

    if (!requestResult.live) {
      setRemovePostState((prev) => ({ ...prev, [item.id]: { kind: "idle" } }));
      recordOutcome(
        item.id,
        "Remove post",
        "Removal recorded locally — no backend configured.",
        "success",
      );
      return;
    }

    const { commandId } = requestResult;
    setRemovePostState((prev) => ({
      ...prev,
      [item.id]: { kind: "polling", attempt: 0 },
    }));

    for (const attempt of pollAttempts) {
      await sleep(pollIntervalMs);
      const statusResult = await getModerationCommandStatus(commandId);

      if (!statusResult.ok) {
        setRemovePostState((prev) => ({ ...prev, [item.id]: { kind: "idle" } }));
        recordOutcome(item.id, "Remove post", statusResult.error, "error");
        return;
      }

      const command = statusResult.command;

      if (command === null || command.status === "pending") {
        setRemovePostState((prev) => ({
          ...prev,
          [item.id]: { kind: "polling", attempt },
        }));
        continue;
      }

      if (command.status === "completed") {
        setRemovePostState((prev) => ({ ...prev, [item.id]: { kind: "completed" } }));
        recordOutcome(item.id, "Remove post", "Post removed.", "success");
        router.refresh();
        return;
      }

      const reason = command.error ?? "Removal failed for an unknown reason.";
      setRemovePostState((prev) => ({ ...prev, [item.id]: { kind: "idle" } }));
      recordOutcome(item.id, "Remove post", reason, "error");
      return;
    }

    setRemovePostState((prev) => ({ ...prev, [item.id]: { kind: "timed-out" } }));
    recordOutcome(
      item.id,
      "Remove post",
      "Timed out waiting for the removal to complete. Check back shortly.",
      "error",
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <label className="flex flex-col gap-1">
          <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
            Type
          </span>
          <select
            value={typeFilter}
            onChange={(event) => setTypeFilter(event.target.value)}
            className={selectClass}
          >
            <option value="all">All types</option>
            {EXCEPTION_TYPE_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
            Severity
          </span>
          <select
            value={severityFilter}
            onChange={(event) => setSeverityFilter(event.target.value)}
            className={selectClass}
          >
            <option value="all">All severities</option>
            {SEVERITIES.map((value) => (
              <option key={value} value={value} className="capitalize">
                {value}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
            Status
          </span>
          <select
            value={statusFilter}
            onChange={(event) => setStatusFilter(event.target.value)}
            className={selectClass}
          >
            <option value="all">All statuses</option>
            {STATUSES.map((value) => (
              <option key={value} value={value} className="capitalize">
                {value}
              </option>
            ))}
          </select>
        </label>
        <p className="ml-auto self-center text-sm text-muted">
          {filtered.length} of {items.length} cases
        </p>
      </div>

      {actionError ? (
        <div
          role="alert"
          className="rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm font-semibold text-[#b42318]"
        >
          {actionError}
        </div>
      ) : null}

      {filtered.length === 0 ? (
        <EmptyState
          title="No cases match these filters"
          description="Try widening the type, severity, or status filters."
        />
      ) : (
        <ul className="space-y-3">
          {filtered.map((item) => {
            const expanded = expandedId === item.id;
            const pending = isPending(item.id);
            const removeState = removePostState[item.id] ?? { kind: "idle" };
            const removeBusy =
              removeState.kind === "requesting" || removeState.kind === "polling";
            const suspension = suspensionTarget(item);
            const itemOutcomes = outcomes[item.id] ?? [];
            const noteError = noteErrors[item.id] ?? null;

            return (
              <li
                key={item.id}
                className="overflow-hidden rounded-lg border border-border bg-white shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)]"
              >
                <button
                  type="button"
                  onClick={() =>
                    setExpandedId((current) =>
                      current === item.id ? null : item.id,
                    )
                  }
                  aria-expanded={expanded}
                  className="flex w-full flex-col gap-3 px-4 py-4 text-left transition-colors duration-150 hover:bg-brand-soft/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-brand/25 sm:px-5"
                >
                  <div className="flex flex-wrap items-center gap-2">
                    <Chip tone="brand">{exceptionTypeLabel(item.type)}</Chip>
                    <SeverityBadge severity={item.severity} />
                    <WorkflowStatusBadge status={item.status} />
                    {item.duplicateReportCount ? (
                      <Chip tone="accent">
                        {item.duplicateReportCount} other report
                        {item.duplicateReportCount === 1 ? "" : "s"} on this
                        target
                      </Chip>
                    ) : null}
                    <span className="ml-auto text-xs text-muted">
                      {formatDateTime(item.createdAt)}
                    </span>
                  </div>
                  <div>
                    <p className="text-sm font-bold text-brand">
                      {item.summary}
                    </p>
                    <p className="mt-0.5 text-xs text-muted">
                      {item.subjectLabel} &middot; Source:{" "}
                      {exceptionSourceLabel(item.source)}
                    </p>
                  </div>
                </button>

                {expanded ? (
                  <div className="border-t border-border bg-brand-soft/25 px-4 py-4 sm:px-5">
                    {/*
                      No "Sanitized" chip and no "Reason:" chip here. The first
                      was hardcoded true for every case (mapReport() in
                      live-data.ts) AND repeated verbatim as a detail card, so
                      it carried no information; the second restated the raw
                      reason string that the collapsed header's summary already
                      shows as "Report: <reason>".
                    */}
                    <dl className="grid gap-2 sm:grid-cols-2">
                      {item.details.map((detail) => (
                        <div
                          key={detail}
                          className="rounded-lg border border-border bg-white px-3 py-2 text-sm text-foreground"
                        >
                          {detail}
                        </div>
                      ))}
                    </dl>

                    <div className="mt-4">
                      <label className="flex flex-col gap-1">
                        <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
                          Note (required to resolve or dismiss)
                        </span>
                        <textarea
                          value={noteDrafts[item.id] ?? ""}
                          onChange={(event) => {
                            const value = event.target.value;
                            setNoteDrafts((prev) => ({
                              ...prev,
                              [item.id]: value,
                            }));
                            if (value.trim()) {
                              setNoteErrors((prev) => ({
                                ...prev,
                                [item.id]: null,
                              }));
                            }
                          }}
                          placeholder="Explain what was found and why this action is being taken."
                          className={noteClass}
                          disabled={pending}
                        />
                      </label>
                      {noteError ? (
                        <p className="mt-1 text-xs font-semibold text-[#b42318]">
                          {noteError}
                        </p>
                      ) : null}
                    </div>

                    <div className="mt-4 flex flex-wrap gap-2">
                      <button
                        type="button"
                        className={btnPrimary}
                        disabled={pending}
                        onClick={() =>
                          runResolutionAction(item, "Resolve", "resolved")
                        }
                      >
                        Resolve
                      </button>
                      <button
                        type="button"
                        className={btnSecondary}
                        disabled={pending}
                        onClick={() =>
                          runResolutionAction(item, "Dismiss", "dismissed")
                        }
                      >
                        Dismiss
                      </button>
                      {/*
                        No "Escalate" button. It escalated nothing: `reports`
                        carries only an onDocumentCreated trigger
                        (functions/src/moderation/reportAutomation.ts), so
                        setting resolutionStatus to "reviewing" notified
                        nobody, assigned nobody, and moved the case to no
                        other queue. It also dropped the case out of the
                        Overview's unresolved count while the backend stale
                        sweep kept aging it, and — being the one action that
                        did not require a note — could null out a note a
                        prior Resolve had recorded.
                      */}
                      {item.type === "reported-feed-post" && item.targetId ? (
                        <button
                          type="button"
                          className={btnDanger}
                          disabled={removeBusy || removeState.kind === "completed"}
                          onClick={() => void removePost(item)}
                        >
                          {removeBusy
                            ? "Removing…"
                            : removeState.kind === "completed"
                              ? "Post removed"
                              : "Remove post"}
                        </button>
                      ) : null}
                      <button
                        type="button"
                        className={btnDanger}
                        disabled={pending || !suspension.uid}
                        title={suspension.reason ?? undefined}
                        onClick={() => suspendUser(item)}
                      >
                        Suspend user
                      </button>
                    </div>

                    {suspension.reason ? (
                      <p className="mt-2 text-xs text-muted">
                        {suspension.reason}
                      </p>
                    ) : null}

                    {removeState.kind === "polling" ? (
                      <p className="mt-2 text-xs text-muted">
                        Removal running — checking status ({removeState.attempt}/
                        {maxPollAttempts})…
                      </p>
                    ) : removeState.kind === "timed-out" ? (
                      <p className="mt-2 text-xs font-semibold text-[#b42318]">
                        Timed out waiting for the removal to complete. Check
                        back shortly.
                      </p>
                    ) : null}

                    {/*
                      The Collapse button that used to sit here rendered only
                      while this case had no outcomes, so it vanished the
                      moment an admin acted — the one point at which a long
                      card most needs collapsing. The header row is a toggle
                      already, so the button is gone rather than duplicated.
                    */}
                    {itemOutcomes.length > 0 ? (
                      <div className="mt-4 rounded-lg border border-border bg-white px-3 py-3">
                        <p className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
                          Outcome
                        </p>
                        <ul className="mt-2 space-y-1">
                          {itemOutcomes.map((entry) => (
                            <li
                              key={entry.id}
                              className={`text-sm ${
                                entry.tone === "error"
                                  ? "font-semibold text-[#b42318]"
                                  : "text-foreground"
                              }`}
                            >
                              {entry.label} — {entry.message} (
                              {formatDateTime(entry.timestamp)})
                            </li>
                          ))}
                        </ul>
                      </div>
                    ) : null}
                  </div>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
