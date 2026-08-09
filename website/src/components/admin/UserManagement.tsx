"use client";

import { useRouter } from "next/navigation";
import { Fragment, useMemo, useState, useTransition } from "react";
import {
  btnDanger,
  btnGhost,
  btnSecondary,
  inputBase,
} from "@/components/admin/button-styles";
import {
  changeUserRole as changeUserRoleAction,
  setUserAccountStatus as setUserAccountStatusAction,
} from "@/lib/actions/admin";
import type { AdminActionResult } from "@/lib/actions/admin";
import {
  Chip,
  EmptyState,
  InfoBanner,
  TableWrap,
} from "@/components/admin/primitives";
import { Pager, usePagination } from "@/components/admin/pagination";
import { UserOperationsPanel } from "@/components/admin/UserOperationsPanel";
import { UserProgressionPanel } from "@/components/admin/UserProgressionPanel";
import {
  ROLE_OPTIONS,
  formatDate,
  formatDateTime,
  formatNumber,
  roleLabel,
  subscriptionLabel,
} from "@/lib/admin/format";
import type {
  AdminActionLogEntry,
  AdminUser,
  UserRole,
} from "@/lib/admin/types";

type LocalUser = AdminUser;

function AccountStatusChip({ status }: { status: AdminUser["accountStatus"] }) {
  if (status === "active") {
    return <Chip tone="brand">Active</Chip>;
  }

  return (
    <span className="inline-flex items-center rounded-full border border-[#f0c2bc] bg-[#fdecea] px-2.5 py-0.5 text-xs font-bold text-[#b42318]">
      {status === "banned" ? "Banned" : "Suspended"}
    </span>
  );
}

export function UserManagement({
  users,
  history,
  query: appliedQuery,
  pageSize,
  canLoadMore,
  searchWindowLimited,
}: {
  users: AdminUser[];
  history: AdminActionLogEntry[];
  query: string;
  pageSize: number;
  canLoadMore: boolean;
  // The applied search was a substring match over a full scan window, so
  // accounts beyond it were never examined and the result is incomplete.
  searchWindowLimited: boolean;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [rows, setRows] = useState<LocalUser[]>(users);
  const [query, setQuery] = useState(appliedQuery);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  // Staged role change for the expanded row: the chosen role plus its
  // mandatory reason, held until the admin explicitly confirms.
  const [roleDraft, setRoleDraft] = useState<{
    role?: UserRole;
    reason?: string;
  }>({});
  const [log, setLog] = useState<{ message: string; live: boolean }[]>([]);
  const [actionError, setActionError] = useState<string | null>(null);
  // True once any action has returned `live: false` — Firebase credentials
  // are not configured, so writes are session-only and never reach
  // Firestore, even though the UI otherwise behaves as if they succeeded.
  const [notPersisting, setNotPersisting] = useState(false);

  // Live mode: router.refresh() re-renders the server page with fresh
  // Firestore data; re-sync local rows when new props arrive. In mock mode the
  // props are stable, so local state persists untouched.
  const [prevUsers, setPrevUsers] = useState(users);
  // Counts genuine list replacements, so the pager can distinguish them from
  // the optimistic in-place row edits that also rebuild `filtered`.
  const [listVersion, setListVersion] = useState(0);
  if (prevUsers !== users) {
    setPrevUsers(users);
    setRows(users);
    setExpandedId(null);
    setListVersion((version) => version + 1);
  }

  // `appliedQuery` was already applied server-side against the scanned window.
  // This narrows the same rows further while the admin is still typing, so the
  // table stays responsive between submits. It is a refinement of the server
  // result, never a substitute for it: rows outside the scan window were never
  // fetched, which is what `searchWindowLimited` warns about.
  const filtered = useMemo(() => {
    const trimmed = query.trim().toLowerCase();

    if (!trimmed || trimmed === appliedQuery.trim().toLowerCase()) {
      return rows;
    }

    return rows.filter((user) =>
      [user.displayName, user.nickname, user.email, user.region]
        .join(" ")
        .toLowerCase()
        .includes(trimmed),
    );
  }, [rows, query, appliedQuery]);

  // The table shows one page of rows at a time; the rest are reachable through
  // the chevrons. "Load more" is what widens the server window when there are
  // more users than were fetched. Typing in the search box re-derives
  // `filtered`, which returns the pager to the first page of the new result
  // set rather than leaving it past the end.
  // `filtered` is also rebuilt by the optimistic `setRows` after a suspend,
  // restore or role change. Those edit rows in place; they do not produce a
  // different result set, so paging must survive them. Reset only on what
  // genuinely replaces the list: a new server page (tracked by `listVersion`,
  // bumped where `users` is adopted above), or a changed search.
  const tablePages = usePagination(filtered, {
    resetKey: `${listVersion}|${query}|${appliedQuery}`,
    // An expanded row belongs to the page it was opened on; leaving it open
    // across a page change would attach its panels to a different user.
    onPageChange: () => {
      setExpandedId(null);
      setRoleDraft({});
    },
  });
  const visible = tablePages.visible;

  // The persisted history is unbounded, so it pages under the same rule as the
  // table. Session entries stay pinned above it — they are few, and they are
  // the feedback for the action the admin just took.
  const historyPages = usePagination(history);

  // Search and page size live in the URL so a reload, a shared link, and
  // router.refresh() after a mutation all reproduce the same view.
  function navigate(nextQuery: string, nextPageSize: number) {
    const params = new URLSearchParams();

    if (nextQuery.trim()) {
      params.set("q", nextQuery.trim());
    }

    if (nextPageSize !== pageSize || params.has("q")) {
      params.set("limit", String(nextPageSize));
    }

    const search = params.toString();
    startTransition(() => {
      router.push(search ? `/admin/users?${search}` : "/admin/users");
    });
  }

  function appendLog(message: string, live: boolean) {
    setLog((prev) => [
      {
        message: `${message} at ${formatDateTime(new Date().toISOString())}`,
        live,
      },
      ...prev,
    ]);
    if (!live) {
      setNotPersisting(true);
    }
  }

  function toggleSuspension(user: LocalUser) {
    const nextStatus = user.accountStatus === "active" ? "suspended" : "active";
    setActionError(null);
    startTransition(async () => {
      const result = await setUserAccountStatusAction(user.uid, nextStatus);

      if (!result.ok) {
        setActionError(result.error);
        return;
      }

      // Optimistic local update in both modes for immediate feedback.
      setRows((prev) =>
        prev.map((row) =>
          row.id === user.id ? { ...row, accountStatus: nextStatus } : row,
        ),
      );
      appendLog(
        `${nextStatus === "suspended" ? "Suspended" : "Restored"} ${user.displayName}`,
        result.live,
      );

      if (result.live) {
        router.refresh();
      }
    });
  }

  // Granting platformAdmin hands over the entire governance surface, so the
  // select only stages the intent — it never mutates on change. The admin has
  // to supply a reason and confirm, which is the same bar suspension and
  // subscription overrides already meet.
  function changeRole(user: LocalUser, role: UserRole, reason: string) {
    setActionError(null);
    startTransition(async () => {
      const result = await changeUserRoleAction(user.uid, role, reason);

      if (!result.ok) {
        setActionError(result.error);
        return;
      }

      setRows((prev) =>
        prev.map((row) =>
          row.id === user.id ? { ...row, userRole: role } : row,
        ),
      );
      appendLog(`Changed ${user.displayName} role to ${roleLabel(role)}`, result.live);
      setRoleDraft({});

      if (result.live) {
        router.refresh();
      }
    });
  }

  function handleProgressionSuccess(message: string, result: AdminActionResult) {
    if (!result.ok) {
      return;
    }

    appendLog(message, result.live);

    if (result.live) {
      router.refresh();
    }
  }

  return (
    <div className="space-y-6">
      <form
        className="flex flex-col gap-3 sm:flex-row sm:items-center"
        onSubmit={(event) => {
          event.preventDefault();
          navigate(query, pageSize);
        }}
      >
        <label className="w-full sm:max-w-sm">
          <span className="sr-only">Search users</span>
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search by name, nickname, region, or exact email / uid"
            className={inputBase}
          />
        </label>
        <button type="submit" className={btnSecondary} disabled={isPending}>
          {isPending ? "Searching..." : "Search"}
        </button>
        {appliedQuery ? (
          <button
            type="button"
            className={btnGhost}
            disabled={isPending}
            onClick={() => {
              setQuery("");
              navigate("", pageSize);
            }}
          >
            Clear
          </button>
        ) : null}
        <p className="text-sm text-muted sm:ml-auto">
          {filtered.length} of {rows.length} users
          {appliedQuery ? ` matching "${appliedQuery}"` : ""}
        </p>
      </form>

      {searchWindowLimited ? (
        <InfoBanner tone="warn">
          This search only covered the {pageSize} accounts loaded so far, so a
          matching account outside that range is not shown. Search by full email
          address or uid to look an account up directly, or use{" "}
          <strong>Load more users</strong> to widen the range.
        </InfoBanner>
      ) : null}

      {notPersisting ? (
        <InfoBanner tone="warn">
          Firestore credentials are not configured — actions below are not
          being saved. Changes only update this session&apos;s local view and
          will be lost on refresh; nothing was written to the live database.
        </InfoBanner>
      ) : null}

      {actionError ? (
        <p
          role="alert"
          className="rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm font-semibold text-[#b42318]"
        >
          {actionError}
        </p>
      ) : null}

      <div className="rounded-lg border border-border bg-white shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)]">
        <TableWrap>
          {filtered.length === 0 ? (
            <div className="py-6">
              <EmptyState title="No users match your search" />
            </div>
          ) : (
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-border text-left text-[0.7rem] uppercase tracking-[0.12em] text-muted">
                  <th className="py-3 pr-4 font-bold">User</th>
                  <th className="py-3 pr-4 font-bold">Role</th>
                  <th className="py-3 pr-4 font-bold">Subscription</th>
                  <th className="py-3 pr-4 font-bold">Level</th>
                  <th className="py-3 pr-4 font-bold">Account</th>
                  <th className="py-3 pr-4 font-bold">Joined</th>
                  <th className="py-3 pr-2 font-bold text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((user) => {
                  const expanded = expandedId === user.id;

                  return (
                    <Fragment key={user.id}>
                      <tr className="border-b border-border last:border-0 align-top">
                        <td className="py-3 pr-4">
                          <p className="font-bold text-brand">
                            {user.displayName}
                          </p>
                          <p className="text-xs text-muted">
                            @{user.nickname} &middot; {user.email}
                          </p>
                        </td>
                        <td className="py-3 pr-4">
                          <Chip tone="neutral">{roleLabel(user.userRole)}</Chip>
                        </td>
                        <td className="py-3 pr-4">
                          <Chip
                            tone={
                              user.subscriptionStatus === "premium"
                                ? "accent"
                                : "muted"
                            }
                          >
                            {subscriptionLabel(user.subscriptionStatus)}
                          </Chip>
                          {user.subscriptionStatus === "premium" ? (
                            <p className="mt-1 text-xs text-muted">
                              {user.subscriptionExpiresAt
                                ? `Until ${formatDate(user.subscriptionExpiresAt)}`
                                : "No expiry"}
                            </p>
                          ) : null}
                        </td>
                        <td className="py-3 pr-4 whitespace-nowrap">
                          {user.level === null && user.totalXp === null ? (
                            <span className="text-muted">—</span>
                          ) : (
                            <span className="text-foreground">
                              L{user.level ?? "—"} &middot;{" "}
                              {user.totalXp === null
                                ? "—"
                                : formatNumber(user.totalXp)}{" "}
                              XP
                            </span>
                          )}
                        </td>
                        <td className="py-3 pr-4">
                          <AccountStatusChip status={user.accountStatus} />
                        </td>
                        <td className="py-3 pr-4 whitespace-nowrap text-muted">
                          {user.joinedAt ? formatDate(user.joinedAt) : "—"}
                        </td>
                        <td className="py-3 pr-2 text-right">
                          <button
                            type="button"
                            className={btnGhost}
                            onClick={() => {
                              // A staged role change belongs to the row it was
                              // started on; never carry it to another user.
                              setRoleDraft({});
                              setExpandedId((current) =>
                                current === user.id ? null : user.id,
                              );
                            }}
                            aria-expanded={expanded}
                          >
                            {expanded ? "Hide" : "View"}
                          </button>
                        </td>
                      </tr>
                      {expanded ? (
                        <tr className="border-b border-border last:border-0">
                          <td colSpan={7} className="bg-brand-soft/25 px-3 py-4">
                            <p className="text-sm text-foreground">
                              {user.note}
                            </p>
                            <p className="mt-1 text-xs text-muted">
                              uid: {user.uid} &middot; Region: {user.region}
                            </p>
                            <div className="mt-3 flex flex-wrap items-end gap-3">
                              <label className="flex flex-col gap-1">
                                <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
                                  Change role
                                </span>
                                <select
                                  value={roleDraft.role ?? user.userRole}
                                  disabled={isPending}
                                  onChange={(event) =>
                                    setRoleDraft((draft) => ({
                                      ...draft,
                                      role: event.target.value as UserRole,
                                    }))
                                  }
                                  className={`${inputBase} w-auto min-w-[11rem] cursor-pointer pr-8`}
                                >
                                  {ROLE_OPTIONS.map((option) => (
                                    <option
                                      key={option.value}
                                      value={option.value}
                                    >
                                      {option.label}
                                    </option>
                                  ))}
                                </select>
                              </label>
                              {roleDraft.role && roleDraft.role !== user.userRole ? (
                                <>
                                  <label className="flex flex-col gap-1">
                                    <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
                                      Reason
                                    </span>
                                    <input
                                      type="text"
                                      placeholder="Reason (required)"
                                      value={roleDraft.reason ?? ""}
                                      disabled={isPending}
                                      onChange={(event) =>
                                        setRoleDraft((draft) => ({
                                          ...draft,
                                          reason: event.target.value,
                                        }))
                                      }
                                      className={inputBase}
                                    />
                                  </label>
                                  <button
                                    type="button"
                                    className={
                                      roleDraft.role === "platformAdmin"
                                        ? btnDanger
                                        : btnSecondary
                                    }
                                    disabled={
                                      isPending ||
                                      (roleDraft.reason ?? "").trim() === ""
                                    }
                                    onClick={() =>
                                      changeRole(
                                        user,
                                        roleDraft.role as UserRole,
                                        roleDraft.reason ?? "",
                                      )
                                    }
                                  >
                                    {isPending
                                      ? "Working..."
                                      : `Confirm ${roleLabel(roleDraft.role)}`}
                                  </button>
                                  <button
                                    type="button"
                                    className={btnGhost}
                                    disabled={isPending}
                                    onClick={() => setRoleDraft({})}
                                  >
                                    Cancel
                                  </button>
                                </>
                              ) : null}
                              {user.accountStatus === "active" ? (
                                <button
                                  type="button"
                                  className={btnDanger}
                                  disabled={isPending}
                                  onClick={() => toggleSuspension(user)}
                                >
                                  {isPending ? "Working..." : "Suspend account"}
                                </button>
                              ) : (
                                <button
                                  type="button"
                                  className={btnSecondary}
                                  disabled={isPending}
                                  onClick={() => toggleSuspension(user)}
                                >
                                  {isPending ? "Working..." : "Restore account"}
                                </button>
                              )}
                            </div>
                            <UserOperationsPanel
                              uid={user.uid}
                              displayName={user.displayName}
                              subscriptionStatus={user.subscriptionStatus}
                              subscriptionExpiresAt={user.subscriptionExpiresAt}
                              hasAvatar={Boolean(user.hasAvatar)}
                              onSuccess={handleProgressionSuccess}
                            />
                            <UserProgressionPanel
                              uid={user.uid}
                              displayName={user.displayName}
                              totalXp={user.totalXp}
                              level={user.level}
                              monthlyXp={user.monthlyXp}
                              onSuccess={handleProgressionSuccess}
                            />
                          </td>
                        </tr>
                      ) : null}
                    </Fragment>
                  );
                })}
              </tbody>
            </table>
          )}
        </TableWrap>
      </div>

      <Pager pagination={tablePages} label="User table pages">
        {canLoadMore ? (
          <button
            type="button"
            className={btnSecondary}
            disabled={isPending}
            onClick={() => navigate(appliedQuery, pageSize * 2)}
          >
            {isPending ? "Loading..." : "Load more users"}
          </button>
        ) : (
          <span className="hidden sm:block sm:w-[7.5rem]" aria-hidden="true" />
        )}
      </Pager>

      <div className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
        <h2 className="text-base font-bold text-brand">Admin action history</h2>
        <ul className="mt-4 space-y-2">
          {log.map((entry, index) => (
            <li
              key={`session-${index}`}
              className={
                entry.live
                  ? "rounded-lg border border-accent/25 bg-accent-soft px-3 py-2 text-sm text-foreground"
                  : "rounded-lg border border-[#f5d78e] bg-[#fdf6e3] px-3 py-2 text-sm text-[#8a5a00]"
              }
            >
              {entry.message}{" "}
              {entry.live
                ? "(this session)"
                : "(not saved — Firestore is not connected)"}
            </li>
          ))}
          {historyPages.visible.map((entry) => (
            <li
              key={entry.id}
              className="flex flex-wrap items-center gap-x-2 gap-y-1 rounded-lg border border-border bg-white px-3 py-2 text-sm"
            >
              <span className="font-semibold text-brand">{entry.actor}</span>
              <span className="text-muted">{entry.action}</span>
              <span className="font-semibold text-foreground">
                {entry.target}
              </span>
              <span className="ml-auto text-xs text-muted">
                {formatDateTime(entry.timestamp)}
              </span>
            </li>
          ))}
        </ul>

        <div className="mt-4">
          <Pager pagination={historyPages} label="Admin action history pages" />
        </div>
      </div>
    </div>
  );
}
