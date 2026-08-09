import { type Firestore, type QueryDocumentSnapshot } from "firebase-admin/firestore";
import { leaderboardLeagueDefinitions } from "../progression/leaderboardLeagues.js";
import { monthlyLeaderboardSnapshotId } from "./monthlyLeaderboardPlanner.js";
import { type MockLeaderboardRecord } from "./leaderboardMockDataset.js";
import { type SeedDataset } from "./leaderboardSeedDataset.js";
import { assertExactDocumentIds, expectedSeedDocumentIds, projectionDocuments, seedSourceCollections } from "./leaderboardSeedOwnership.js";

type SnapshotRanks = ReadonlyMap<string, readonly QueryDocumentSnapshot[]>;

const firestoreInQueryLimit = 10;

export async function verifyLeaderboardSeedRun(input: {
  readonly firestore: Firestore;
  readonly projectId: string;
  readonly seedDataset: SeedDataset;
}): Promise<Record<string, unknown>> {
  const { dataset } = input.seedDataset;
  const ids = expectedSeedDocumentIds(input.seedDataset);
  const snapshotIds = expectedSnapshotIds(input.seedDataset);
  const [users, profiles, contributions, ranks, views, snapshots, affectedRanks, manifest] = await Promise.all([
    markerDocuments(input.firestore, "users", dataset.runId),
    markerDocuments(input.firestore, "userProfiles", dataset.runId),
    markerDocuments(input.firestore, "leaderboardContributions", dataset.runId),
    projectionDocuments(input.firestore, "leaderboardUserRanks", input.seedDataset.uidPrefix),
    projectionDocuments(input.firestore, "leaderboardCurrentViews", input.seedDataset.uidPrefix),
    expectedSnapshots(input.firestore, snapshotIds),
    ranksForSnapshots(input.firestore, snapshotIds),
    input.firestore.collection("leaderboardSeedRuns").doc(dataset.runId).get(),
  ]);
  const documents = { users, userProfiles: profiles, leaderboardContributions: contributions };
  const expectedBuildId = assertManifest(manifest, input.projectId, input.seedDataset);
  for (const collection of seedSourceCollections) assertExactDocumentIds(collection, documents[collection], ids[collection]);
  assertExactDocumentIds("leaderboardUserRanks", ranks, ids.leaderboardUserRanks);
  assertExactDocumentIds("leaderboardCurrentViews", views, ids.leaderboardCurrentViews);
  assertSourceIntegrity(input.seedDataset, documents);
  const snapshotRanks = assertSnapshots(snapshots, affectedRanks, input.seedDataset, expectedBuildId);
  assertRankAndViewIntegrity(ranks, views, snapshotRanks, input.seedDataset, expectedBuildId);
  await input.firestore.collection("leaderboardSeedRuns").doc(dataset.runId).set({
    status: "verified", verifiedAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
    verifiedProfileCount: profiles.length, verifiedRankCount: ranks.length,
    verifiedCurrentViewCount: views.length, verifiedRegionCount: input.seedDataset.regionIds.length,
  }, { merge: true });
  return {
    status: "verified", profileCount: profiles.length, contributionCount: contributions.length,
    rankCount: ranks.length, currentViewCount: views.length, regionCount: input.seedDataset.regionIds.length,
    regionIds: input.seedDataset.regionIds, snapshotCount: snapshots.length,
  };
}

function expectedSnapshotIds(seedDataset: SeedDataset): readonly string[] {
  return seedDataset.regionIds.flatMap((regionId) => leaderboardLeagueDefinitions.map((league) => monthlyLeaderboardSnapshotId({ periodKey: seedDataset.dataset.periodKey, regionId, divisionKey: league.key })));
}

async function expectedSnapshots(firestore: Firestore, ids: readonly string[]): Promise<readonly QueryDocumentSnapshot[]> {
  const snapshots = await firestore.getAll(...ids.map((id) => firestore.collection("leaderboardSnapshots").doc(id)));
  return snapshots.filter((snapshot): snapshot is QueryDocumentSnapshot => snapshot.exists);
}

async function ranksForSnapshots(firestore: Firestore, snapshotIds: readonly string[]): Promise<readonly QueryDocumentSnapshot[]> {
  const batches = await Promise.all(snapshotIdBatches(snapshotIds).map((snapshotIdBatch) =>
    firestore.collection("leaderboardUserRanks").where("snapshotId", "in", snapshotIdBatch).get(),
  ));
  return batches.flatMap((batch) => batch.docs);
}

export function snapshotIdBatches(snapshotIds: readonly string[]): readonly (readonly string[])[] {
  const batches: string[][] = [];
  for (let index = 0; index < snapshotIds.length; index += firestoreInQueryLimit) {
    batches.push(snapshotIds.slice(index, index + firestoreInQueryLimit));
  }
  return batches;
}

function assertSnapshots(snapshots: readonly QueryDocumentSnapshot[], ranks: readonly QueryDocumentSnapshot[], seedDataset: SeedDataset, expectedBuildId: string): SnapshotRanks {
  const ids = expectedSnapshotIds(seedDataset);
  const expectedSnapshotIdSet = new Set(ids);
  const ranksBySnapshot = new Map<string, QueryDocumentSnapshot[]>();
  for (const rank of ranks) {
    const snapshotId = rank.get("snapshotId");
    if (typeof snapshotId !== "string" || !expectedSnapshotIdSet.has(snapshotId)) throw new Error("snapshot integrity is invalid");
    const group = ranksBySnapshot.get(snapshotId);
    if (group === undefined) ranksBySnapshot.set(snapshotId, [rank]);
    else group.push(rank);
  }
  assertExactIds("snapshot", snapshots, ids);
  const expectedBySnapshot = expectedRecordsBySnapshot(seedDataset);
  const result = new Map<string, readonly QueryDocumentSnapshot[]>();
  for (const snapshot of snapshots) {
    const expected = expectedBySnapshot.get(snapshot.id);
    const firstRecord = expected?.[0];
    if (expected === undefined || firstRecord === undefined) throw new Error("snapshot bounds are invalid");
    const topEntries = snapshot.get("topEntries");
    const entryCount = snapshot.get("entryCount");
    if (!Number.isInteger(entryCount) || entryCount < expected.length || !Array.isArray(topEntries) || topEntries.length !== Math.min(entryCount, 10) || snapshot.get("entries") !== undefined || snapshot.get("buildId") !== expectedBuildId || snapshot.get("periodKey") !== seedDataset.dataset.periodKey || snapshot.get("periodType") !== "monthly" || snapshot.get("regionId") !== firstRecord.contribution.regionId || snapshot.get("divisionKey") !== firstRecord.contribution.divisionKey || snapshot.get("regionLabel") !== firstRecord.contribution.regionLabel || snapshot.get("divisionLabel") !== firstRecord.contribution.divisionLabel) throw new Error("snapshot bounds are invalid");
    let previousScore = Number.POSITIVE_INFINITY;
    for (const [index, entry] of topEntries.entries()) {
      if (!isSafePublicEntry(entry) || entry.score > previousScore || entry.rankLabel !== `#${index + 1}`) throw new Error("snapshot ordering is invalid");
      previousScore = entry.score;
    }
    const ordered = assertGlobalSnapshotRanks(snapshot, ranksBySnapshot.get(snapshot.id) ?? [], seedDataset.dataset.periodKey, expectedBuildId);
    result.set(snapshot.id, ordered);
  }
  return result;
}

function expectedRecordsBySnapshot(seedDataset: SeedDataset): ReadonlyMap<string, readonly MockLeaderboardRecord[]> {
  const result = new Map<string, MockLeaderboardRecord[]>();
  for (const record of seedDataset.dataset.records) {
    if (record.user["subscriptionStatus"] !== "basic") continue;
    const id = monthlyLeaderboardSnapshotId({ periodKey: seedDataset.dataset.periodKey, regionId: record.contribution.regionId, divisionKey: record.contribution.divisionKey });
    const group = result.get(id);
    if (group === undefined) result.set(id, [record]);
    else group.push(record);
  }
  return result;
}

function assertGlobalSnapshotRanks(snapshot: QueryDocumentSnapshot, ranks: readonly QueryDocumentSnapshot[], periodKey: string, expectedBuildId: string): readonly QueryDocumentSnapshot[] {
  const ordered = [...ranks].sort((left, right) => rankNumber(left.get("rankLabel")) - rankNumber(right.get("rankLabel")));
  if (snapshot.get("entryCount") !== ordered.length) throw new Error("snapshot integrity is invalid");
  let previousScore = Number.POSITIVE_INFINITY;
  let previousOwnerUid = "";
  for (const [index, rank] of ordered.entries()) {
    const ownerUid = rank.get("ownerUid");
    const score = rank.get("score");
    const currentEntry = rank.get("currentEntry");
    if (typeof ownerUid !== "string" || typeof score !== "number" || !Number.isFinite(score) || rank.get("periodKey") !== periodKey || rank.get("buildId") !== expectedBuildId || rank.id !== `${ownerUid}_monthly_${periodKey}` || rank.get("rankLabel") !== `#${index + 1}` || rank.get("regionId") !== snapshot.get("regionId") || rank.get("divisionKey") !== snapshot.get("divisionKey") || !isSafePublicEntry(currentEntry) || currentEntry.score !== score || currentEntry.rankLabel !== rank.get("rankLabel") || currentEntry.regionLabel !== snapshot.get("regionLabel") || currentEntry.divisionLabel !== snapshot.get("divisionLabel") || score > previousScore || (score === previousScore && ownerUid.localeCompare(previousOwnerUid) < 0)) throw new Error("snapshot integrity is invalid");
    const topEntries = snapshot.get("topEntries");
    if (Array.isArray(topEntries) && index < topEntries.length && !sameValue(topEntries[index], currentEntry)) throw new Error("snapshot integrity is invalid");
    previousScore = score;
    previousOwnerUid = ownerUid;
  }
  return ordered;
}

function assertRankAndViewIntegrity(ranks: readonly QueryDocumentSnapshot[], views: readonly QueryDocumentSnapshot[], snapshotRanks: SnapshotRanks, seedDataset: SeedDataset, expectedBuildId: string): void {
  const ranksById = new Map(ranks.map((rank) => [rank.id, rank]));
  const viewsByUid = new Map(views.map((view) => [view.id, view]));
  for (const record of seedDataset.dataset.records) {
    const view = viewsByUid.get(record.uid);
    // Premium parity: a premium seed record is ranked like any other. What
    // still keeps a record off the board is a zero score, and the planner drops
    // those before any projection is written — so it must have no view at all,
    // not an "excluded" one.
    if (record.contribution.scoreXp <= 0) {
      if (view !== undefined) throw new Error("current view integrity is invalid");
      continue;
    }
    if (view === undefined || view.get("ownerUid") !== record.uid || view.get("periodKey") !== seedDataset.dataset.periodKey || view.get("buildId") !== expectedBuildId || view.get("regionId") !== record.contribution.regionId || view.get("homeRegionId") !== record.contribution.regionId || view.get("divisionKey") !== record.contribution.divisionKey) throw new Error("current view integrity is invalid");
    const snapshotId = monthlyLeaderboardSnapshotId({ periodKey: seedDataset.dataset.periodKey, regionId: record.contribution.regionId, divisionKey: record.contribution.divisionKey });
    const rankId = `${record.uid}_monthly_${seedDataset.dataset.periodKey}`;
    const rank = ranksById.get(rankId);
    if (rank === undefined || rank.get("ownerUid") !== record.uid || rank.get("periodKey") !== seedDataset.dataset.periodKey || rank.get("buildId") !== expectedBuildId || rank.get("snapshotId") !== snapshotId || rank.get("regionId") !== record.contribution.regionId || rank.get("divisionKey") !== record.contribution.divisionKey || rank.get("score") !== record.contribution.scoreXp || !matchesExpectedEntry(rank.get("currentEntry"), record, rank.get("rankLabel"))) throw new Error("rank integrity is invalid");
    const group = snapshotRanks.get(snapshotId);
    const rankIndex = group?.findIndex((candidate) => candidate.id === rank.id) ?? -1;
    if (group === undefined || rankIndex < 0 || !sameValue(rank.get("nearbyEntries"), nearbyEntries(group, rankIndex))) throw new Error("rank integrity is invalid");
    if (view.get("status") !== "ranked" || view.get("rankId") !== rankId || view.get("snapshotId") !== snapshotId || view.get("activeRankProjectionId") !== rankId || view.get("activeSnapshotId") !== snapshotId) throw new Error("current view integrity is invalid");
  }
}

function nearbyEntries(group: readonly QueryDocumentSnapshot[], rankIndex: number): readonly unknown[] {
  const start = Math.min(Math.max(0, rankIndex - 2), Math.max(0, group.length - 5));
  return group.slice(start, start + 5).map((rank) => rank.get("currentEntry"));
}

function matchesExpectedEntry(value: unknown, record: MockLeaderboardRecord, rankLabel: unknown): boolean {
  return isSafePublicEntry(value) && value.publicAlias === record.contribution.publicAlias && value.score === record.contribution.scoreXp && value.scoreLabel === `${record.contribution.scoreXp.toLocaleString("en-US")} XP` && value.levelLabel === record.contribution.levelLabel && value.divisionLabel === record.contribution.divisionLabel && value.regionLabel === record.contribution.regionLabel && value.rankLabel === rankLabel;
}

function assertManifest(manifest: FirebaseFirestore.DocumentSnapshot, projectId: string, seedDataset: SeedDataset): string {
  const { dataset } = seedDataset;
  const buildId = manifest.get("lastRefreshBuildId");
  if (!manifest.exists || manifest.get("runId") !== dataset.runId || manifest.get("projectId") !== projectId || manifest.get("periodKey") !== dataset.periodKey || !sameStringList(manifest.get("regionIds"), seedDataset.regionIds) || manifest.get("usersPerRegion") !== dataset.usersPerRegion || manifest.get("regionCount") !== dataset.regionCount || manifest.get("profileCount") !== dataset.records.length || typeof buildId !== "string") throw new Error("seed manifest integrity is invalid");
  return buildId;
}

function assertSourceIntegrity(seedDataset: SeedDataset, documents: { readonly users: readonly QueryDocumentSnapshot[]; readonly userProfiles: readonly QueryDocumentSnapshot[]; readonly leaderboardContributions: readonly QueryDocumentSnapshot[] }): void {
  const users = new Map(documents.users.map((document) => [document.id, document]));
  const profiles = new Map(documents.userProfiles.map((document) => [document.id, document]));
  const contributions = new Map(documents.leaderboardContributions.map((document) => [document.id, document]));
  for (const record of seedDataset.dataset.records) {
    const user = users.get(record.uid);
    const profile = profiles.get(record.uid);
    const contribution = contributions.get(`${record.uid}_monthly_${seedDataset.dataset.periodKey}`);
    if (user === undefined || profile === undefined || contribution === undefined || !sameValue(user.data(), record.user) || !sameValue(profile.data(), record.profile) || !sameValue(contribution.data(), record.contribution)) throw new Error("seed source integrity is invalid");
  }
}

function markerDocuments(firestore: Firestore, collection: string, runId: string): Promise<readonly QueryDocumentSnapshot[]> {
  return firestore.collection(collection).where("mockSeedRunId", "==", runId).get().then((snapshot) => snapshot.docs);
}

function assertExactIds(collection: string, documents: readonly QueryDocumentSnapshot[], expectedIds: readonly string[]): void {
  const actual = new Set(documents.map((document) => document.id));
  const expected = new Set(expectedIds);
  if (actual.size !== expected.size || [...actual].some((id) => !expected.has(id))) throw new Error(`${collection} set is incomplete`);
}

function rankNumber(value: unknown): number {
  if (typeof value !== "string" || !/^#[1-9]\d*$/.test(value)) throw new Error("snapshot integrity is invalid");
  return Number(value.slice(1));
}

// Exact key-set guard, deliberately not a subset check: a published entry lands
// in world-readable `leaderboardSnapshots`, so an unexpected extra key (a uid,
// a raw profile field) must fail verification rather than be tolerated. Any
// intentional addition to `LeaderboardPublicEntry` therefore has to be
// registered here as well — `levelProgressPercent` is the XP-ring value.
function isSafePublicEntry(value: unknown): value is { readonly avatarUrl: string; readonly divisionLabel: string; readonly levelLabel: string; readonly levelProgressPercent: number; readonly publicAlias: string; readonly rankLabel: string; readonly regionLabel: string; readonly score: number; readonly scoreLabel: string } {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const keys = ["avatarUrl", "divisionLabel", "levelLabel", "levelProgressPercent", "publicAlias", "rankLabel", "regionLabel", "score", "scoreLabel"];
  return JSON.stringify(Object.keys(value).sort()) === JSON.stringify(keys.sort()) && typeof Reflect.get(value, "avatarUrl") === "string" && typeof Reflect.get(value, "divisionLabel") === "string" && typeof Reflect.get(value, "levelLabel") === "string" && typeof Reflect.get(value, "levelProgressPercent") === "number" && typeof Reflect.get(value, "publicAlias") === "string" && typeof Reflect.get(value, "rankLabel") === "string" && typeof Reflect.get(value, "regionLabel") === "string" && typeof Reflect.get(value, "score") === "number" && typeof Reflect.get(value, "scoreLabel") === "string";
}

function sameStringList(value: unknown, expected: readonly string[]): boolean {
  return Array.isArray(value) && value.length === expected.length && value.every((item, index) => item === expected[index]);
}

function sameValue(left: unknown, right: unknown): boolean {
  if (Object.is(left, right)) return true;
  if (Array.isArray(left) || Array.isArray(right)) return Array.isArray(left) && Array.isArray(right) && left.length === right.length && left.every((item, index) => sameValue(item, right[index]));
  if (typeof left !== "object" || left === null || typeof right !== "object" || right === null) return false;
  const leftKeys = Object.keys(left).sort();
  const rightKeys = Object.keys(right).sort();
  return leftKeys.length === rightKeys.length && leftKeys.every((key, index) => key === rightKeys[index] && sameValue(Reflect.get(left, key), Reflect.get(right, key)));
}
