"use client";

// Tab shell for the admin "Newsletter" console (src/app/admin/newsletter).
// No existing admin page has a tabbed layout to copy, so this is a small,
// local pattern: plain client-side tab state (no routing/query-string
// involvement needed, since the two tabs never need to be independently
// linkable) switching between the two feature components below.

import { useState } from "react";
import { NewsletterCampaigns } from "@/components/admin/NewsletterCampaigns";
import { NewsletterSubscribers } from "@/components/admin/NewsletterSubscribers";
import type { NewsletterCampaign, NewsletterSubscriber } from "@/lib/admin/types";

type Tab = "subscribers" | "campaigns";

const TABS: { id: Tab; label: string }[] = [
  { id: "subscribers", label: "Subscribers" },
  { id: "campaigns", label: "Campaigns" },
];

export function NewsletterConsole({
  subscribers,
  campaigns,
}: {
  subscribers: NewsletterSubscriber[];
  campaigns: NewsletterCampaign[];
}) {
  const [tab, setTab] = useState<Tab>("subscribers");

  return (
    <div className="space-y-6">
      <div
        role="tablist"
        aria-label="Newsletter sections"
        className="inline-flex rounded-lg border border-border bg-white p-1"
      >
        {TABS.map((item) => {
          const active = item.id === tab;
          return (
            <button
              key={item.id}
              type="button"
              role="tab"
              aria-selected={active}
              onClick={() => setTab(item.id)}
              className={`rounded-md px-4 py-1.5 text-sm font-bold transition-colors duration-150 ${
                active ? "bg-brand text-white" : "text-brand hover:bg-brand-soft/70"
              }`}
            >
              {item.label}
            </button>
          );
        })}
      </div>

      <div role="tabpanel">
        {tab === "subscribers" ? (
          <NewsletterSubscribers subscribers={subscribers} />
        ) : (
          <NewsletterCampaigns campaigns={campaigns} />
        )}
      </div>
    </div>
  );
}
