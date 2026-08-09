import { ErrorMonitoring } from "@/components/admin/ErrorMonitoring";
import {
  InfoBanner,
  PageHeader,
  StatCard,
} from "@/components/admin/primitives";
import { getErrorGroups } from "@/lib/admin/data";
import { formatNumber } from "@/lib/admin/format";
import { ERROR_GROUPS_READ_LIMIT } from "@/lib/firebase/firestore";

export const dynamic = "force-dynamic";

export default async function ErrorsPage() {
  const groups = await getErrorGroups();
  // ERROR_GROUPS_READ_LIMIT is a defensive ceiling, not a page size (see the
  // comment on listErrorGroups() in src/lib/firebase/firestore.ts). Returning
  // exactly that many rows means the read was truncated, which would
  // otherwise silently change what the StatCards below and the table's
  // filters claim to total.
  const groupsTruncated = groups.length === ERROR_GROUPS_READ_LIMIT;

  const criticalGroups = groups.filter(
    (group) => group.severity === "critical",
  ).length;
  const unresolved = groups.filter(
    (group) => group.status === "new" || group.status === "investigating",
  ).length;
  // groups starts empty in a freshly-configured or quiet environment — an
  // unguarded reduce() over an empty array throws, so mostRepeated is only
  // computed when there is at least one group.
  const mostRepeated =
    groups.length > 0
      ? groups.reduce((max, group) =>
          group.occurrences > max.occurrences ? group : max,
        )
      : null;
  const affectedUsers = groups.reduce(
    (sum, group) => sum + group.affectedUsers,
    0,
  );

  return (
    <>
      <PageHeader title="App Errors" />

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Critical groups"
          value={criticalGroups}
          hint="Highest-severity groups"
          tone="critical"
        />
        <StatCard
          label="Unresolved groups"
          value={unresolved}
          hint="New or investigating"
          tone="accent"
        />
        <StatCard
          label="Most-repeated error"
          value={mostRepeated ? formatNumber(mostRepeated.occurrences) : "—"}
          hint={mostRepeated ? mostRepeated.title : "No errors reported yet"}
        />
        <StatCard
          label="Affected users"
          value={formatNumber(affectedUsers)}
          hint="Across all groups"
        />
      </div>

      {groupsTruncated ? (
        <InfoBanner tone="warn">
          Showing the {formatNumber(ERROR_GROUPS_READ_LIMIT)} most recently
          seen error groups. The environment has reached this cap, so the
          totals and filters below may not reflect every group — older
          groups beyond this limit are not included.
        </InfoBanner>
      ) : null}

      <ErrorMonitoring groups={groups} />
    </>
  );
}
