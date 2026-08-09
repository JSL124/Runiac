import { type Firestore, type QueryDocumentSnapshot } from "firebase-admin/firestore";
import { claimCleanupLease, newCleanupLeaseId, releaseCleanupLease } from "./leaderboardSeedCleanupLease.js";
import { assertInventoryFingerprint, assertVerifiedReplacementRun, currentCleanupInventoryFingerprint, matchesManifestRegions } from "./leaderboardSeedCleanupAuthorization.js";
import { type CleanupPreview, type InventoryIssue } from "./leaderboardSeedCommandTypes.js";
import { type SeedDataset } from "./leaderboardSeedDataset.js";
import { expectedSeedDocumentIds, expectedProjectionDocuments, expectedSourceDocuments, projectionDocuments, seedSourceCollections } from "./leaderboardSeedOwnership.js";
import { currentSingaporeMonthKey } from "./monthlyLeaderboardPeriod.js";
import { refreshMonthlyLeaderboardSnapshots } from "./monthlyLeaderboardWriter.js";
import {
  assertAtomicSeedBatchLimit,
  candidateDocumentCounts,
  cleanupExpectedDocumentCount,
  hasExpectedSourceMarkers,
  hasSafeCleanupCandidateIds,
  totalCandidateCount,
  closeBulkWriterAfterObservedWrites,
} from "./leaderboardSeedWriteRecovery.js";

export async function seedLeaderboardDataset(input: {
  readonly firestore: Firestore;
  readonly projectId: string;
  readonly seedDataset: SeedDataset;
}): Promise<Record<string, unknown>> {
  await assertSeedPreflight(input.firestore, input.seedDataset);
  const { dataset } = input.seedDataset;
  const manifestRef = input.firestore.collection("leaderboardSeedRuns").doc(dataset.runId);
  const startedAt = new Date().toISOString();
  const sourceWriteCount = dataset.records.length * 3;
  assertAtomicSeedBatchLimit(sourceWriteCount + 1);
  const batch = input.firestore.batch();
  batch.create(manifestRef, {
    runId: dataset.runId,
    projectId: input.projectId,
    periodKey: dataset.periodKey,
    regionIds: input.seedDataset.regionIds,
    usersPerRegion: dataset.usersPerRegion,
    regionCount: dataset.regionCount,
    profileCount: dataset.records.length,
    status: "seeded",
    startedAt,
    completedAt: startedAt,
    updatedAt: startedAt,
    writeCount: sourceWriteCount,
  });
  for (const record of dataset.records) {
    batch.create(input.firestore.collection("users").doc(record.uid), record.user);
    batch.create(input.firestore.collection("userProfiles").doc(record.uid), record.profile);
    batch.create(
      input.firestore.collection("leaderboardContributions")
        .doc(`${record.uid}_monthly_${dataset.periodKey}`),
      record.contribution,
    );
  }
  await batch.commit();
  return { status: "seeded", profileCount: dataset.records.length, writeCount: sourceWriteCount };
}

export async function previewLeaderboardCleanup(input: {
  readonly firestore: Firestore;
  readonly projectId: string;
  readonly seedDataset: SeedDataset;
}): Promise<CleanupPreview> {
  const [documents, manifest] = await Promise.all([
    cleanupDocuments(input.firestore, input.seedDataset),
    input.firestore.collection("leaderboardSeedRuns").doc(input.seedDataset.dataset.runId).get(),
  ]);
  const issues = await cleanupIssues({ ...input, documents });
  const candidateCounts = candidateDocumentCounts(documents);
  return {
    action: "preview-cleanup",
    projectId: input.projectId,
    runId: input.seedDataset.dataset.runId,
    periodKey: input.seedDataset.dataset.periodKey,
    uidPrefix: input.seedDataset.uidPrefix,
    status: issues.length === 0 ? "ready" : "blocked",
    sourceDocumentCount: candidateCounts.users + candidateCounts.userProfiles + candidateCounts.leaderboardContributions,
    rankDocumentCount: candidateCounts.leaderboardUserRanks,
    currentViewDocumentCount: candidateCounts.leaderboardCurrentViews,
    candidateCounts,
    cleanupInventoryFingerprint: currentCleanupInventoryFingerprint({
      projectId: input.projectId, seedDataset: input.seedDataset, manifest, candidateCounts,
    }),
    issues,
  };
}

export async function cleanupLeaderboardSeedRun(input: {
  readonly firestore: Firestore;
  readonly projectId: string;
  readonly seedDataset: SeedDataset;
  readonly confirmInventory: string | null;
  readonly replacementRunId: string | null;
}): Promise<Record<string, unknown>> {
  await assertVerifiedReplacementRun({
    firestore: input.firestore,
    projectId: input.projectId,
    targetRunId: input.seedDataset.dataset.runId,
    replacementRunId: input.replacementRunId,
  });
  const preview = await previewLeaderboardCleanup(input);
  if (preview.status === "blocked") throw new Error("cleanup validation blocked");
  assertInventoryFingerprint(input.confirmInventory, preview.cleanupInventoryFingerprint);
  const cleanupLeaseId = newCleanupLeaseId();
  await claimCleanupLease(input.firestore, input.seedDataset.dataset.periodKey, cleanupLeaseId);
  try {
    const documents = await cleanupDocuments(input.firestore, input.seedDataset);
    const issues = await cleanupIssues({ ...input, documents });
    if (issues.length > 0) {
      throw new Error("cleanup validation changed after lease acquisition");
    }
    const manifestRef = input.firestore.collection("leaderboardSeedRuns").doc(input.seedDataset.dataset.runId);
    const manifest = await manifestRef.get();
    const expectedCounts = candidateDocumentCounts(expectedSeedDocumentIds(input.seedDataset));
    const cleanupPending = manifest.get("status") === "cleanup_pending";
    if (cleanupPending && cleanupExpectedDocumentCount(manifest.get("cleanupExpectedCandidateCounts"), manifest.get("cleanupExpectedDocumentCount"), expectedCounts) === null) throw new Error("cleanup expected candidate counts are invalid");
    await manifestRef.set({
      status: "cleanup_pending",
      cleanupPendingAt: new Date().toISOString(),
      ...(cleanupPending ? {} : {
        cleanupExpectedCandidateCounts: expectedCounts,
        cleanupExpectedDocumentCount: totalCandidateCount(expectedCounts),
      }),
      updatedAt: new Date().toISOString(),
    }, { merge: true });
    const writer = input.firestore.bulkWriter();
    const writeOperations: Promise<unknown>[] = [];
    for (const document of allDocuments(documents)) {
      writeOperations.push(writer.delete(document.ref));
    }
    await closeBulkWriterAfterObservedWrites(writer, writeOperations);
  } finally {
    await releaseCleanupLease(input.firestore, input.seedDataset.dataset.periodKey, cleanupLeaseId);
  }
  // Refresh the LIVE period, never the seed run's own period. Unlike the seed
  // and refresh actions, cleanup is deliberately exempt from
  // `assertProductionDatasetScope`, so a cleanup may legitimately name a past
  // `--period`. `refreshMonthlyLeaderboardSnapshots` is not period-scoped in
  // its side effects: it repoints `leaderboardPeriods/monthly_current` at
  // whatever key it is handed and then prunes every projection outside
  // `retainedPeriodKeys(thatKey)`. Passing a past key therefore pointed the
  // app at a finished month and deleted the live month's snapshots and ranks
  // — the same defect already closed in `leaderboardAdminCommand.ts`, which
  // derives its key from `currentSingaporeMonthKey` for exactly this reason.
  // The seed run's own projection documents are removed by the id-scoped bulk
  // delete above, so nothing depends on re-aggregating the historical period.
  const livePeriodKey = currentSingaporeMonthKey(new Date());
  const refresh = await refreshMonthlyLeaderboardSnapshots(
    input.firestore,
    livePeriodKey,
    { buildId: `cleanup_${input.seedDataset.dataset.runId}_${livePeriodKey}` },
  );
  // A lost lease is a FAILURE here, deliberately. Targeting the live period
  // means this refresh contends with the hourly `refreshLeaderboardSnapshots`
  // schedule, and when the seed itself covers the live period that holder may
  // already have read the synthetic contributions before the deletes above
  // committed — so it can republish the very rows this cleanup removed. It does
  // not reconcile the deletion, and reporting `cleaned` while mock rows are
  // still visible in live snapshots is the worst available outcome.
  //
  // Throwing after the deletes have committed is not a stranded state: the
  // manifest is left at `cleanup_pending`, which `cleanupIssues` and
  // `hasSafeCleanupCandidateIds` explicitly accept as a resumable status, and
  // the deletes are id-scoped and idempotent. Re-running the cleanup finishes
  // the refresh and marks it `cleaned`.
  if (refresh.status !== "completed") {
    throw new Error(
      `cleanup refresh did not complete (status: ${refresh.status}); re-run cleanup to finish it`,
    );
  }
  const manifestRef = input.firestore.collection("leaderboardSeedRuns").doc(input.seedDataset.dataset.runId);
  const expectedCounts = candidateDocumentCounts(expectedSeedDocumentIds(input.seedDataset));
  const manifest = await manifestRef.get();
  const deletedDocumentCount = cleanupExpectedDocumentCount(manifest.get("cleanupExpectedCandidateCounts"), manifest.get("cleanupExpectedDocumentCount"), expectedCounts);
  if (deletedDocumentCount === null) throw new Error("cleanup expected candidate counts are invalid");
  await manifestRef.set({
    status: "cleaned",
    cleanedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    deletedDocumentCount,
  }, { merge: true });
  return { status: "cleaned", deletedDocumentCount, refresh };
}

type CleanupDocuments = Readonly<Record<keyof ReturnType<typeof expectedSeedDocumentIds>, readonly QueryDocumentSnapshot[]>>;

async function assertSeedPreflight(firestore: Firestore, seedDataset: SeedDataset): Promise<void> {
  const manifest = await firestore.collection("leaderboardSeedRuns").doc(seedDataset.dataset.runId).get();
  if (manifest.exists && manifest.get("status") !== "cleaned") {
    throw new Error(`seed run already exists: ${seedDataset.dataset.runId}`);
  }
  const [expectedSources, expectedProjections, documents] = await Promise.all([
    expectedSourceDocuments(firestore, seedDataset),
    expectedProjectionDocuments(firestore, seedDataset),
    cleanupDocuments(firestore, seedDataset),
  ]);
  if (expectedSources.length > 0 || expectedProjections.length > 0 || allDocuments(documents).length > 0) {
    throw new Error("seed collision: synthetic identifiers already exist");
  }
}

async function cleanupDocuments(firestore: Firestore, seedDataset: SeedDataset): Promise<CleanupDocuments> {
  const ids = expectedSeedDocumentIds(seedDataset);
  const [users, profiles, contributions, ranks, views] = await Promise.all([
    firestore.collection("users").where("mockSeedRunId", "==", seedDataset.dataset.runId).get(),
    firestore.collection("userProfiles").where("mockSeedRunId", "==", seedDataset.dataset.runId).get(),
    firestore.collection("leaderboardContributions").where("mockSeedRunId", "==", seedDataset.dataset.runId).get(),
    projectionDocuments(firestore, "leaderboardUserRanks", seedDataset.uidPrefix),
    projectionDocuments(firestore, "leaderboardCurrentViews", seedDataset.uidPrefix),
  ]);
  return {
    users: users.docs,
    userProfiles: profiles.docs,
    leaderboardContributions: contributions.docs,
    leaderboardUserRanks: ranks,
    leaderboardCurrentViews: views,
  };
}

async function cleanupIssues(input: {
  readonly firestore: Firestore;
  readonly projectId: string;
  readonly seedDataset: SeedDataset;
  readonly documents: CleanupDocuments;
}): Promise<readonly InventoryIssue[]> {
  const { dataset } = input.seedDataset;
  const manifest = await input.firestore.collection("leaderboardSeedRuns").doc(dataset.runId).get();
  if (!manifest.exists || manifest.get("runId") !== dataset.runId) {
    return [issue("manifest_missing", "leaderboardSeedRuns", dataset.runId, 1)];
  }
  const issues: InventoryIssue[] = [];
  const cleanupPending = manifest.get("status") === "cleanup_pending";
  if (!cleanupPending && manifest.get("status") !== "seeded" && manifest.get("status") !== "verified") issues.push(issue("manifest_status_not_cleanable", "leaderboardSeedRuns", dataset.runId, 1));
  if (manifest.get("projectId") !== input.projectId) issues.push(issue("manifest_project_mismatch", "leaderboardSeedRuns", dataset.runId, 1));
  if (manifest.get("periodKey") !== dataset.periodKey) issues.push(issue("manifest_period_mismatch", "leaderboardSeedRuns", dataset.runId, 1));
  if (!matchesManifestRegions(manifest.get("regionIds"), manifest.get("regionCount"), input.seedDataset)) issues.push(issue("manifest_region_mismatch", "leaderboardSeedRuns", dataset.runId, 1));
  if (manifest.get("usersPerRegion") !== dataset.usersPerRegion || manifest.get("regionCount") !== dataset.regionCount || manifest.get("profileCount") !== dataset.records.length) {
    issues.push(issue("manifest_count_mismatch", "leaderboardSeedRuns", dataset.runId, 1));
  }
  const ids = expectedSeedDocumentIds(input.seedDataset);
  if (cleanupPending && !hasExpectedSourceMarkers(
    (await expectedSourceDocuments(input.firestore, input.seedDataset)).map((document) => ({ collection: document.ref.parent.id, id: document.id })),
    input.documents,
    seedSourceCollections,
  )) {
    issues.push(issue("source_marker_mismatch", "leaderboardSeedRuns", dataset.runId, 1));
  }
  for (const collection of seedSourceCollections) {
    if (!hasSafeCleanupCandidateIds(input.documents[collection].map((document) => document.id), ids[collection], cleanupPending)) {
      issues.push(issue("exact_source_id_set_mismatch", collection, dataset.runId, 1));
    }
  }
  for (const collection of ["leaderboardUserRanks", "leaderboardCurrentViews"] as const) {
    if (!hasSafeCleanupCandidateIds(input.documents[collection].map((document) => document.id), ids[collection], cleanupPending)) {
      issues.push(issue("exact_projection_id_set_mismatch", collection, dataset.runId, 1));
    }
  }
  for (const document of allDocuments(input.documents)) {
    if (isSeedSourceCollection(document.ref.parent.id) && (document.get("isMockData") !== true || document.get("mockSeedRunId") !== dataset.runId)) {
      issues.push(issue("source_marker_mismatch", document.ref.parent.id, dataset.runId, 1));
    }
    if (document.ref.parent.id === "leaderboardContributions") {
      const uid = document.id.slice(0, -`_monthly_${dataset.periodKey}`.length);
      if (document.get("ownerUid") !== uid || document.get("periodKey") !== dataset.periodKey) {
        issues.push(issue("contribution_owner_or_period_mismatch", document.ref.parent.id, dataset.runId, 1));
      }
    }
  }
  for (const document of input.documents.leaderboardUserRanks) {
    const ownerUid = document.get("ownerUid");
    if (typeof ownerUid !== "string" || document.id !== `${ownerUid}_monthly_${dataset.periodKey}` || document.get("periodKey") !== dataset.periodKey) issues.push(issue("projection_owner_or_period_mismatch", "leaderboardUserRanks", dataset.runId, 1));
  }
  for (const document of input.documents.leaderboardCurrentViews) {
    if (document.get("ownerUid") !== document.id || document.get("periodKey") !== dataset.periodKey) issues.push(issue("projection_owner_or_period_mismatch", "leaderboardCurrentViews", dataset.runId, 1));
  }
  return issues;
}

function allDocuments(documents: CleanupDocuments): readonly QueryDocumentSnapshot[] {
  return Object.values(documents).flat();
}

function isSeedSourceCollection(value: string): boolean {
  return seedSourceCollections.some((collection) => collection === value);
}

function issue(code: string, collection: string | null, runId: string | null, count: number): InventoryIssue {
  return { code, collection, runId, count };
}
