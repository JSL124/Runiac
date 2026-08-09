// Stage A of account deletion: the part that must not be left half-done.
//
// This callable does NOT erase anything. It makes the account immediately and
// irreversibly unusable, frees the one resource another runner may be waiting
// on (the nickname), and enqueues the erase. Everything unbounded — the fan-out
// across ~25 collections and four Storage prefixes — belongs to the trigger,
// because a callable cannot guarantee it will finish and a half-finished
// deletion that reported success is worse than one that reported failure.
//
// The command document is keyed by uid rather than an auto-id, which makes a
// double-tap naturally idempotent: the second call finds the existing command
// and returns `already_requested` instead of enqueuing a second erase.

import {
  FieldValue,
  getFirestore,
  Timestamp,
  type DocumentSnapshot,
  type Firestore,
} from "firebase-admin/firestore";
import { getAuth, type Auth } from "firebase-admin/auth";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { rejectUnsupportedFields } from "../run/rejectUnsupportedFields.js";
import { shouldEnforceAppCheck } from "../security/appCheck.js";
import { withCallableErrorReporting } from "../errors/withErrorReporting.js";
import { ACCOUNT_DELETION_COMMANDS } from "./accountDeletionCommandTypes.js";

const ALLOWED_PAYLOAD_KEYS = new Set(["confirmation"]);

// The client already gates this behind a typed confirmation and a destructive
// dialog. Requiring the same token on the wire means a mis-wired caller — a
// stray retry, a fuzzed payload, a copy-pasted callable invocation — cannot
// delete an account by accident. It is a guard against mistakes, not against
// an attacker, who would simply send the token.
const REQUIRED_CONFIRMATION = "DELETE";

type RequestAccountDeletionRequest = {
  readonly auth?: { readonly uid: string };
  readonly data: unknown;
};

export type RequestAccountDeletionResult = {
  readonly status: "accepted" | "already_requested";
};

export type RequestAccountDeletionDependencies = {
  readonly firestore: Firestore;
  readonly auth: Auth;
};

export const requestAccountDeletion = onCall<unknown, Promise<RequestAccountDeletionResult>>(
  { region: "asia-southeast1", enforceAppCheck: shouldEnforceAppCheck() },
  withCallableErrorReporting("requestAccountDeletion", async (request: RequestAccountDeletionRequest) =>
    requestAccountDeletionForCallable(request, {
      firestore: getFirestore(),
      auth: getAuth(),
    })),
);

export async function requestAccountDeletionForCallable(
  request: RequestAccountDeletionRequest,
  dependencies: RequestAccountDeletionDependencies,
  nowMs: number = Date.now(),
): Promise<RequestAccountDeletionResult> {
  const uid = authenticatedUid(request);
  assertConfirmed(request.data);

  const { firestore, auth } = dependencies;
  const now = Timestamp.fromMillis(nowMs);

  const status = await firestore.runTransaction(async (transaction) => {
    const commandRef = firestore.doc(`${ACCOUNT_DELETION_COMMANDS}/${uid}`);
    const [commandSnap, profileSnap] = (await transaction.getAll(
      commandRef,
      firestore.doc(`userProfiles/${uid}`),
    )) as [DocumentSnapshot, DocumentSnapshot];

    if (commandSnap.exists && commandSnap.get("status") !== "failed") {
      return "already_requested" as const;
    }

    // The nickname claim is released here rather than in the fan-out because it
    // is the one piece of this account another runner may be actively waiting
    // to reuse, and because the claim document is keyed by the nickname, not by
    // the uid — once userProfiles/{uid} is gone there is nothing left pointing
    // at it. Guarded on ownership so a claim already reassigned to somebody
    // else is never deleted out from under them.
    const profile = profileSnap.data();
    for (const key of ["nicknameIndexKey", "nicknameKey"]) {
      const indexKey = profile?.[key];
      if (typeof indexKey !== "string" || indexKey.length === 0) continue;
      const claimRef = firestore.doc(`nicknameClaims/${indexKey}`);
      const claimSnap = await transaction.get(claimRef);
      if (claimSnap.exists && claimSnap.get("ownerUid") === uid) {
        transaction.delete(claimRef);
      }
    }

    // `merge` rather than `update`: an account whose users/{uid} document was
    // never provisioned must still be deletable.
    transaction.set(
      firestore.doc(`users/${uid}`),
      {
        accountStatus: "deleting",
        accountDeletionRequestedAt: now,
      },
      { merge: true },
    );

    // Withdraw from friend search immediately. The profile is erased minutes
    // later anyway, but until then it stays discoverable, and a runner who has
    // just deleted their account should not surface in anybody's search.
    if (profileSnap.exists) {
      transaction.update(firestore.doc(`userProfiles/${uid}`), {
        socialDiscoveryStatus: "inactive",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    transaction.set(commandRef, {
      uid,
      status: "pending",
      requestedAt: now,
      completedSteps: [],
    });

    return "accepted" as const;
  });

  if (status === "accepted") {
    // Auth teardown runs after the commit, and failures here are deliberately
    // fatal to the call: the whole point of stage A is that the caller cannot
    // keep using the account. If this throws, the client shows an error and the
    // command document is left `pending` for a retry, which is the correct
    // failure mode — the alternative is telling a user their account is gone
    // while their session still works.
    //
    // Revoke first, then disable. Revoking invalidates refresh tokens so no new
    // ID token can be minted; disabling closes sign-in. Doing it in this order
    // means there is no instant at which a fresh token could be issued to an
    // account that already looks deleted.
    await auth.revokeRefreshTokens(uid);
    await auth.updateUser(uid, { disabled: true });
  }

  return { status };
}

function authenticatedUid(request: RequestAccountDeletionRequest): string {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return uid;
}

function assertConfirmed(data: unknown): void {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "A confirmation payload object is required.");
  }
  rejectUnsupportedFields(data, ALLOWED_PAYLOAD_KEYS, "Account deletion payload");
  if (data["confirmation"] !== REQUIRED_CONFIRMATION) {
    throw new HttpsError("invalid-argument", "confirmation must be the exact word DELETE.");
  }
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
