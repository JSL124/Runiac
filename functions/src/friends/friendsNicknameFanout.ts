import type { DocumentReference, Firestore, Transaction } from "firebase-admin/firestore";

import type { FriendIdentity } from "./nickname.js";

const SOCIAL_IDENTITY_COLLECTION_GROUPS = ["friends", "friendRequests", "blockedUsers"] as const;

// Firestore permits 500 transaction writes; reserve 3 for the target claim, profile, and old-claim deletion.
export const NICKNAME_RENAME_MAX_FANOUT_ROWS = 500 - 3;

export async function nicknameFanoutReferences(
  firestore: Firestore,
  transaction: Transaction,
  uid: string,
): Promise<readonly DocumentReference[]> {
  const snapshots = await Promise.all(SOCIAL_IDENTITY_COLLECTION_GROUPS.map((collectionGroup) =>
    transaction.get(
      firestore.collectionGroup(collectionGroup)
        .where("uid", "==", uid)
        .limit(NICKNAME_RENAME_MAX_FANOUT_ROWS + 1),
    )
  ));
  const referencesByPath = new Map<string, DocumentReference>();
  for (const snapshot of snapshots) {
    for (const document of snapshot.docs) referencesByPath.set(document.ref.path, document.ref);
  }
  return [...referencesByPath.values()];
}

export function updateNicknameFanout(
  transaction: Transaction,
  references: readonly DocumentReference[],
  identity: FriendIdentity,
  canonicalNickname: string,
): void {
  for (const reference of references) {
    transaction.update(reference, {
      nickname: identity.nickname,
      displayName: identity.displayName,
      avatarInitials: identity.avatarInitials,
      listSortKey: canonicalNickname,
    });
  }
}
