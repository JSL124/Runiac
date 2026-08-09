"use client";

import Link from "next/link";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { dismissAttentionItem } from "@/lib/actions/admin";
import { CaptionLabel, SeverityBadge } from "@/components/admin/primitives";
import type { AttentionItem } from "@/lib/admin/types";

// Dashboard "Attention needed" list. Items come from the adminNotifications
// collection (written by Cloud Functions automation); dismissing one
// merge-writes status: "dismissed" and appends an audit entry.
export function AttentionItemsPanel({ items }: { items: AttentionItem[] }) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [dismissingId, setDismissingId] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  function handleDismiss(id: string) {
    setDismissingId(id);
    setErrorMessage(null);
    startTransition(async () => {
      const result = await dismissAttentionItem(id);
      setDismissingId(null);
      if (!result.ok) {
        setErrorMessage(result.error);
        return;
      }
      if (result.live) {
        router.refresh();
      }
    });
  }

  if (items.length === 0) {
    return (
      <p className="text-sm text-muted">
        Nothing needs attention right now. Automation escalations will appear
        here.
      </p>
    );
  }

  return (
    <>
      {errorMessage ? (
        <p className="mb-3 text-sm font-semibold text-[#b42318]">{errorMessage}</p>
      ) : null}
      <ul className="space-y-3">
        {items.map((item) => (
          <li
            key={item.id}
            className="flex flex-col gap-2 rounded-lg border border-border bg-white px-4 py-3 sm:flex-row sm:items-center sm:justify-between"
          >
            <Link
              href={item.href}
              className="min-w-0 flex-1 rounded-md transition-colors duration-150 hover:bg-brand-soft/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/25"
            >
              <p className="text-sm font-bold text-brand">{item.title}</p>
              <p className="mt-0.5 text-xs text-muted">{item.detail}</p>
            </Link>
            <div className="flex items-center gap-2">
              <SeverityBadge severity={item.severity} />
              <CaptionLabel>Review</CaptionLabel>
              <button
                type="button"
                onClick={() => handleDismiss(item.id)}
                disabled={isPending && dismissingId === item.id}
                className="rounded-md border border-border px-2 py-1 text-xs font-semibold text-muted transition-colors hover:border-brand/25 hover:text-brand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/25 disabled:opacity-50"
              >
                {isPending && dismissingId === item.id ? "Dismissing…" : "Dismiss"}
              </button>
            </div>
          </li>
        ))}
      </ul>
    </>
  );
}
