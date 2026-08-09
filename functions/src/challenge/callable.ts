// Challenge callable production surface.
//
// Thin onCall wrappers (region asia-southeast1, same registration/emulator style
// as completeRun) that delegate to the transaction cores. Each maps the raw
// callable request onto the minimal `{ auth?: { uid }, data }` contract, then
// runs against the live Firestore. All authentication, idempotency, and stable
// reason codes live in the cores.

import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import {
  cancelChallengeLobbyForCallable,
  createChallengeLobbyForCallable,
  getActiveChallengeForCallable,
  getChallengeCatalogForCallable,
  getChallengeInvitationsForCallable,
  inviteChallengeFriendsForCallable,
  respondToChallengeInvitationForCallable,
  startChallengeForCallable,
  withdrawFromChallengeLobbyForCallable,
  type CallableRequest,
} from "./challengeLobbyCore.js";
import {
  abandonChallengeForCallable,
  leaveChallengeForCallable,
} from "./challengeSettlementCore.js";
import { withCallableErrorReporting } from "../errors/withErrorReporting.js";
import { avatarUrlContextFromEnvironment } from "../profile/avatar/context.js";

if (getApps().length === 0) initializeApp();

type RawCallableRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };

function normalize(request: RawCallableRequest): CallableRequest {
  return request.auth === undefined
    ? { data: request.data }
    : { auth: { uid: request.auth.uid }, data: request.data };
}

export const getChallengeCatalog = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("getChallengeCatalog", async (request: RawCallableRequest) =>
    getChallengeCatalogForCallable(normalize(request), getFirestore())),
);

export const createChallengeLobby = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("createChallengeLobby", async (request: RawCallableRequest) =>
    createChallengeLobbyForCallable(normalize(request), getFirestore())),
);

export const inviteChallengeFriends = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("inviteChallengeFriends", async (request: RawCallableRequest) =>
    inviteChallengeFriendsForCallable(normalize(request), getFirestore())),
);

export const respondToChallengeInvitation = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("respondToChallengeInvitation", async (request: RawCallableRequest) =>
    respondToChallengeInvitationForCallable(normalize(request), getFirestore())),
);

export const withdrawFromChallengeLobby = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("withdrawFromChallengeLobby", async (request: RawCallableRequest) =>
    withdrawFromChallengeLobbyForCallable(normalize(request), getFirestore())),
);

export const cancelChallengeLobby = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("cancelChallengeLobby", async (request: RawCallableRequest) =>
    cancelChallengeLobbyForCallable(normalize(request), getFirestore())),
);

export const startChallenge = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("startChallenge", async (request: RawCallableRequest) =>
    startChallengeForCallable(normalize(request), getFirestore())),
);

export const getActiveChallenge = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("getActiveChallenge", async (request: RawCallableRequest) =>
    getActiveChallengeForCallable(normalize(request), getFirestore(), avatarUrlContextFromEnvironment())),
);

export const getChallengeInvitations = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("getChallengeInvitations", async (request: RawCallableRequest) =>
    getChallengeInvitationsForCallable(normalize(request), getFirestore())),
);

export const leaveChallenge = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("leaveChallenge", async (request: RawCallableRequest) =>
    leaveChallengeForCallable(normalize(request), getFirestore())),
);

export const abandonChallenge = onCall(
  { region: "asia-southeast1" },
  withCallableErrorReporting("abandonChallenge", async (request: RawCallableRequest) =>
    abandonChallengeForCallable(normalize(request), getFirestore())),
);
