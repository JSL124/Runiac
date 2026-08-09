import Link from "next/link";
import { AdminSection, Chip } from "@/components/admin/primitives";
import { formatDateTime } from "@/lib/admin/format";
import type { ConfigSummary } from "@/lib/admin/live-data";

// Read-only overview panel: one row per backend-owned config document
// (config/progression, config/leaderboard, config/featureAccess,
// config/siteContent) showing its version and last-write metadata, with a
// link into the section that edits it. Server component — data.ts already
// resolved the live-vs-mock read.
export function SystemConfigSummary({
  summaries,
}: {
  summaries: ConfigSummary[];
}) {
  return (
    <AdminSection title="System configuration">
      <ul className="divide-y divide-border">
        {summaries.map((summary) => (
          <li
            key={summary.id}
            className="flex flex-col gap-2 py-3 first:pt-0 last:pb-0 sm:flex-row sm:items-center sm:justify-between"
          >
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <p className="text-sm font-bold text-foreground">{summary.label}</p>
                {summary.version !== null ? (
                  <Chip tone={summary.configured ? "brand" : "muted"}>
                    v{summary.version}
                  </Chip>
                ) : null}
                {!summary.configured ? <Chip tone="muted">Using defaults</Chip> : null}
              </div>
              <p className="mt-0.5 text-xs text-muted">
                {summary.updatedAt
                  ? `Last updated ${formatDateTime(summary.updatedAt)}`
                  : "Not yet saved to a live config document"}
                {summary.updatedBy ? ` · by ${summary.updatedBy}` : ""}
              </p>
            </div>
            <Link
              href={summary.href}
              className="text-sm font-bold text-accent transition-colors hover:text-accent/80 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/30"
            >
              Manage
            </Link>
          </li>
        ))}
      </ul>
    </AdminSection>
  );
}
