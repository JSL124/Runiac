"use client";

// Subscribers tab of the admin "Newsletter" console
// (src/app/admin/newsletter). List + status filter + text search + status
// counts + a delete action for privacy/GDPR requests, behind a confirm step
// (mirrors DocumentDeleteButton.tsx's window.confirm() guard).
//
// There is deliberately no "change status" control anywhere on this tab: the
// console can remove a subscriber but can never promote one to "confirmed" —
// see src/lib/actions/newsletter.ts for why.

import { useRouter } from "next/navigation";
import { useMemo, useState, useTransition } from "react";
import { btnDanger, inputBase } from "@/components/admin/button-styles";
import {
  Chip,
  EmptyState,
  StatCard,
  TableWrap,
} from "@/components/admin/primitives";
import { deleteNewsletterSubscriber } from "@/lib/actions/newsletter";
import { formatDateTime } from "@/lib/admin/format";
import type {
  NewsletterSubscriber,
  NewsletterSubscriberStatus,
} from "@/lib/admin/types";

// "bounced" is deliberately absent. Nothing in the system ever assigns it:
// the Trigger Email extension records a failed send as `delivery.state =
// "ERROR"` on the `mail` document and no job feeds that back onto the
// subscriber, and a true asynchronous bounce is only ever seen by the SMTP
// relay, which has no webhook into this project. Offering the filter would
// promise a view that is permanently empty. The status stays in the type and
// in the read mapper so a document that somehow carries it still renders
// (see STATUS_CHIP_TONE below) rather than being coerced to "pending".
const STATUS_OPTIONS: { value: NewsletterSubscriberStatus | "all"; label: string }[] = [
  { value: "all", label: "All statuses" },
  { value: "pending", label: "Pending" },
  { value: "confirmed", label: "Confirmed" },
  { value: "unsubscribed", label: "Unsubscribed" },
];

const STATUS_CHIP_TONE: Record<
  NewsletterSubscriberStatus,
  "brand" | "accent" | "muted" | "neutral"
> = {
  pending: "accent",
  confirmed: "brand",
  unsubscribed: "muted",
  bounced: "neutral",
};

function StatusChip({ status }: { status: NewsletterSubscriberStatus }) {
  return <Chip tone={STATUS_CHIP_TONE[status]}>{status}</Chip>;
}

export function NewsletterSubscribers({
  subscribers,
}: {
  subscribers: NewsletterSubscriber[];
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [rows, setRows] = useState(subscribers);
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<NewsletterSubscriberStatus | "all">(
    "all",
  );
  const [actionError, setActionError] = useState<string | null>(null);

  // Live mode: after router.refresh() the server passes fresh subscriber
  // data; re-sync local rows. Mock props are stable, so local state persists.
  const [prevSubscribers, setPrevSubscribers] = useState(subscribers);
  if (prevSubscribers !== subscribers) {
    setPrevSubscribers(subscribers);
    setRows(subscribers);
  }

  // `bounced` is counted but has no StatCard, for the same reason it has no
  // filter option (see STATUS_OPTIONS): the backend never assigns it, so a
  // card would sit at a permanent 0. The tally entry has to stay — the record
  // is keyed by the full status union and `base[row.status] += 1` below would
  // otherwise blow up on a document that somehow carries it.
  const counts = useMemo(() => {
    const base: Record<NewsletterSubscriberStatus, number> = {
      pending: 0,
      confirmed: 0,
      unsubscribed: 0,
      bounced: 0,
    };
    for (const row of rows) {
      base[row.status] += 1;
    }
    return base;
  }, [rows]);

  const filtered = useMemo(() => {
    const trimmed = query.trim().toLowerCase();
    return rows.filter((row) => {
      if (statusFilter !== "all" && row.status !== statusFilter) {
        return false;
      }
      if (!trimmed) {
        return true;
      }
      return [row.emailLower, row.source].some((value) =>
        value.toLowerCase().includes(trimmed),
      );
    });
  }, [rows, query, statusFilter]);

  function handleDelete(row: NewsletterSubscriber) {
    const confirmed = window.confirm(
      `Delete subscriber "${row.emailLower}"? This permanently removes their record.`,
    );

    if (!confirmed) {
      return;
    }

    setActionError(null);
    startTransition(async () => {
      const result = await deleteNewsletterSubscriber(row.id);

      if (!result.ok) {
        setActionError(result.error);
        return;
      }

      setRows((prev) => prev.filter((item) => item.id !== row.id));

      if (result.live) {
        router.refresh();
      }
    });
  }

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <StatCard label="Pending" value={counts.pending} />
        <StatCard label="Confirmed" value={counts.confirmed} tone="accent" />
        <StatCard label="Unsubscribed" value={counts.unsubscribed} />
      </div>

      <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
        <label className="flex-1">
          <span className="sr-only">Search subscribers</span>
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search by email or source"
            className={inputBase}
          />
        </label>
        <label className="sm:w-56">
          <span className="sr-only">Filter by status</span>
          <select
            value={statusFilter}
            onChange={(event) =>
              setStatusFilter(event.target.value as NewsletterSubscriberStatus | "all")
            }
            className={inputBase}
          >
            {STATUS_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
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
          title="No subscribers match"
          description="Try a different search term or status filter."
        />
      ) : (
        <div className="rounded-lg border border-border bg-white shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)]">
          <TableWrap>
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-border text-left text-[0.7rem] uppercase tracking-[0.12em] text-muted">
                  <th className="py-3 pr-4 font-bold">Email</th>
                  <th className="py-3 pr-4 font-bold">Status</th>
                  <th className="py-3 pr-4 font-bold">Consent</th>
                  <th className="py-3 pr-4 font-bold">Confirmed</th>
                  <th className="py-3 pr-4 font-bold">Source</th>
                  <th className="py-3 pr-2 text-right font-bold">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((row) => (
                  <tr key={row.id} className="border-b border-border align-top last:border-0">
                    <td className="py-3 pr-4 font-semibold text-brand">{row.emailLower}</td>
                    <td className="py-3 pr-4">
                      <StatusChip status={row.status} />
                    </td>
                    <td className="py-3 pr-4 text-muted">
                      {row.consentAt ? formatDateTime(row.consentAt) : "—"}
                    </td>
                    <td className="py-3 pr-4 text-muted">
                      {row.confirmedAt ? formatDateTime(row.confirmedAt) : "—"}
                    </td>
                    <td className="py-3 pr-4 text-muted">{row.source}</td>
                    <td className="py-3 pr-2 text-right">
                      <button
                        type="button"
                        className={btnDanger}
                        disabled={isPending}
                        onClick={() => handleDelete(row)}
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        </div>
      )}
    </div>
  );
}
