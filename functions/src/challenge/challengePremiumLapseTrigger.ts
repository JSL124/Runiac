// `users/{uid}` update trigger for the challenge premium-lapse hold.
//
// Why a trigger at all: the admin console is a separate Next.js app using the
// Admin SDK, so it cannot call a callable — `setUserSubscription` is a direct
// Firestore write. A document trigger is therefore the only way to observe an
// admin-driven downgrade (or an admin-driven RE-upgrade, which must clear a
// hold just as promptly). The daily expiry sweep calls the same core, so an
// expiry-driven downgrade converges even if this trigger fails.
//
// Cost note, recorded honestly: `completeRun` writes `users/{uid}` on every
// finished run, so this fires far more often than subscriptions actually
// change. The guard below returns before any read whenever neither
// subscription field moved, which is the overwhelming majority of invocations.

import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import {
  onDocumentUpdated,
  type Change,
  type FirestoreEvent,
  type QueryDocumentSnapshot,
} from "firebase-functions/v2/firestore";

import { syncChallengePremiumHold } from "./challengePremiumLapse.js";
import { withTriggerErrorReporting } from "../errors/withErrorReporting.js";

type SubscriptionChangeEvent = FirestoreEvent<
  Change<QueryDocumentSnapshot> | undefined,
  { readonly uid: string }
>;

if (getApps().length === 0) {
  initializeApp();
}

export const challengeSubscriptionChanged = onDocumentUpdated(
  {
    document: "users/{uid}",
    region: "asia-southeast1",
  },
  withTriggerErrorReporting("challengeSubscriptionChanged", async (event: SubscriptionChangeEvent) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before === undefined || after === undefined) return;

    // Both fields matter: a status flip is the obvious case, but an admin
    // shortening or extending `subscriptionExpiresAt` changes effective
    // entitlement without touching the status string.
    if (
      before["subscriptionStatus"] === after["subscriptionStatus"] &&
      sameExpiry(before["subscriptionExpiresAt"], after["subscriptionExpiresAt"])
    ) {
      return;
    }

    await syncChallengePremiumHold(getFirestore(), event.params["uid"], Date.now());
  }),
);

function sameExpiry(before: unknown, after: unknown): boolean {
  const beforeMs = expiryMillis(before);
  const afterMs = expiryMillis(after);
  return beforeMs === afterMs;
}

function expiryMillis(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "object" && value !== null && "toMillis" in value) {
    const toMillis = (value as { readonly toMillis: unknown }).toMillis;
    if (typeof toMillis === "function") {
      return (toMillis as () => number).call(value);
    }
  }
  return null;
}
