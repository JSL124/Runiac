"use client";

import { useRouter } from "next/navigation";
import { Fragment, useMemo, useState, useTransition } from "react";
import { btnSecondary, inputBase } from "@/components/admin/button-styles";
import {
  Chip,
  EmptyState,
  SeverityBadge,
  TableWrap,
  WorkflowStatusBadge,
} from "@/components/admin/primitives";
import { triageErrorGroup } from "@/lib/actions/admin";
import { formatDateTime, formatNumber } from "@/lib/admin/format";
import type { ErrorGroup, ErrorSource, ErrorStatus } from "@/lib/admin/types";

const STATUS_OPTIONS: ErrorStatus[] = [
  "new",
  "investigating",
  "resolved",
  "ignored",
];

// "App" / "Backend" are the console-facing labels for the stored
// "mobile" / "functions" source values (see ErrorSource in
// src/lib/admin/types.ts).
const SOURCE_OPTIONS: { value: ErrorSource; label: string }[] = [
  { value: "mobile", label: "App" },
  { value: "functions", label: "Backend" },
];

const selectClass = `${inputBase} w-auto min-w-[9rem] cursor-pointer pr-8`;

export function ErrorMonitoring({ groups }: { groups: ErrorGroup[] }) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [rows, setRows] = useState<ErrorGroup[]>(groups);
  const [statusFilter, setStatusFilter] = useState("all");
  const [sourceFilter, setSourceFilter] = useState("all");
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  // Live mode: after router.refresh() the server passes fresh error-group
  // data; re-sync local rows. Mock props are stable, so local state persists.
  const [prevGroups, setPrevGroups] = useState(groups);
  if (prevGroups !== groups) {
    setPrevGroups(groups);
    setRows(groups);
  }

  const filtered = useMemo(
    () =>
      rows.filter(
        (row) =>
          (statusFilter === "all" || row.status === statusFilter) &&
          (sourceFilter === "all" || row.source === sourceFilter),
      ),
    [rows, statusFilter, sourceFilter],
  );

  function changeStatus(id: string, status: ErrorStatus) {
    const previousStatus = rows.find((row) => row.id === id)?.status;
    if (previousStatus === undefined || previousStatus === status) {
      return;
    }

    setActionError(null);
    setRows((prev) =>
      prev.map((row) => (row.id === id ? { ...row, status } : row)),
    );

    startTransition(async () => {
      const result = await triageErrorGroup(id, status);

      if (!result.ok) {
        setActionError(result.error);
        setRows((prev) =>
          prev.map((row) =>
            row.id === id ? { ...row, status: previousStatus } : row,
          ),
        );
        return;
      }

      if (result.live) {
        router.refresh();
      }
    });
  }

  return (
    <div className="space-y-4">
      {actionError ? (
        <div
          role="alert"
          className="rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm font-semibold text-[#b42318]"
        >
          {actionError}
        </div>
      ) : null}

      <div className="flex flex-wrap items-end gap-3">
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
            {STATUS_OPTIONS.map((value) => (
              <option key={value} value={value} className="capitalize">
                {value}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
            Source
          </span>
          <select
            value={sourceFilter}
            onChange={(event) => setSourceFilter(event.target.value)}
            className={selectClass}
          >
            <option value="all">All sources</option>
            {SOURCE_OPTIONS.map(({ value, label }) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <p className="ml-auto self-center text-sm text-muted">
          {filtered.length} of {rows.length} error groups
        </p>
      </div>

      {filtered.length === 0 ? (
        <EmptyState
          title={
            rows.length === 0
              ? "No app errors reported yet"
              : "No error groups match these filters"
          }
          description={
            rows.length === 0
              ? "Nothing has been reported by the mobile app or Cloud Functions in this environment yet."
              : "Try a different status or source, or select \"All statuses\" and \"All sources\"."
          }
        />
      ) : (
      <div className="rounded-lg border border-border bg-white shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)]">
        <TableWrap>
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-border text-left text-[0.7rem] uppercase tracking-[0.12em] text-muted">
                <th className="py-3 pr-4 font-bold">Error group</th>
                <th className="py-3 pr-4 font-bold">Version / Runtime</th>
                <th className="py-3 pr-4 font-bold text-right">Occurrences</th>
                <th className="py-3 pr-4 font-bold text-right">Users</th>
                <th className="py-3 pr-4 font-bold">Severity</th>
                <th className="py-3 pr-2 font-bold">Status</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((group) => {
                const expanded = expandedId === group.id;

                return (
                  <Fragment key={group.id}>
                    <tr className="border-b border-border last:border-0 align-top">
                      <td className="py-3 pr-4">
                        <button
                          type="button"
                          onClick={() =>
                            setExpandedId((current) =>
                              current === group.id ? null : group.id,
                            )
                          }
                          aria-expanded={expanded}
                          className="text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/25"
                        >
                          <span className="font-bold text-brand hover:underline">
                            {group.title}
                          </span>
                          <span className="mt-0.5 block text-xs text-muted">
                            {group.screen}
                          </span>
                        </button>
                      </td>
                      <td className="py-3 pr-4 whitespace-nowrap text-muted">
                        {group.appVersion}
                        <span className="block text-xs">{group.os}</span>
                      </td>
                      <td className="py-3 pr-4 text-right font-mono tabular-nums text-foreground">
                        {formatNumber(group.occurrences)}
                      </td>
                      <td className="py-3 pr-4 text-right font-mono tabular-nums text-foreground">
                        {formatNumber(group.affectedUsers)}
                      </td>
                      <td className="py-3 pr-4">
                        <SeverityBadge severity={group.severity} />
                      </td>
                      <td className="py-3 pr-2">
                        <WorkflowStatusBadge status={group.status} />
                      </td>
                    </tr>
                    {expanded ? (
                      <tr className="border-b border-border last:border-0">
                        <td colSpan={6} className="bg-brand-soft/25 px-3 py-4">
                          <div className="flex flex-wrap items-center gap-2">
                            {group.sanitized ? (
                              <Chip tone="muted">
                                Sanitized report &mdash; no location,
                                credentials, or profile data
                              </Chip>
                            ) : null}
                          </div>
                          <p className="mt-3 rounded-lg border border-border bg-white px-3 py-2 font-mono text-xs text-foreground">
                            {group.stackSummary}
                          </p>
                          <p className="mt-2 text-xs text-muted">
                            First seen {formatDateTime(group.firstSeenAt)}
                            {" · "}Last seen {formatDateTime(group.lastSeenAt)}
                          </p>
                          <label className="mt-3 flex flex-wrap items-end gap-2">
                            <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
                              Change status
                            </span>
                            <select
                              value={group.status}
                              disabled={isPending}
                              onChange={(event) =>
                                changeStatus(
                                  group.id,
                                  event.target.value as ErrorStatus,
                                )
                              }
                              className={selectClass}
                            >
                              {STATUS_OPTIONS.map((value) => (
                                <option
                                  key={value}
                                  value={value}
                                  className="capitalize"
                                >
                                  {value}
                                </option>
                              ))}
                            </select>
                            <button
                              type="button"
                              className={btnSecondary}
                              disabled={isPending}
                              onClick={() => setExpandedId(null)}
                            >
                              Collapse
                            </button>
                          </label>
                        </td>
                      </tr>
                    ) : null}
                  </Fragment>
                );
              })}
            </tbody>
          </table>
        </TableWrap>
      </div>
      )}
    </div>
  );
}
