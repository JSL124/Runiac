import Link from "next/link";
import { ActiveUsersChart } from "@/components/admin/ActiveUsersChart";
import { AttentionItemsPanel } from "@/components/admin/AttentionItemsPanel";
import { SystemConfigSummary } from "@/components/admin/SystemConfigSummary";
import {
  AdminSection,
  PageHeader,
  StatCard,
  StatusPill,
} from "@/components/admin/primitives";
import {
  getActiveUsersTrend,
  getAttentionItems,
  getConfigSummaries,
  getOverviewStats,
  getSystemHealth,
} from "@/lib/admin/data";
import { formatDateTime, formatNumber } from "@/lib/admin/format";

export const dynamic = "force-dynamic";

export default async function AdminOverviewPage() {
  const [stats, health, attention, trend, configSummaries] = await Promise.all([
    getOverviewStats(),
    getSystemHealth(),
    getAttentionItems(),
    getActiveUsersTrend(),
    getConfigSummaries(),
  ]);

  return (
    <>
      <PageHeader title="Overview" />

      <section aria-label="Key metrics">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {stats.map((stat) => {
            const content = (
              <StatCard
                label={stat.label}
                value={formatNumber(stat.value)}
                hint={stat.hint}
                tone={stat.tone}
              />
            );

            return stat.href ? (
              <Link
                key={stat.id}
                href={stat.href}
                className="rounded-lg transition-transform duration-150 hover:-translate-y-0.5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/25 motion-reduce:hover:translate-y-0"
              >
                {content}
              </Link>
            ) : (
              <div key={stat.id}>{content}</div>
            );
          })}
        </div>
      </section>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <AdminSection
          title="Active users this month"
          className="lg:col-span-2"
        >
          <ActiveUsersChart data={trend} />
        </AdminSection>

        <AdminSection title="System health">
          <ul className="space-y-4">
            {health.map((component) => (
              <li key={component.id} className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-sm font-bold text-foreground">
                    {component.name}
                  </p>
                  <p className="mt-0.5 text-xs text-muted">
                    {component.description}
                  </p>
                  <p className="mt-1 text-[0.7rem] text-muted">
                    Checked {formatDateTime(component.lastCheckedAt)}
                  </p>
                </div>
                <StatusPill status={component.status} />
              </li>
            ))}
          </ul>
        </AdminSection>
      </div>

      <SystemConfigSummary summaries={configSummaries} />

      <AdminSection
        title="Attention needed"
        actions={
          <Link
            href="/admin/exceptions"
            className="text-sm font-bold text-accent transition-colors hover:text-accent/80 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/30"
          >
            Open Exception Queue
          </Link>
        }
      >
        <AttentionItemsPanel items={attention} />
      </AdminSection>
    </>
  );
}
