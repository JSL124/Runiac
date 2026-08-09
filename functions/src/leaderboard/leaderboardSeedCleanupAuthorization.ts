import type { Firestore } from "firebase-admin/firestore";
import type { InventoryCandidateCounts } from "./leaderboardSeedCommandTypes.js";
import { cleanupInventoryFingerprint } from "./leaderboardSeedInventoryFingerprint.js";
import type { SeedDataset } from "./leaderboardSeedDataset.js";
import { supportedSingaporePlanningAreas } from "./singaporePlanningAreas.js";

export function currentCleanupInventoryFingerprint(input: {
  readonly projectId: string;
  readonly seedDataset: SeedDataset;
  readonly manifest: FirebaseFirestore.DocumentSnapshot;
  readonly candidateCounts: InventoryCandidateCounts;
}): string {
  return cleanupInventoryFingerprint({
    projectId: input.projectId,
    runId: input.seedDataset.dataset.runId,
    uidPrefix: input.seedDataset.uidPrefix,
    periodKey: stringOrNull(input.manifest.get("periodKey")),
    manifestStatus: stringOrNull(input.manifest.get("status")),
    regionCount: integerOrNull(input.manifest.get("regionCount")),
    usersPerRegion: integerOrNull(input.manifest.get("usersPerRegion")),
    profileCount: integerOrNull(input.manifest.get("profileCount")),
    candidateCounts: input.candidateCounts,
  });
}

export function assertInventoryFingerprint(
  suppliedFingerprint: string | null,
  currentFingerprint: string,
): void {
  if (suppliedFingerprint !== null && suppliedFingerprint !== currentFingerprint) {
    throw new Error("cleanup inventory fingerprint does not match the current preview");
  }
}

export async function assertVerifiedReplacementRun(input: {
  readonly firestore: Firestore;
  readonly projectId: string;
  readonly targetRunId: string;
  readonly replacementRunId: string | null;
}): Promise<void> {
  if (input.replacementRunId === null) return;
  if (input.replacementRunId === input.targetRunId) {
    throw new Error("replacement run must be distinct from cleanup target");
  }
  const manifest = await input.firestore.collection("leaderboardSeedRuns").doc(input.replacementRunId).get();
  if (!isVerifiedJurongEastReplacement(manifest, input.projectId, input.replacementRunId)) {
    throw new Error("replacement manifest is not a verified Jurong East fixture");
  }
}

export function matchesManifestRegions(value: unknown, regionCount: unknown, seedDataset: SeedDataset): boolean {
  if (Array.isArray(value)) return sameStringList(value, seedDataset.regionIds);
  const canonicalRegionIds = supportedSingaporePlanningAreas.map((area) => area.regionId).sort();
  return value === undefined && regionCount === canonicalRegionIds.length && sameStringList(seedDataset.regionIds, canonicalRegionIds);
}

function isVerifiedJurongEastReplacement(
  manifest: FirebaseFirestore.DocumentSnapshot,
  projectId: string,
  runId: string,
): boolean {
  return manifest.exists &&
    manifest.get("runId") === runId &&
    manifest.get("status") === "verified" &&
    manifest.get("projectId") === projectId &&
    manifest.get("periodKey") === "2026-07" &&
    sameStringList(manifest.get("regionIds"), ["jurong-east"]) &&
    manifest.get("usersPerRegion") === 100 &&
    manifest.get("profileCount") === 100 &&
    manifest.get("verifiedProfileCount") === 100 &&
    manifest.get("verifiedRankCount") === 99 &&
    // Premium parity: the 100-user fixture contains one zero-score record, and
    // the planner drops zero-score contributions before any projection is
    // written — so it yields 99 ranks AND 99 current views. This was 100 while
    // premium exclusion was the default, because an excluded runner still
    // received an `ineligible_premium` current view.
    manifest.get("verifiedCurrentViewCount") === 99 &&
    manifest.get("verifiedRegionCount") === 1 &&
    typeof manifest.get("lastRefreshBuildId") === "string";
}

function stringOrNull(value: unknown): string | null { return typeof value === "string" ? value : null; }
function integerOrNull(value: unknown): number | null { return typeof value === "number" && Number.isInteger(value) ? value : null; }
function sameStringList(value: unknown, expected: readonly string[]): boolean {
  return Array.isArray(value) && value.length === expected.length && value.every((item, index) => item === expected[index]);
}
