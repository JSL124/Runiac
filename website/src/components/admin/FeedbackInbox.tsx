"use client";

import { useRouter } from "next/navigation";
import { useMemo, useState, useTransition } from "react";
import { btnPrimary, btnSecondary, inputBase } from "@/components/admin/button-styles";
import {
  Chip,
  SeverityBadge,
  WorkflowStatusBadge,
} from "@/components/admin/primitives";
import { closeFeedback, triageFeedback } from "@/lib/actions/admin";
import {
  feedbackCategoryLabel,
  formatDateTime,
} from "@/lib/admin/format";
import type {
  FeedbackCategory,
  FeedbackItem,
  FeedbackStatus,
} from "@/lib/admin/types";

type LocalFeedback = FeedbackItem;

const CATEGORY_ORDER: FeedbackCategory[] = [
  "bug",
  "plan issue",
  "billing",
  "abuse",
  "other",
];

// resolved/dismissed are terminal: "Advance status" only cycles the open
// states below, and a resolved/dismissed item instead surfaces "Reopen"
// (back to "new") so closed feedback never silently cycles back on its own.
const TERMINAL_STATUSES: ReadonlySet<FeedbackStatus> = new Set([
  "resolved",
  "dismissed",
]);

const NEXT_STATUS: Partial<Record<FeedbackStatus, FeedbackStatus>> = {
  new: "responded",
  responded: "resolved",
  escalated: "resolved",
};

function nextStatusFor(status: FeedbackStatus): FeedbackStatus {
  if (TERMINAL_STATUSES.has(status)) {
    return "new";
  }
  return NEXT_STATUS[status] ?? status;
}

export function FeedbackInbox({ items }: { items: FeedbackItem[] }) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [rows, setRows] = useState<LocalFeedback[]>(items);
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [actionError, setActionError] = useState<string | null>(null);
  const [showClosed, setShowClosed] = useState(false);

  // Live mode: after router.refresh() the server passes fresh feedback data;
  // re-sync local rows. Mock props are stable, so local state persists.
  const [prevItems, setPrevItems] = useState(items);
  if (prevItems !== items) {
    setPrevItems(items);
    setRows(items);
    setDrafts({});
  }

  const closedCount = useMemo(
    () => rows.filter((row) => row.closed).length,
    [rows],
  );

  const grouped = useMemo(() => {
    const visible = showClosed ? rows : rows.filter((row) => !row.closed);
    return CATEGORY_ORDER.map((category) => ({
      category,
      entries: visible.filter((row) => row.category === category),
    })).filter((group) => group.entries.length > 0);
  }, [rows, showClosed]);

  function setNoteDraft(id: string, note: string) {
    setDrafts((prev) => ({ ...prev, [id]: note }));
  }

  function clearDraft(id: string) {
    setDrafts((prev) => {
      const next = { ...prev };
      delete next[id];
      return next;
    });
  }

  function saveNote(row: LocalFeedback) {
    const note = drafts[row.id];
    if (note === undefined || note === row.note) {
      return;
    }

    setActionError(null);
    startTransition(async () => {
      const result = await triageFeedback(row.id, row.status, note);

      if (!result.ok) {
        setActionError(result.error);
        return;
      }

      setRows((prev) =>
        prev.map((item) => (item.id === row.id ? { ...item, note } : item)),
      );
      clearDraft(row.id);

      if (result.live) {
        router.refresh();
      }
    });
  }

  function advanceStatus(row: LocalFeedback) {
    const nextStatus = nextStatusFor(row.status);
    const pendingNote = drafts[row.id];

    setActionError(null);
    startTransition(async () => {
      const result = await triageFeedback(row.id, nextStatus, pendingNote);

      if (!result.ok) {
        setActionError(result.error);
        return;
      }

      setRows((prev) =>
        prev.map((item) =>
          item.id === row.id
            ? {
                ...item,
                status: nextStatus,
                note: pendingNote ?? item.note,
              }
            : item,
        ),
      );
      clearDraft(row.id);

      if (result.live) {
        router.refresh();
      }
    });
  }

  function setClosed(row: LocalFeedback, closed: boolean) {
    setActionError(null);
    startTransition(async () => {
      const result = await closeFeedback(row.id, closed);

      if (!result.ok) {
        setActionError(result.error);
        return;
      }

      setRows((prev) =>
        prev.map((item) => (item.id === row.id ? { ...item, closed } : item)),
      );

      if (result.live) {
        router.refresh();
      }
    });
  }

  return (
    <div className="space-y-6">
      <label className="flex w-fit items-center gap-2 text-sm font-semibold text-muted">
        <input
          type="checkbox"
          checked={showClosed}
          onChange={(event) => setShowClosed(event.target.checked)}
        />
        Show closed ({closedCount})
      </label>

      {actionError ? (
        <div
          role="alert"
          className="rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm font-semibold text-[#b42318]"
        >
          {actionError}
        </div>
      ) : null}

      {grouped.map((group) => (
        <section key={group.category} className="space-y-3">
          <div className="flex items-center gap-2">
            <h2 className="text-lg font-bold text-brand">
              {feedbackCategoryLabel(group.category)}
            </h2>
            <Chip tone="muted">{group.entries.length}</Chip>
          </div>
          <ul className="space-y-3">
            {group.entries.map((entry) => {
              const draft = drafts[entry.id];
              const noteDirty = draft !== undefined && draft !== entry.note;
              const isTerminal = TERMINAL_STATUSES.has(entry.status);

              return (
                <li
                  key={entry.id}
                  className="rounded-lg border border-border bg-white p-4 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)]"
                >
                  <div className="flex flex-wrap items-center gap-2">
                    <SeverityBadge severity={entry.severity} />
                    <WorkflowStatusBadge status={entry.status} />
                    {entry.closed ? <Chip tone="muted">Closed</Chip> : null}
                    {entry.duplicateCount > 1 ? (
                      <Chip tone="accent">
                        {entry.duplicateCount} similar
                      </Chip>
                    ) : null}
                    <span className="ml-auto text-xs text-muted">
                      {formatDateTime(entry.receivedAt)}
                    </span>
                  </div>
                  <p className="mt-2 text-sm font-bold text-brand">
                    {entry.summary}
                  </p>
                  <label className="mt-3 block">
                    <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
                      Admin note
                    </span>
                    <textarea
                      rows={2}
                      value={draft ?? entry.note}
                      placeholder="Add a note for this escalated item"
                      disabled={isPending}
                      onChange={(event) =>
                        setNoteDraft(entry.id, event.target.value)
                      }
                      className={`${inputBase} mt-1 h-auto py-2 leading-relaxed`}
                    />
                  </label>
                  <div className="mt-2 flex justify-end gap-2">
                    {noteDirty ? (
                      <button
                        type="button"
                        className={btnPrimary}
                        disabled={isPending}
                        onClick={() => saveNote(entry)}
                      >
                        Save note
                      </button>
                    ) : null}
                    <button
                      type="button"
                      className={btnSecondary}
                      disabled={isPending}
                      onClick={() => advanceStatus(entry)}
                    >
                      {isTerminal ? "Reopen" : "Advance status"}
                    </button>
                    <button
                      type="button"
                      className={btnSecondary}
                      disabled={isPending}
                      onClick={() => setClosed(entry, !entry.closed)}
                    >
                      {entry.closed ? "Restore" : "Close"}
                    </button>
                  </div>
                </li>
              );
            })}
          </ul>
        </section>
      ))}
    </div>
  );
}
