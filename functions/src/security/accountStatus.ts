import type { Firestore, Transaction } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

// Canonical account-suspension predicate.
//
// DEFENCE-IN-DEPTH ONLY — this is NOT the primary control, and a future
// reader must not mistake it for one. The primary control lives in the admin
// console's `setUserAccountStatus`: the moment an operator sets
// `users/{uid}.accountStatus` to a blocking value, that same action disables
// the user's Firebase Auth account and calls `revokeRefreshTokens`, which is
// what actually stops them from signing in or minting a new ID token. This
// predicate exists only to close the residual window in which an ID token
// issued and cached BEFORE that disable is still unexpired (Firebase ID
// tokens are valid for up to ~1 hour) and would otherwise keep passing
// Firestore rules and callables that never re-check `users/{uid}`.
//
// A missing `users/{uid}` document, or a missing/unrecognised
// `accountStatus` value, is treated as NOT suspended, so every
// already-stored document keeps its current behaviour. Every server-side
// suspension check must go through this one predicate so the set of
// blocking values never drifts across call sites.
//
// `deleting` joins the set for the same reason and with the same shape, but a
// different primary control: `requestAccountDeletion` revokes the caller's
// refresh tokens and disables their Auth user in the same call that sets the
// status, so this predicate again only closes the unexpired-ID-token window.
// Including it here rather than adding a second predicate is deliberate — every
// write-bearing callable already routes through this one, so an account being
// erased is locked out of all of them without a single new call site, and
// `isSuspendedAccount` also hides it from `getRunnerPublicProfile` while the
// fan-out runs.
const BLOCKING_ACCOUNT_STATUSES = new Set(["suspended", "banned", "deleting"]);

// Kept separate from the set above only so the rejection can say something
// true. Telling a runner who just deleted their account that it is "suspended"
// would be a confusing lie at the one moment they are most likely to contact
// support about it.
const DELETING_ACCOUNT_STATUS = "deleting";

export function isSuspendedAccount(userData: Readonly<Record<string, unknown>> | undefined): boolean {
  const accountStatus = userData?.["accountStatus"];
  return typeof accountStatus === "string" && BLOCKING_ACCOUNT_STATUSES.has(accountStatus);
}

// Canonical rejection for every write-bearing callable that checks
// suspension: same predicate, same error code, same message everywhere, so
// behaviour cannot drift across call sites the way the underlying check
// would if callables compared the string literals themselves.
export function assertAccountNotSuspended(userData: Readonly<Record<string, unknown>> | undefined): void {
  if (userData?.["accountStatus"] === DELETING_ACCOUNT_STATUS) {
    throw new HttpsError("permission-denied", "This account is being deleted.");
  }
  if (isSuspendedAccount(userData)) {
    throw new HttpsError("permission-denied", "This account is suspended.");
  }
}

// Convenience for callables whose transaction does not already read
// `users/{uid}` for some other reason. Performed as an ordinary
// `transaction.get`, so it still obeys Firestore's reads-before-writes rule
// no matter where in the transaction body it is called, as long as it is
// called before the transaction's first write.
export async function assertCallerAccountNotSuspendedInTransaction(
  transaction: Transaction,
  firestore: Firestore,
  uid: string,
): Promise<void> {
  const snapshot = await transaction.get(firestore.doc(`users/${uid}`));
  assertAccountNotSuspended(snapshot.data());
}
