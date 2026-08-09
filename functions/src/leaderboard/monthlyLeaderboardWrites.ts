import type { DocumentReference, Firestore } from "firebase-admin/firestore";

const maxBatchOperations = 400;

export type WriteOperation =
  | {
      readonly kind: "set";
      readonly ref: DocumentReference;
      readonly data: FirebaseFirestore.DocumentData;
    }
  | {
      readonly kind: "delete";
      readonly ref: DocumentReference;
    };

export async function commitOperations(
  firestore: Firestore,
  operations: readonly WriteOperation[],
): Promise<void> {
  for (
    let index = 0;
    index < operations.length;
    index += maxBatchOperations
  ) {
    const batch = firestore.batch();
    for (const operation of operations.slice(
      index,
      index + maxBatchOperations,
    )) {
      if (operation.kind === "set") {
        batch.set(operation.ref, operation.data);
      } else {
        batch.delete(operation.ref);
      }
    }
    await batch.commit();
  }
}
export async function cleanupExpiredProjections(
  firestore: Firestore,
  retainedPeriods: ReadonlySet<string>,
): Promise<void> {
  const collections = [
    "leaderboardSnapshots",
    "leaderboardUserRanks",
    "leaderboardAggregationLocks",
  ];
  const operations: WriteOperation[] = [];
  for (const collection of collections) {
    const snapshot = await firestore
      .collection(collection)
      .where("periodType", "==", "monthly")
      .get();
    for (const document of snapshot.docs) {
      const periodKey = readString(document.data()["periodKey"]);
      if (periodKey !== null && !retainedPeriods.has(periodKey)) {
        operations.push({ kind: "delete", ref: document.ref });
      }
    }
  }
  await commitOperations(firestore, operations);
}

function readString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}
