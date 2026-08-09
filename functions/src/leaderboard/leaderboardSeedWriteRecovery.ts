import type { InventoryCandidateCounts } from "./leaderboardSeedCommandTypes.js";

const maxAtomicBatchOperations = 500;

export function assertAtomicSeedBatchLimit(operationCount: number): void {
  if (operationCount > maxAtomicBatchOperations) {
    throw new Error(`atomic seed batch limit exceeded: ${operationCount} writes`);
  }
}

export function hasSafeCleanupCandidateIds(
  actualIds: readonly string[],
  expectedIds: readonly string[],
  allowSubset: boolean,
): boolean {
  const actual = new Set(actualIds);
  const expected = new Set(expectedIds);
  return (allowSubset || actual.size === expected.size) &&
    [...actual].every((id) => expected.has(id));
}

export function candidateDocumentCounts(
  documents: Readonly<Record<keyof InventoryCandidateCounts, readonly unknown[]>>,
): InventoryCandidateCounts {
  return {
    users: documents.users.length,
    userProfiles: documents.userProfiles.length,
    leaderboardContributions: documents.leaderboardContributions.length,
    leaderboardUserRanks: documents.leaderboardUserRanks.length,
    leaderboardCurrentViews: documents.leaderboardCurrentViews.length,
  };
}

export function hasExpectedCandidateCounts(
  value: unknown,
  expected: Readonly<Record<string, number>>,
): boolean {
  return typeof value === "object" && value !== null &&
    Object.entries(expected).every(([collection, count]) => Reflect.get(value, collection) === count);
}

export function totalCandidateCount(counts: Readonly<Record<string, number>>): number {
  return Object.values(counts).reduce((total, count) => total + count, 0);
}

export function cleanupExpectedDocumentCount(
  candidateCounts: unknown,
  documentCount: unknown,
  expectedCounts: Readonly<Record<string, number>>,
): number | null {
  return hasExpectedCandidateCounts(candidateCounts, expectedCounts) &&
    typeof documentCount === "number" &&
    documentCount === totalCandidateCount(expectedCounts)
    ? documentCount
    : null;
}

export function hasExpectedSourceMarkers(
  expectedDocuments: readonly { readonly collection: string; readonly id: string }[],
  actualDocuments: Readonly<Record<string, readonly { readonly id: string }[]>>,
  collections: readonly string[],
): boolean {
  return collections.every((collection) => {
    const expected = expectedDocuments.filter((document) => document.collection === collection);
    const actual = actualDocuments[collection] ?? [];
    return expected.length === actual.length && expected.every((document) => actual.some((candidate) => candidate.id === document.id));
  });
}

export async function closeBulkWriterAfterObservedWrites(
  writer: { readonly close: () => Promise<void> },
  writeOperations: readonly Promise<unknown>[],
): Promise<void> {
  const close = writer.close();
  const results = await Promise.allSettled(writeOperations);
  await close;
  const failed = results.find((result) => result.status === "rejected");
  if (failed !== undefined && failed.status === "rejected") {
    throw failed.reason;
  }
}
