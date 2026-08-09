import { LeaderboardOversight } from "@/components/admin/LeaderboardOversight";
import { PageHeader } from "@/components/admin/primitives";
import {
  getAggregationJob,
  getLeaderboardConfig,
  getLeaderboardCoverage,
  getLeaderboardCurrentPeriod,
  getLeaderboardParticipation,
  getSuspiciousScores,
} from "@/lib/admin/data";

export const dynamic = "force-dynamic";

export default async function LeaderboardPage() {
  const [job, leaderboardConfig, suspicious, currentPeriod, participation, coverage] =
    await Promise.all([
      getAggregationJob(),
      getLeaderboardConfig(),
      getSuspiciousScores(),
      getLeaderboardCurrentPeriod(),
      getLeaderboardParticipation(),
      getLeaderboardCoverage(),
    ]);

  return (
    <>
      <PageHeader title="Leaderboard Oversight" />
      <LeaderboardOversight
        job={job}
        leaderboardConfig={leaderboardConfig}
        suspicious={suspicious}
        currentPeriod={currentPeriod}
        participation={participation}
        coverage={coverage}
      />
    </>
  );
}
