"use client";

// Campaigns tab of the admin "Newsletter" console
// (src/app/admin/newsletter). Compose (subject + Markdown body), "Send test
// to yourself", "Send" behind an explicit confirm dialog, and a send history
// table with per-campaign delivery failure visibility.
//
// The console only ever flips a campaign's `status` / writes
// `testRecipients` (src/lib/actions/newsletter.ts) — a Firestore trigger
// outside this app does the actual sending. "Send test" always targets the
// signed-in admin's own email; there is no field anywhere on this tab to
// choose an arbitrary test recipient. A sent/queued campaign can never be
// edited or re-sent from here — see the "draft only" guards in
// src/lib/firebase/firestore.ts.

import { useRouter } from "next/navigation";
import { Fragment, useEffect, useRef, useState, useTransition } from "react";
import { btnPrimary, btnSecondary, inputBase } from "@/components/admin/button-styles";
import { EmptyState, InfoBanner, TableWrap } from "@/components/admin/primitives";
import {
  getNewsletterCampaignDeliveries,
  saveNewsletterCampaignDraft,
  sendNewsletterCampaign,
  sendTestNewsletterCampaign,
} from "@/lib/actions/newsletter";
import { formatDateTime, formatNumber } from "@/lib/admin/format";
import type {
  NewsletterCampaign,
  NewsletterCampaignStatus,
  NewsletterDelivery,
} from "@/lib/admin/types";

const CAMPAIGN_STATUS_STYLES: Record<NewsletterCampaignStatus, string> = {
  draft: "border-border bg-brand-soft text-muted",
  testQueued: "border-accent/25 bg-accent-soft text-accent",
  queued: "border-accent/25 bg-accent-soft text-accent",
  sending: "border-accent/25 bg-accent-soft text-accent",
  sent: "border-[#bfe3d3] bg-[#eafaf3] text-[#0f6b4e]",
  failed: "border-[#f0c2bc] bg-[#fdecea] text-[#b42318]",
};

function CampaignStatusBadge({ status }: { status: NewsletterCampaignStatus }) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-bold capitalize ${CAMPAIGN_STATUS_STYLES[status]}`}
    >
      {status === "testQueued" ? "Test queued" : status}
    </span>
  );
}

type DeliveriesState =
  | { kind: "loading" }
  | { kind: "error"; error: string }
  | { kind: "loaded"; deliveries: NewsletterDelivery[] };

export function NewsletterCampaigns({
  campaigns,
}: {
  campaigns: NewsletterCampaign[];
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [rows, setRows] = useState(campaigns);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [subject, setSubject] = useState("");
  const [bodyMarkdown, setBodyMarkdown] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [deliveriesByCampaign, setDeliveriesByCampaign] = useState<
    Record<string, DeliveriesState>
  >({});
  const [openDeliveriesFor, setOpenDeliveriesFor] = useState<string | null>(null);

  // Live mode: after router.refresh() the server passes fresh campaign data;
  // re-sync local rows. Mock props are stable, so local state persists.
  const [prevCampaigns, setPrevCampaigns] = useState(campaigns);
  if (prevCampaigns !== campaigns) {
    setPrevCampaigns(campaigns);
    setRows(campaigns);
  }

  // Mirrors `rows` into a ref so the poll interval below always reads the
  // latest data without needing to be torn down and rebuilt on every render.
  // Synced in an effect, not during render — refs must not be written while
  // rendering (react-hooks/refs).
  const rowsRef = useRef(rows);
  useEffect(() => {
    rowsRef.current = rows;
  }, [rows]);

  // "Send test"/"Send" only ever move a campaign into an INTERMEDIATE status
  // (testQueued / queued) — the Firestore trigger that actually sends mail
  // moves it on again asynchronously (testQueued -> draft; queued -> sending
  // -> sent/failed). A single router.refresh() right after queuing almost
  // always lands on that still-intermediate status, which the composer and
  // Actions column treat as non-editable/non-sendable — so nothing ever
  // refreshes again and the admin has to reload the page to continue the
  // normal test-then-send flow. This polls the existing router.refresh() data
  // path on an interval until the campaign's row leaves the intermediate
  // status, then stops. Only one poll runs at a time (the most recent action
  // wins), which matches this composer only ever driving one in-flight action
  // at a time.
  const POLL_INTERVAL_MS = 2500;
  const POLL_MAX_ATTEMPTS = 12; // ~30s at POLL_INTERVAL_MS
  const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const pollAttemptsRef = useRef(0);

  function stopPolling() {
    if (pollTimerRef.current !== null) {
      clearInterval(pollTimerRef.current);
      pollTimerRef.current = null;
    }
    pollAttemptsRef.current = 0;
  }

  // Clean up any in-flight poll on unmount.
  useEffect(() => stopPolling, []);

  function pollUntilSettled(
    campaignId: string,
    isIntermediate: (status: NewsletterCampaignStatus) => boolean,
  ) {
    stopPolling();

    pollTimerRef.current = setInterval(() => {
      pollAttemptsRef.current += 1;

      const current = rowsRef.current.find((row) => row.id === campaignId);
      const settled = !current || !isIntermediate(current.status);

      if (settled || pollAttemptsRef.current >= POLL_MAX_ATTEMPTS) {
        stopPolling();
        return;
      }

      router.refresh();
    }, POLL_INTERVAL_MS);
  }

  const editingCampaign = editingId ? rows.find((row) => row.id === editingId) ?? null : null;
  // A brand-new, unsaved draft (editingCampaign is null but editingId may
  // still be null too) is always editable; once a campaign row exists, it
  // stays editable/sendable only while its status is still "draft".
  const isEditableDraft = editingCampaign === null || editingCampaign.status === "draft";
  const hasContent = subject.trim().length > 0 && bodyMarkdown.trim().length > 0;
  const canActOnComposer = isEditableDraft && hasContent && !isPending;

  function resetComposer() {
    setEditingId(null);
    setSubject("");
    setBodyMarkdown("");
  }

  function loadDraftIntoComposer(campaign: NewsletterCampaign) {
    setEditingId(campaign.id);
    setSubject(campaign.subject);
    setBodyMarkdown(campaign.bodyMarkdown);
    setActionError(null);
    setNotice(null);
  }

  function upsertRow(campaign: NewsletterCampaign) {
    setRows((prev) => {
      const exists = prev.some((row) => row.id === campaign.id);
      return exists
        ? prev.map((row) => (row.id === campaign.id ? campaign : row))
        : [campaign, ...prev];
    });
  }

  // Saves the composer's current subject/body as a draft, returning the
  // resulting campaign id (existing or newly created) on success, or null on
  // failure (with actionError already set).
  async function saveDraft(): Promise<string | null> {
    const result = await saveNewsletterCampaignDraft(editingId, subject, bodyMarkdown);

    if (!result.ok) {
      setActionError(result.error);
      return null;
    }

    const nextId = result.campaignId ?? editingId;

    if (nextId) {
      setEditingId(nextId);
      upsertRow({
        id: nextId,
        subject: subject.trim(),
        bodyMarkdown: bodyMarkdown.trim(),
        status: editingCampaign?.status ?? "draft",
        createdBy: editingCampaign?.createdBy ?? "",
        createdAt: editingCampaign?.createdAt ?? null,
        queuedAt: editingCampaign?.queuedAt ?? null,
        sentAt: editingCampaign?.sentAt ?? null,
        recipientCount: editingCampaign?.recipientCount ?? 0,
        deliveredCount: editingCampaign?.deliveredCount ?? 0,
        failedCount: editingCampaign?.failedCount ?? 0,
        testRecipients: editingCampaign?.testRecipients ?? [],
        lastTestSentAt: editingCampaign?.lastTestSentAt ?? null,
        error: editingCampaign?.error ?? null,
      });
    }

    if (result.live) {
      router.refresh();
    }

    return nextId ?? null;
  }

  function handleSaveDraft() {
    setActionError(null);
    setNotice(null);
    startTransition(async () => {
      const id = await saveDraft();
      if (id) {
        setNotice("Draft saved.");
      }
    });
  }

  function handleSendTest() {
    setActionError(null);
    setNotice(null);
    startTransition(async () => {
      const id = await saveDraft();
      if (!id) {
        return;
      }

      const result = await sendTestNewsletterCampaign(id);
      if (!result.ok) {
        setActionError(result.error);
        return;
      }

      setNotice("Test send queued to your own email.");
      if (result.live) {
        router.refresh();
        // The row is now "testQueued", not editable/sendable; poll until the
        // trigger reverts it back to "draft" so the flow can continue without
        // a manual reload.
        pollUntilSettled(id, (status) => status === "testQueued");
      }
    });
  }

  function handleSend() {
    const confirmed = window.confirm(
      `Send "${subject.trim() || "this campaign"}" to every confirmed subscriber? This cannot be undone.`,
    );
    if (!confirmed) {
      return;
    }

    setActionError(null);
    setNotice(null);
    startTransition(async () => {
      const id = await saveDraft();
      if (!id) {
        return;
      }

      const result = await sendNewsletterCampaign(id);
      if (!result.ok) {
        setActionError(result.error);
        return;
      }

      setNotice("Campaign queued for sending.");
      resetComposer();
      if (result.live) {
        router.refresh();
        // Terminal states are "sent"/"failed"; "queued"/"sending" are both
        // still in flight, so keep polling through either of them.
        pollUntilSettled(
          id,
          (status) => status === "queued" || status === "sending",
        );
      }
    });
  }

  function toggleDeliveries(campaignId: string) {
    if (openDeliveriesFor === campaignId) {
      setOpenDeliveriesFor(null);
      return;
    }

    setOpenDeliveriesFor(campaignId);

    if (deliveriesByCampaign[campaignId]) {
      return;
    }

    setDeliveriesByCampaign((prev) => ({ ...prev, [campaignId]: { kind: "loading" } }));

    startTransition(async () => {
      const result = await getNewsletterCampaignDeliveries(campaignId);
      setDeliveriesByCampaign((prev) => ({
        ...prev,
        [campaignId]: result.ok
          ? { kind: "loaded", deliveries: result.deliveries }
          : { kind: "error", error: result.error },
      }));
    });
  }

  return (
    <div className="space-y-6">
      <div className="rounded-lg border border-border bg-white p-5 shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] sm:p-6">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-base font-bold text-brand">
            {editingId ? "Edit draft" : "New draft"}
          </h3>
          {editingId ? (
            <button type="button" className={btnSecondary} onClick={resetComposer}>
              Start a new draft
            </button>
          ) : null}
        </div>

        {editingCampaign && editingCampaign.status !== "draft" ? (
          <div className="mt-3">
            <InfoBanner tone="warn">
              This campaign is {editingCampaign.status} and can no longer be
              edited or re-sent.
            </InfoBanner>
          </div>
        ) : null}

        <label className="mt-4 block">
          <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
            Subject
          </span>
          <input
            type="text"
            value={subject}
            maxLength={200}
            disabled={isPending || !isEditableDraft}
            onChange={(event) => setSubject(event.target.value)}
            placeholder="What's new at Runiac"
            className={`${inputBase} mt-1`}
          />
        </label>

        <label className="mt-4 block">
          <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
            Body (Markdown)
          </span>
          <textarea
            rows={10}
            value={bodyMarkdown}
            disabled={isPending || !isEditableDraft}
            onChange={(event) => setBodyMarkdown(event.target.value)}
            placeholder={"# Heading\n\nWrite the email body in Markdown."}
            className={`${inputBase} mt-1 h-auto py-2 font-mono text-xs leading-relaxed`}
          />
        </label>

        {actionError ? (
          <div
            role="alert"
            className="mt-4 rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm font-semibold text-[#b42318]"
          >
            {actionError}
          </div>
        ) : null}

        {notice ? (
          <p className="mt-4 text-sm font-semibold text-brand" aria-live="polite">
            {notice}
          </p>
        ) : null}

        <div className="mt-5 flex flex-wrap gap-2">
          <button
            type="button"
            className={btnSecondary}
            disabled={!canActOnComposer}
            onClick={handleSaveDraft}
          >
            Save draft
          </button>
          <button
            type="button"
            className={btnSecondary}
            disabled={!canActOnComposer}
            onClick={handleSendTest}
          >
            Send test to yourself
          </button>
          <button
            type="button"
            className={btnPrimary}
            disabled={!canActOnComposer}
            onClick={handleSend}
          >
            Send
          </button>
        </div>
      </div>

      <div className="space-y-3">
        <h3 className="text-lg font-bold text-brand">History</h3>

        {rows.length === 0 ? (
          <EmptyState
            title="No campaigns yet"
            description="Compose a draft above to get started."
          />
        ) : (
          <div className="rounded-lg border border-border bg-white shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)]">
            <TableWrap>
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-[0.7rem] uppercase tracking-[0.12em] text-muted">
                    <th className="py-3 pr-4 font-bold">Subject</th>
                    <th className="py-3 pr-4 font-bold">Status</th>
                    <th className="py-3 pr-4 font-bold">Recipients</th>
                    <th className="py-3 pr-4 font-bold">Delivered</th>
                    <th className="py-3 pr-4 font-bold">Failed</th>
                    <th className="py-3 pr-4 font-bold">Sent</th>
                    <th className="py-3 pr-2 text-right font-bold">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => (
                    <Fragment key={row.id}>
                      <tr className="border-b border-border align-top">
                        <td className="py-3 pr-4 font-semibold text-brand">{row.subject}</td>
                        <td className="py-3 pr-4">
                          <CampaignStatusBadge status={row.status} />
                        </td>
                        <td className="py-3 pr-4 text-muted">{formatNumber(row.recipientCount)}</td>
                        <td className="py-3 pr-4 text-muted">{formatNumber(row.deliveredCount)}</td>
                        <td className="py-3 pr-4 text-muted">{formatNumber(row.failedCount)}</td>
                        <td className="py-3 pr-4 text-muted">
                          {row.sentAt ? formatDateTime(row.sentAt) : "—"}
                        </td>
                        <td className="py-3 pr-2 text-right">
                          <div className="flex justify-end gap-2">
                            {row.status === "draft" ? (
                              <button
                                type="button"
                                className={btnSecondary}
                                disabled={isPending}
                                onClick={() => loadDraftIntoComposer(row)}
                              >
                                Edit
                              </button>
                            ) : null}
                            {row.failedCount > 0 || row.deliveredCount > 0 ? (
                              <button
                                type="button"
                                className={btnSecondary}
                                disabled={isPending}
                                onClick={() => toggleDeliveries(row.id)}
                              >
                                {openDeliveriesFor === row.id ? "Hide" : "View"} deliveries
                              </button>
                            ) : null}
                          </div>
                        </td>
                      </tr>
                      {openDeliveriesFor === row.id ? (
                        <tr className="border-b border-border bg-brand-soft/30">
                          <td colSpan={7} className="px-4 py-4">
                            <DeliveriesPanel state={deliveriesByCampaign[row.id]} />
                          </td>
                        </tr>
                      ) : null}
                    </Fragment>
                  ))}
                </tbody>
              </table>
            </TableWrap>
          </div>
        )}
      </div>
    </div>
  );
}

function DeliveriesPanel({ state }: { state: DeliveriesState | undefined }) {
  if (!state || state.kind === "loading") {
    return <p className="text-sm text-muted">Loading delivery history…</p>;
  }

  if (state.kind === "error") {
    return <p className="text-sm font-semibold text-[#b42318]">{state.error}</p>;
  }

  if (state.deliveries.length === 0) {
    return <p className="text-sm text-muted">No delivery records yet.</p>;
  }

  const failed = state.deliveries.filter((delivery) => Boolean(delivery.error));
  const ok = state.deliveries.filter((delivery) => !delivery.error);

  return (
    <div className="space-y-3">
      {failed.length > 0 ? (
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#b42318]">
            Failed ({failed.length})
          </p>
          <ul className="mt-1 space-y-1">
            {failed.map((delivery) => (
              <li key={delivery.id} className="text-sm text-foreground">
                <span className="font-semibold">{delivery.id}</span> — {delivery.status}
                {delivery.error ? `: ${delivery.error}` : ""}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      {ok.length > 0 ? (
        <p className="text-xs text-muted">{ok.length} delivered without error.</p>
      ) : null}
    </div>
  );
}
