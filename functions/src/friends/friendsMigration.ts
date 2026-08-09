import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { friendError, FRIEND_REASON } from "./friendsErrors.js";
import { dataOf, requireAuthUid, stringOrUndefined } from "./friendsParsing.js";
import { claimRef, profileRef } from "./friendsPaths.js";
import {
  buildFriendIdentity,
  preflightNicknameClaimMigration,
  type NicknameMigrationClaim,
  type NicknameMigrationProfile,
} from "./nickname.js";
import type { FriendsCallableRequest, FriendsDependencies } from "./friendsTypes.js";
import { isPlatformAdminRole } from "../security/roles.js";
import { assertAccountNotSuspended } from "../security/accountStatus.js";

const MAX_MIGRATION_WRITES = 500;

export async function migrateUnicodeNicknameClaims(
  dependencies: FriendsDependencies,
  request: FriendsCallableRequest,
) {
  const uid = requireAuthUid(request);
  const at = Timestamp.fromMillis(dependencies.nowMs());
  return dependencies.firestore.runTransaction(async (transaction) => {
    const [adminSnapshot, profileSnapshots, claimSnapshots] = await Promise.all([
      transaction.get(dependencies.firestore.doc(`users/${uid}`)),
      transaction.get(dependencies.firestore.collection("userProfiles")),
      transaction.get(dependencies.firestore.collection("nicknameClaims")),
    ]);
    // Defence-in-depth (see accountStatus.ts): reuses this transaction's own
    // users/{uid} read (adminSnapshot) rather than adding a second read.
    assertAccountNotSuspended(dataOf(adminSnapshot));
    if (!isPlatformAdminRole(dataOf(adminSnapshot))) {
      throw friendError(FRIEND_REASON.NOT_PLATFORM_ADMIN);
    }
    const profiles = readProfiles(profileSnapshots.docs.map((snapshot) => ({ id: snapshot.id, data: dataOf(snapshot) })));
    const claims = readClaims(claimSnapshots.docs.map((snapshot) => ({ id: snapshot.id, data: dataOf(snapshot) })));
    const plan = preflightNicknameClaimMigration(profiles, claims);
    if (plan.kind === "invalid") throw friendError(FRIEND_REASON.NICKNAME_MIGRATION_INVALID);
    const writeCount = plan.rows.reduce(
      (count, row) => count + 2 + (row.sourceClaimId === row.indexKey ? 0 : 1),
      0,
    );
    if (writeCount > MAX_MIGRATION_WRITES) throw friendError(FRIEND_REASON.MIGRATION_TOO_LARGE);
    for (const row of plan.rows) {
      const identity = buildFriendIdentity(row.uid, row.nickname);
      transaction.set(claimRef(dependencies.firestore, row.indexKey), {
        ownerUid: row.uid,
        nicknameCanonical: row.canonical,
        nicknameDisplay: row.nickname,
        nicknameIndexKey: row.indexKey,
        updatedAt: at,
      });
      transaction.update(profileRef(dependencies.firestore, row.uid), {
        nickname: row.nickname,
        nicknameCanonical: row.canonical,
        nicknameIndexKey: row.indexKey,
        nicknameKey: FieldValue.delete(),
        displayName: identity.displayName,
        avatarInitials: identity.avatarInitials,
        socialDiscoveryStatus: row.socialDiscoveryStatus,
        socialListSortKey: row.canonical,
        updatedAt: at,
      });
      if (row.sourceClaimId !== row.indexKey) transaction.delete(claimRef(dependencies.firestore, row.sourceClaimId));
    }
    return { migrated: plan.rows.length };
  });
}

function readProfiles(records: readonly { readonly id: string; readonly data: Readonly<Record<string, unknown>> }[]): NicknameMigrationProfile[] {
  const profiles: NicknameMigrationProfile[] = [];
  for (const record of records) {
    const nickname = record.data["nickname"];
    if (typeof nickname !== "string") continue;
    const legacyNicknameKey = stringOrUndefined(record.data["nicknameKey"]);
    const nicknameIndexKey = stringOrUndefined(record.data["nicknameIndexKey"]);
    const nicknameCanonical = stringOrUndefined(record.data["nicknameCanonical"]);
    const socialDiscoveryStatus = stringOrUndefined(record.data["socialDiscoveryStatus"]);
    profiles.push({
      uid: record.id,
      nickname,
      ...(legacyNicknameKey === undefined ? {} : { legacyNicknameKey }),
      ...(nicknameIndexKey === undefined ? {} : { nicknameIndexKey }),
      ...(nicknameCanonical === undefined ? {} : { nicknameCanonical }),
      ...(socialDiscoveryStatus === undefined ? {} : { socialDiscoveryStatus }),
    });
  }
  return profiles;
}

function readClaims(records: readonly { readonly id: string; readonly data: Readonly<Record<string, unknown>> }[]): NicknameMigrationClaim[] {
  const claims: NicknameMigrationClaim[] = [];
  for (const record of records) {
    const ownerUid = record.data["ownerUid"];
    if (typeof ownerUid !== "string") throw friendError(FRIEND_REASON.NICKNAME_MIGRATION_INVALID);
    const nicknameCanonical = stringOrUndefined(record.data["nicknameCanonical"]);
    claims.push({ id: record.id, ownerUid, ...(nicknameCanonical === undefined ? {} : { nicknameCanonical }) });
  }
  return claims;
}
