import type { Firestore } from "firebase-admin/firestore";

import type { AvatarUrlContext } from "../profile/avatar/avatarPaths.js";
import type { FriendIdentity } from "./nickname.js";

export type FriendsCallableRequest = {
  readonly auth?: { readonly uid: string };
  readonly data: unknown;
};

export type FriendsDependencies = {
  readonly firestore: Firestore;
  readonly nowMs: () => number;
  /**
   * Resolves a stored profile avatar path into a served URL for the one
   * friends callable that returns another runner's avatar (`searchFriends`).
   * `createFriendsService` defaults it to `NULL_AVATAR_URL_CONTEXT`, so a
   * caller that does not inject one fails closed to `avatarUrl: ""` rather
   * than relaying an unsanitised stored value.
   */
  readonly avatarContext: AvatarUrlContext;
};

export type RequestAction = "accept" | "decline";

export type SocialProfile = {
  readonly identity: FriendIdentity;
  readonly canonicalNickname: string;
};
