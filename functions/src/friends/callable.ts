import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";

import { createFriendsService, type FriendsCallableRequest } from "./friendsCore.js";
import { withCallableErrorReporting } from "../errors/withErrorReporting.js";
import { avatarUrlContextFromEnvironment } from "../profile/avatar/context.js";

if (getApps().length === 0) initializeApp();

type RawCallableRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };

function requestForCore(request: RawCallableRequest): FriendsCallableRequest {
  return request.auth === undefined
    ? { data: request.data }
    : { auth: { uid: request.auth.uid }, data: request.data };
}

export const checkNicknameAvailability = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("checkNicknameAvailability", async (request: RawCallableRequest) =>
    createFriendsService({ firestore: getFirestore() }).checkNicknameAvailability(requestForCore(request))),
);

export const upsertNickname = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("upsertNickname", async (request: RawCallableRequest) =>
    createFriendsService({ firestore: getFirestore() }).upsertNickname(requestForCore(request))),
);

// The only friends callable that returns another runner's avatar, so the only
// one that needs a real avatar context; every other one leaves the service's
// fail-closed default in place.
export const searchFriends = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("searchFriends", async (request: RawCallableRequest) =>
    createFriendsService({ firestore: getFirestore(), avatarContext: avatarUrlContextFromEnvironment() })
      .search(requestForCore(request))),
);

export const sendFriendRequest = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("sendFriendRequest", async (request: RawCallableRequest) =>
    createFriendsService({ firestore: getFirestore() }).sendFriendRequest(requestForCore(request))),
);

export const cancelFriendRequest = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("cancelFriendRequest", async (request: RawCallableRequest) =>
    createFriendsService({ firestore: getFirestore() }).cancelFriendRequest(requestForCore(request))),
);

export const respondToFriendRequest = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("respondToFriendRequest", async (request: RawCallableRequest) =>
    createFriendsService({ firestore: getFirestore() }).respondToFriendRequest(requestForCore(request))),
);

export const removeFriend = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("removeFriend", async (request: RawCallableRequest) =>
    createFriendsService({ firestore: getFirestore() }).removeFriend(requestForCore(request))),
);

export const blockUser = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("blockUser", async (request: RawCallableRequest) =>
    createFriendsService({ firestore: getFirestore() }).blockUser(requestForCore(request))),
);

export const unblockUser = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("unblockUser", async (request: RawCallableRequest) =>
    createFriendsService({ firestore: getFirestore() }).unblockUser(requestForCore(request))),
);

export const migrateUnicodeNicknameClaims = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("migrateUnicodeNicknameClaims", async (request: RawCallableRequest) =>
    createFriendsService({ firestore: getFirestore() }).migrateUnicodeNicknameClaims(requestForCore(request))),
);
