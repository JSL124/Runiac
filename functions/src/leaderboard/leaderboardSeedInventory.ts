import { FieldPath, type Firestore, type QueryDocumentSnapshot } from "firebase-admin/firestore";
import {
  type InventoryCandidateCounts,
  type InventoryIssue,
  type InventoryRun,
  type InventorySummary,
} from "./leaderboardSeedCommandTypes.js";
import { cleanupInventoryFingerprint } from "./leaderboardSeedInventoryFingerprint.js";

// Works out what the leaderboard seeder actually created, before a cleanup
// deletes anything.
//
// Seeded documents are identified by fingerprint rather than by collection, so
// a cleanup can tell a mock runner apart from a real one that happens to live
// in the same collection. Anything that cannot be positively identified is
// reported as an issue and blocks the cleanup instead of being deleted on the
// assumption it was ours.

const sourceCollections = ["users", "userProfiles", "leaderboardContributions"] as const;
const candidateCollections = [
  "users",
  "userProfiles",
  "leaderboardContributions",
  "leaderboardUserRanks",
  "leaderboardCurrentViews",
] as const;

type SourceCollection = typeof sourceCollections[number];
type CandidateCollection = typeof candidateCollections[number];
type MutableInventoryCandidateCounts = Record<CandidateCollection, number>;
type SourceDocuments = ReadonlyMap<SourceCollection, readonly QueryDocumentSnapshot[]>;

export async function inventoryLeaderboardSeedRuns(
  firestore: Firestore,
  projectId: string,
): Promise<InventorySummary> {
  const [users, profiles, contributions, manifests, ranks, views] = await Promise.all([
    markerDocuments(firestore, "users"), markerDocuments(firestore, "userProfiles"),
    markerDocuments(firestore, "leaderboardContributions"),
    firestore.collection("leaderboardSeedRuns").get(),
    mockProjectionDocuments(firestore, "leaderboardUserRanks"),
    mockProjectionDocuments(firestore, "leaderboardCurrentViews"),
  ]);
  const sources: SourceDocuments = new Map<SourceCollection, readonly QueryDocumentSnapshot[]>([
    ["users", users], ["userProfiles", profiles], ["leaderboardContributions", contributions],
  ]);
  const sourceIndex = indexSourceDocuments(sources);
  const countsByRunId = sourceIndex.countsByRunId;
  indexProjectionDocuments(countsByRunId, ranks, "leaderboardUserRanks");
  indexProjectionDocuments(countsByRunId, views, "leaderboardCurrentViews");
  const manifestsByRunId = new Map(manifests.docs.map((document) => [document.id, document]));
  const runIds = new Set([
    ...manifests.docs.map((document) => document.id), ...countsByRunId.keys(),
  ]);
  const runs = [...runIds].sort().map((runId) => inventoryRun({
    projectId,
    runId,
    manifest: manifestsByRunId.get(runId),
    candidateCounts: countsByRunId.get(runId) ?? emptyCandidateCounts(),
  }));
  const issues = [...sourceIndex.invalidMarkerIssues, ...runs.flatMap((run) => run.issues)];
  return { action: "inventory", projectId, status: issues.length === 0 ? "ready" : "blocked", runs, issues };
}

function inventoryRun(input: {
  readonly projectId: string;
  readonly runId: string;
  readonly manifest: QueryDocumentSnapshot | undefined;
  readonly candidateCounts: InventoryCandidateCounts;
}): InventoryRun {
  const manifestStatus = stringOrNull(input.manifest?.get("status"));
  const periodKey = stringOrNull(input.manifest?.get("periodKey"));
  const regionCount = numberOrNull(input.manifest?.get("regionCount"));
  const usersPerRegion = numberOrNull(input.manifest?.get("usersPerRegion"));
  const profileCount = numberOrNull(input.manifest?.get("profileCount"));
  const issues = manifestIssues(input, input.candidateCounts);
  const uidPrefix = `lbmock_${input.runId}_`;
  return {
    runId: input.runId, uidPrefix, users: input.candidateCounts.users,
    profiles: input.candidateCounts.userProfiles,
    contributions: input.candidateCounts.leaderboardContributions,
    ranks: input.candidateCounts.leaderboardUserRanks,
    currentViews: input.candidateCounts.leaderboardCurrentViews,
    candidateCounts: input.candidateCounts,
    manifestStatus,
    periodKey,
    cleanupInventoryFingerprint: cleanupInventoryFingerprint({
      projectId: input.projectId,
      runId: input.runId,
      uidPrefix,
      periodKey,
      manifestStatus,
      regionCount,
      usersPerRegion,
      profileCount,
      candidateCounts: input.candidateCounts,
    }),
    status: issues.length === 0 ? "ready" : "blocked",
    issues,
  };
}

function manifestIssues(input: {
  readonly projectId: string;
  readonly runId: string;
  readonly manifest: QueryDocumentSnapshot | undefined;
}, counts: InventoryCandidateCounts): readonly InventoryIssue[] {
  const manifest = input.manifest;
  if (manifest === undefined || manifest.get("runId") !== input.runId) {
    return [issue("orphan_markers", "leaderboardSeedRuns", input.runId, 1)];
  }
  const issues: InventoryIssue[] = [];
  if (manifest.get("projectId") !== input.projectId) issues.push(issue("manifest_project_mismatch", "leaderboardSeedRuns", input.runId, 1));
  const profileCount = numberOrNull(manifest.get("profileCount"));
  const regionCount = numberOrNull(manifest.get("regionCount"));
  if (profileCount === null || regionCount === null || profileCount < regionCount) {
    return [...issues, issue("manifest_count_mismatch", "leaderboardSeedRuns", input.runId, 1)];
  }
  const expected = manifest.get("status") === "cleaned"
    ? emptyCandidateCounts()
    : {
      users: profileCount,
      userProfiles: profileCount,
      leaderboardContributions: profileCount,
      leaderboardUserRanks: profileCount - regionCount,
      leaderboardCurrentViews: profileCount,
    };
  for (const collection of candidateCollections) {
    if (counts[collection] !== expected[collection]) {
      issues.push(issue("manifest_candidate_count_mismatch", collection, input.runId, 1));
    }
  }
  return issues;
}

function indexSourceDocuments(sources: SourceDocuments): {
  readonly countsByRunId: Map<string, MutableInventoryCandidateCounts>;
  readonly invalidMarkerIssues: readonly InventoryIssue[];
} {
  const countsByRunId = new Map<string, MutableInventoryCandidateCounts>();
  const invalidCountByCollection = new Map<SourceCollection, number>();
  for (const collection of sourceCollections) {
    for (const document of sources.get(collection) ?? []) {
      const runId = document.get("mockSeedRunId");
      if (isRunId(runId)) {
        incrementCandidateCount(countsByRunId, runId, collection);
      } else {
        invalidCountByCollection.set(collection, (invalidCountByCollection.get(collection) ?? 0) + 1);
      }
    }
  }
  const invalidMarkerIssues = sourceCollections.flatMap((collection) => {
    const count = invalidCountByCollection.get(collection) ?? 0;
    return count === 0 ? [] : [issue("missing_or_invalid_run_id", collection, null, count)];
  });
  return { countsByRunId, invalidMarkerIssues };
}

function indexProjectionDocuments(
  countsByRunId: Map<string, MutableInventoryCandidateCounts>,
  documents: readonly QueryDocumentSnapshot[],
  collection: "leaderboardUserRanks" | "leaderboardCurrentViews",
): void {
  for (const document of documents) {
    const runId = projectionRunId(document.id);
    if (runId !== null) incrementCandidateCount(countsByRunId, runId, collection);
  }
}

function projectionRunId(documentId: string): string | null {
  const match = /^lbmock_([a-z0-9][a-z0-9-]{2,47})_/.exec(documentId);
  return match?.[1] ?? null;
}

function incrementCandidateCount(
  countsByRunId: Map<string, MutableInventoryCandidateCounts>,
  runId: string,
  collection: CandidateCollection,
): void {
  const counts = countsByRunId.get(runId) ?? emptyCandidateCounts();
  counts[collection] += 1;
  countsByRunId.set(runId, counts);
}

function emptyCandidateCounts(): MutableInventoryCandidateCounts {
  return {
    users: 0,
    userProfiles: 0,
    leaderboardContributions: 0,
    leaderboardUserRanks: 0,
    leaderboardCurrentViews: 0,
  };
}

function markerDocuments(firestore: Firestore, collection: string): Promise<readonly QueryDocumentSnapshot[]> {
  return firestore.collection(collection).where("isMockData", "==", true).get().then((snapshot) => snapshot.docs);
}

function mockProjectionDocuments(firestore: Firestore, collection: string): Promise<readonly QueryDocumentSnapshot[]> {
  return firestore.collection(collection).where(FieldPath.documentId(), ">=", "lbmock_").where(FieldPath.documentId(), "<=", "lbmock_\uf8ff").get().then((snapshot) => snapshot.docs);
}

function isRunId(value: unknown): value is string {
  return typeof value === "string" && /^[a-z0-9][a-z0-9-]{2,47}$/.test(value);
}

function stringOrNull(value: unknown): string | null { return typeof value === "string" ? value : null; }
function numberOrNull(value: unknown): number | null { return typeof value === "number" && Number.isInteger(value) ? value : null; }
function issue(code: string, collection: string | null, runId: string | null, count: number): InventoryIssue { return { code, collection, runId, count }; }
