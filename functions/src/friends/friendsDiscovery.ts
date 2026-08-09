import { friendError, FRIEND_REASON } from "./friendsErrors.js";
import { dataOf, readNickname, requireAuthUid } from "./friendsParsing.js";
import { blockRef, claimRef, profileRef, rateRef } from "./friendsPaths.js";
import { socialProfile } from "./friendsProfiles.js";
import { nextSearchAttemptMs, writeSearchRate } from "./friendsRateLimits.js";
import { nicknameIndexKey } from "./nickname.js";
import type { FriendsCallableRequest, FriendsDependencies } from "./friendsTypes.js";
import { resolveProfileLevelDisplay } from "../progression/profileLevelDisplay.js";
import { resolveProfileAvatarDisplay } from "../profile/profileIdentityDisplay.js";

export async function searchFriends(
  dependencies: FriendsDependencies,
  request: FriendsCallableRequest,
) {
  const uid = requireAuthUid(request);
  const nickname = readNickname(request.data);
  const indexKey = nicknameIndexKey(nickname.canonical);
  const atMs = dependencies.nowMs();
  return dependencies.firestore.runTransaction(async (transaction) => {
    const rateReference = rateRef(dependencies.firestore, uid);
    const [rateSnapshot, claimSnapshot] = await Promise.all([
      transaction.get(rateReference),
      transaction.get(claimRef(dependencies.firestore, indexKey)),
    ]);
    const attempts = nextSearchAttemptMs(dataOf(rateSnapshot), atMs);
    if (!claimSnapshot.exists) {
      writeSearchRate(transaction, rateReference, attempts);
      return { results: [] };
    }
    const claim = dataOf(claimSnapshot);
    const candidateUid = claim["ownerUid"];
    if (typeof candidateUid !== "string" || candidateUid === uid || claim["nicknameCanonical"] !== nickname.canonical) {
      writeSearchRate(transaction, rateReference, attempts);
      return { results: [] };
    }
    const [profileSnapshot, actorBlockSnapshot, candidateBlockSnapshot] = await Promise.all([
      transaction.get(profileRef(dependencies.firestore, candidateUid)),
      transaction.get(blockRef(dependencies.firestore, uid, candidateUid)),
      transaction.get(blockRef(dependencies.firestore, candidateUid, uid)),
    ]);
    writeSearchRate(transaction, rateReference, attempts);
    if (!profileSnapshot.exists || actorBlockSnapshot.exists || candidateBlockSnapshot.exists) return { results: [] };
    const profile = socialProfile(candidateUid, dataOf(profileSnapshot));
    if (profile === undefined || profile.canonicalNickname !== nickname.canonical) return { results: [] };
    // `profile.identity` is built from the nickname alone (`buildFriendIdentity`),
    // so it carries no avatar. Without this the one search result renders as an
    // initials disc while the same runner shows their photo on every other
    // Friends tab, whose rows resolve the avatar through `getFriendLevels`.
    // Search never calls that, being the one tab with no social edge yet.
    return {
      results: [
        {
          ...profile.identity,
          ...resolveProfileLevelDisplay(dataOf(profileSnapshot)),
          ...resolveProfileAvatarDisplay(dataOf(profileSnapshot), dependencies.avatarContext),
        },
      ],
    };
  });
}
