import { generateMockLeaderboardDataset, type MockLeaderboardDataset } from "./leaderboardMockDataset.js";

export type SeedDataset = {
  readonly dataset: MockLeaderboardDataset;
  readonly regionIds: readonly string[];
  readonly uidPrefix: string;
};

export function createSeedDataset(input: {
  readonly runId: string;
  readonly periodKey: string;
  readonly usersPerRegion: number;
  readonly regionId: string | undefined;
}): SeedDataset {
  const dataset = input.regionId === undefined
    ? generateMockLeaderboardDataset({
      runId: input.runId,
      periodKey: input.periodKey,
      usersPerRegion: input.usersPerRegion,
    })
    : generateMockLeaderboardDataset({
      runId: input.runId,
      periodKey: input.periodKey,
      usersPerRegion: input.usersPerRegion,
      regionId: input.regionId,
    });
  const regionIds = [...new Set(dataset.records.map((record) => record.contribution.regionId))]
    .sort();
  return {
    dataset,
    regionIds,
    uidPrefix: `lbmock_${dataset.runId}_`,
  };
}

export function seedDatasetSummary(
  projectId: string,
  seedDataset: SeedDataset,
): Record<string, unknown> {
  const { dataset } = seedDataset;
  return {
    projectId,
    runId: dataset.runId,
    periodKey: dataset.periodKey,
    uidPrefix: seedDataset.uidPrefix,
    regionIds: seedDataset.regionIds,
    regionCount: dataset.regionCount,
    usersPerRegion: dataset.usersPerRegion,
    profileCount: dataset.records.length,
    basicCount: dataset.records.length - dataset.regionCount,
    premiumCount: dataset.regionCount,
    sourceWriteCount: dataset.records.length * 3,
    candidateCounts: {
      users: dataset.records.length,
      userProfiles: dataset.records.length,
      leaderboardContributions: dataset.records.length,
      leaderboardUserRanks: dataset.records.length - dataset.regionCount,
      // One zero-score record per region reaches neither a rank nor a current
      // view: the planner drops `scoreXp <= 0` contributions outright.
      leaderboardCurrentViews: dataset.records.length - dataset.regionCount,
    },
  };
}
