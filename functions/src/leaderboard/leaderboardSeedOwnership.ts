import { FieldPath, type Firestore, type QueryDocumentSnapshot } from "firebase-admin/firestore";
import { type SeedDataset } from "./leaderboardSeedDataset.js";

export const seedSourceCollections = [
  "users",
  "userProfiles",
  "leaderboardContributions",
] as const;

export type SeedDocumentIds = {
  readonly users: readonly string[];
  readonly userProfiles: readonly string[];
  readonly leaderboardContributions: readonly string[];
  readonly leaderboardUserRanks: readonly string[];
  readonly leaderboardCurrentViews: readonly string[];
};

export function expectedSeedDocumentIds(seedDataset: SeedDataset): SeedDocumentIds {
  const { dataset } = seedDataset;
  // Premium parity: subscription tier no longer decides who is projected. The
  // planner projects a record if and only if it scored, so both ranks and
  // current views follow the score, not the tier.
  const scoringUids = dataset.records
    .filter((record) => record.contribution.scoreXp > 0)
    .map((record) => record.uid);
  const allUids = dataset.records.map((record) => record.uid);
  return {
    users: allUids,
    userProfiles: allUids,
    leaderboardContributions: allUids.map((uid) => `${uid}_monthly_${dataset.periodKey}`),
    leaderboardUserRanks: scoringUids.map((uid) => `${uid}_monthly_${dataset.periodKey}`),
    leaderboardCurrentViews: scoringUids,
  };
}

export function assertExactDocumentIds(
  collection: keyof SeedDocumentIds,
  documents: readonly QueryDocumentSnapshot[],
  expectedIds: readonly string[],
): void {
  const actualIds = new Set(documents.map((document) => document.id));
  const expected = new Set(expectedIds);
  if (
    actualIds.size !== expected.size ||
    [...actualIds].some((id) => !expected.has(id))
  ) {
    throw new Error(`exact id set mismatch: ${collection}`);
  }
}

export function projectionDocuments(
  firestore: Firestore,
  collection: "leaderboardUserRanks" | "leaderboardCurrentViews",
  uidPrefix: string,
): Promise<readonly QueryDocumentSnapshot[]> {
  return firestore.collection(collection)
    .where(FieldPath.documentId(), ">=", uidPrefix)
    .where(FieldPath.documentId(), "<=", `${uidPrefix}\uf8ff`)
    .get()
    .then((snapshot) => snapshot.docs);
}

export async function expectedSourceDocuments(
  firestore: Firestore,
  seedDataset: SeedDataset,
): Promise<readonly QueryDocumentSnapshot[]> {
  const documentIds = expectedSeedDocumentIds(seedDataset);
  const refs = seedSourceCollections.flatMap((collection) =>
    documentIds[collection].map((id) => firestore.collection(collection).doc(id)),
  );
  const snapshots = await firestore.getAll(...refs);
  return snapshots.filter((snapshot): snapshot is QueryDocumentSnapshot => snapshot.exists);
}

export async function expectedProjectionDocuments(
  firestore: Firestore,
  seedDataset: SeedDataset,
): Promise<readonly QueryDocumentSnapshot[]> {
  const ids = expectedSeedDocumentIds(seedDataset);
  const refs = [
    ...ids.leaderboardUserRanks.map((id) => firestore.collection("leaderboardUserRanks").doc(id)),
    ...ids.leaderboardCurrentViews.map((id) => firestore.collection("leaderboardCurrentViews").doc(id)),
  ];
  // A dataset can legitimately project nothing — seeding one user per region
  // makes that user the zero-score record, and the planner drops it — and
  // getAll() rejects an empty argument list.
  if (refs.length === 0) {
    return [];
  }
  const snapshots = await firestore.getAll(...refs);
  return snapshots.filter((snapshot): snapshot is QueryDocumentSnapshot => snapshot.exists);
}
