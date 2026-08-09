import { FieldValue, getFirestore, type DocumentData, type Firestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { reportBackendError } from "../errors/reportBackendError.js";
import { hashesEqual, sha256Hex } from "./crypto.js";
import { toMillis } from "./firestoreHelpers.js";
import { siteBaseUrl } from "./env.js";
import { NEWSLETTER_SUBSCRIBERS_COLLECTION } from "./collections.js";

// Confirmation link target for double opt-in: GET /confirmNewsletterSubscription?s=<subscriberId>&t=<rawToken>.
// Deliberately a public onRequest (not a callable) because the caller is a
// browser or mail-client link click with no Firebase SDK involved at all.
export type ConfirmNewsletterOutcome = "confirmed" | "invalid";

export type ConfirmNewsletterSubscriberSnapshot = {
  readonly status: string;
  readonly confirmTokenHash?: string;
  readonly confirmTokenExpiresAtMs?: number;
};

// The pure decision: everything above the write. `write: true` means the
// caller (the port's transaction) must persist "confirmed"; `write: false`
// covers both terminal-invalid outcomes and the already-confirmed idempotent
// path, where the outcome is "confirmed" but nothing needs writing again.
export type ConfirmDecision = {
  readonly outcome: ConfirmNewsletterOutcome;
  readonly write: boolean;
};

export function decideConfirmOutcome(
  snapshot: ConfirmNewsletterSubscriberSnapshot | null,
  token: string,
  nowMs: number,
): ConfirmDecision {
  if (snapshot === null || snapshot.confirmTokenHash === undefined) {
    return { outcome: "invalid", write: false };
  }
  if (!hashesEqual(sha256Hex(token), snapshot.confirmTokenHash)) {
    return { outcome: "invalid", write: false };
  }

  if (snapshot.status === "confirmed") {
    // Idempotent: a repeat click (double-click, mail client prefetch retry)
    // with a still-matching token redirects to success again without a
    // second write.
    return { outcome: "confirmed", write: false };
  }

  // MUST NOT resurrect an explicit unsubscribe. Scenario: a subscriber
  // confirms on day 0 and receives a campaign on day 2, then unsubscribes
  // that same day — but their original confirmation email (sent day 0) is
  // still sitting in their inbox with a confirm link that stays valid for 7
  // days. A stray click on that stale link, or a mail-scanner prefetch of
  // it, would otherwise re-confirm them against their explicit unsubscribe,
  // silently undoing it. So an "unsubscribed" record can never be
  // re-confirmed via an old confirm link, regardless of token validity — the
  // only path back to "pending"/"confirmed" is a genuine re-subscription
  // through subscribeNewsletter, which resets status to "pending" and mints
  // a fresh confirm token.
  //
  // This guard is only meaningful if it observes the LATEST status, not a
  // status read moments before an interleaved unsubscribe — see the
  // ConfirmNewsletterPort comment below for how runConfirmTransaction makes
  // that true.
  if (snapshot.status === "unsubscribed") {
    return { outcome: "invalid", write: false };
  }

  if (snapshot.confirmTokenExpiresAtMs !== undefined && snapshot.confirmTokenExpiresAtMs < nowMs) {
    return { outcome: "invalid", write: false };
  }

  return { outcome: "confirmed", write: true };
}

export type ConfirmNewsletterPort = {
  readonly now: () => Date;
  // The read (get), the decision (decide), and the write (conditional
  // markConfirmed) all happen inside ONE Firestore transaction. This is not
  // an optional hardening — without it, a plain get-then-write has a race:
  // an unsubscribe landing between the read and the write would be silently
  // overwritten by a confirm that read stale "pending" data, resurrecting a
  // subscriber the user explicitly opted out. Firestore transactions read
  // via the transaction handle and retry automatically if a concurrent
  // commit touches the same document before this one commits, so `decide`
  // always runs against the state that is about to be committed, never a
  // stale snapshot. `decide` stays pure (see decideConfirmOutcome) so it is
  // unit-testable without a real transaction; only the port implementation
  // needs Firestore.
  readonly runConfirmTransaction: (
    subscriberId: string,
    decide: (snapshot: ConfirmNewsletterSubscriberSnapshot | null) => ConfirmDecision,
  ) => Promise<ConfirmNewsletterOutcome>;
};

export async function confirmNewsletterSubscriptionCore(
  input: { readonly subscriberId: string | null; readonly token: string | null },
  port: ConfirmNewsletterPort,
): Promise<ConfirmNewsletterOutcome> {
  if (input.subscriberId === null || input.token === null) {
    return "invalid";
  }

  const token = input.token;
  const nowMs = port.now().getTime();
  return port.runConfirmTransaction(input.subscriberId, (snapshot) => decideConfirmOutcome(snapshot, token, nowMs));
}

export const confirmNewsletterSubscription = onRequest(
  { region: "asia-southeast1", invoker: "public" },
  async (req, res) => {
    try {
      const subscriberId = readQueryParam(req.query["s"]);
      const token = readQueryParam(req.query["t"]);
      const outcome = await confirmNewsletterSubscriptionCore(
        { subscriberId, token },
        firebaseConfirmNewsletterPort(),
      );
      res.redirect(302, `${siteBaseUrl()}/newsletter/${outcome === "confirmed" ? "confirmed" : "invalid"}`);
    } catch (error) {
      // No shared onRequest error-reporting wrapper exists anywhere in this
      // codebase — every other entry point is a callable, a Firestore
      // trigger, or a scheduled job (see errors/withErrorReporting.ts),
      // which is exactly the set that module wraps. Rather than add a
      // fourth wrapper shape for the two onRequest handlers in this module,
      // report inline here, matching what withCallableErrorReporting does
      // internally, and always fail toward the safe redirect rather than
      // ever surfacing a raw 500 to a browser or mail client.
      await reportBackendError({ functionName: "confirmNewsletterSubscription", error, fatal: true });
      res.redirect(302, `${siteBaseUrl()}/newsletter/invalid`);
    }
  },
);

function readQueryParam(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function readStatus(value: unknown): string {
  return typeof value === "string" ? value : "pending";
}

function readConfirmSnapshot(data: DocumentData): ConfirmNewsletterSubscriberSnapshot {
  const confirmTokenHash = data["confirmTokenHash"];
  const expiresAtMs = toMillis(data["confirmTokenExpiresAt"]);
  return {
    status: readStatus(data["status"]),
    ...(typeof confirmTokenHash === "string" ? { confirmTokenHash } : {}),
    ...(expiresAtMs === null ? {} : { confirmTokenExpiresAtMs: expiresAtMs }),
  };
}

function firebaseConfirmNewsletterPort(firestore: Firestore = getFirestore()): ConfirmNewsletterPort {
  return {
    now: () => new Date(),
    runConfirmTransaction: async (subscriberId, decide) => {
      const ref = firestore.collection(NEWSLETTER_SUBSCRIBERS_COLLECTION).doc(subscriberId);
      return firestore.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        const current = snapshot.exists ? readConfirmSnapshot(snapshot.data() ?? {}) : null;
        const decision = decide(current);
        if (decision.write) {
          transaction.set(
            ref,
            { status: "confirmed", confirmedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() },
            { merge: true },
          );
        }
        return decision.outcome;
      });
    },
  };
}
