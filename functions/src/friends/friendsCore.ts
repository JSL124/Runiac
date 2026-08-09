import type { Firestore } from "firebase-admin/firestore";

import type { AvatarUrlContext } from "../profile/avatar/avatarPaths.js";
import { NULL_AVATAR_URL_CONTEXT } from "../profile/avatar/avatarUrlContextDefaults.js";
import { blockUser, unblockUser } from "./friendsBlocks.js";
import { searchFriends } from "./friendsDiscovery.js";
import { migrateUnicodeNicknameClaims } from "./friendsMigration.js";
import { checkNicknameAvailability, upsertNickname } from "./friendsNicknameService.js";
import { cancelFriendRequest, sendFriendRequest } from "./friendsRequests.js";
import { removeFriend, respondToFriendRequest } from "./friendsResponses.js";
import type { FriendsDependencies } from "./friendsTypes.js";

export type { FriendsCallableRequest } from "./friendsTypes.js";

export function createFriendsService(input: {
  readonly firestore: Firestore;
  readonly nowMs?: () => number;
  readonly avatarContext?: AvatarUrlContext;
}) {
  const dependencies: FriendsDependencies = {
    firestore: input.firestore,
    nowMs: input.nowMs ?? Date.now,
    avatarContext: input.avatarContext ?? NULL_AVATAR_URL_CONTEXT,
  };
  return {
    checkNicknameAvailability: (request: import("./friendsTypes.js").FriendsCallableRequest) =>
      checkNicknameAvailability(dependencies, request),
    upsertNickname: (request: import("./friendsTypes.js").FriendsCallableRequest) =>
      upsertNickname(dependencies, request),
    search: (request: import("./friendsTypes.js").FriendsCallableRequest) => searchFriends(dependencies, request),
    sendFriendRequest: (request: import("./friendsTypes.js").FriendsCallableRequest) =>
      sendFriendRequest(dependencies, request),
    cancelFriendRequest: (request: import("./friendsTypes.js").FriendsCallableRequest) =>
      cancelFriendRequest(dependencies, request),
    respondToFriendRequest: (request: import("./friendsTypes.js").FriendsCallableRequest) =>
      respondToFriendRequest(dependencies, request),
    removeFriend: (request: import("./friendsTypes.js").FriendsCallableRequest) => removeFriend(dependencies, request),
    blockUser: (request: import("./friendsTypes.js").FriendsCallableRequest) => blockUser(dependencies, request),
    unblockUser: (request: import("./friendsTypes.js").FriendsCallableRequest) => unblockUser(dependencies, request),
    migrateUnicodeNicknameClaims: (request: import("./friendsTypes.js").FriendsCallableRequest) =>
      migrateUnicodeNicknameClaims(dependencies, request),
  };
}
