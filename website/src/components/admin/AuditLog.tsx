"use client";

import { useMemo, useState } from "react";
import { inputBase } from "@/components/admin/button-styles";
import { Chip, EmptyState } from "@/components/admin/primitives";
import { Pager, usePagination } from "@/components/admin/pagination";
import { formatDateTime } from "@/lib/admin/format";
import type { AuditCategory, AuditEntry } from "@/lib/admin/types";

const CATEGORY_LABELS: Record<AuditCategory, string> = {
  "admin-action": "Admin action",
  "role-change": "Role change",
  "subscription-change": "Subscription change",
  "rule-activation": "Rule activation",
  "backend-job": "Backend job",
};

const selectClass = `${inputBase} w-auto min-w-[11rem] cursor-pointer pr-8`;

export function AuditLog({ entries }: { entries: AuditEntry[] }) {
  const [categoryFilter, setCategoryFilter] = useState("all");
  const [actorFilter, setActorFilter] = useState("all");

  const actors = useMemo(
    () => Array.from(new Set(entries.map((entry) => entry.actor))),
    [entries],
  );

  const sorted = useMemo(
    () =>
      [...entries].sort(
        (a, b) =>
          new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime(),
      ),
    [entries],
  );

  const filtered = useMemo(
    () =>
      sorted.filter(
        (entry) =>
          (categoryFilter === "all" || entry.category === categoryFilter) &&
          (actorFilter === "all" || entry.actor === actorFilter),
      ),
    [sorted, categoryFilter, actorFilter],
  );

  // Changing either filter re-derives `filtered`, which resets the pager to
  // the first page of the new result set.
  const pagination = usePagination(filtered);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <label className="flex flex-col gap-1">
          <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
            Category
          </span>
          <select
            value={categoryFilter}
            onChange={(event) => setCategoryFilter(event.target.value)}
            className={selectClass}
          >
            <option value="all">All categories</option>
            {(Object.keys(CATEGORY_LABELS) as AuditCategory[]).map((value) => (
              <option key={value} value={value}>
                {CATEGORY_LABELS[value]}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
            Actor
          </span>
          <select
            value={actorFilter}
            onChange={(event) => setActorFilter(event.target.value)}
            className={selectClass}
          >
            <option value="all">All actors</option>
            {actors.map((actor) => (
              <option key={actor} value={actor}>
                {actor}
              </option>
            ))}
          </select>
        </label>
        <p className="ml-auto self-center text-sm text-muted">
          {filtered.length} of {entries.length} entries
        </p>
      </div>

      {filtered.length === 0 ? (
        <EmptyState title="No entries match these filters" />
      ) : (
        <ol className="space-y-2">
          {pagination.visible.map((entry) => (
            <li
              key={entry.id}
              className="flex flex-col gap-2 rounded-lg border border-border bg-white px-4 py-3 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:flex-row sm:items-center"
            >
              <div className="flex flex-wrap items-center gap-2">
                <Chip tone={entry.actor === "system" ? "muted" : "brand"}>
                  {entry.actor}
                </Chip>
                <Chip tone="neutral">{CATEGORY_LABELS[entry.category]}</Chip>
              </div>
              <p className="min-w-0 text-sm">
                <span className="text-muted">{entry.action}</span>{" "}
                <span className="font-semibold text-foreground">
                  {entry.target}
                </span>
              </p>
              <span className="text-xs text-muted sm:ml-auto sm:whitespace-nowrap">
                {formatDateTime(entry.timestamp)}
              </span>
            </li>
          ))}
        </ol>
      )}

      <Pager pagination={pagination} label="Audit log pages" />
    </div>
  );
}
