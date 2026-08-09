import { createHash } from "node:crypto";
import type { InventoryCandidateCounts } from "./leaderboardSeedCommandTypes.js";

export type CleanupInventoryFingerprintInput = {
  readonly projectId: string;
  readonly runId: string;
  readonly uidPrefix: string;
  readonly periodKey: string | null;
  readonly manifestStatus: string | null;
  readonly regionCount: number | null;
  readonly usersPerRegion: number | null;
  readonly profileCount: number | null;
  readonly candidateCounts: InventoryCandidateCounts;
};

export function cleanupInventoryFingerprint(input: CleanupInventoryFingerprintInput): string {
  const payload = JSON.stringify([
    input.projectId,
    input.runId,
    input.uidPrefix,
    input.periodKey,
    input.manifestStatus,
    input.regionCount,
    input.usersPerRegion,
    input.profileCount,
    input.candidateCounts.users,
    input.candidateCounts.userProfiles,
    input.candidateCounts.leaderboardContributions,
    input.candidateCounts.leaderboardUserRanks,
    input.candidateCounts.leaderboardCurrentViews,
  ]);
  return `sha256:${createHash("sha256").update(payload).digest("hex")}`;
}
