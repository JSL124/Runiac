import { FieldValue, getFirestore, type DocumentData, type Firestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { reportBackendError } from "../errors/reportBackendError.js";
import { hashesEqual, sha256Hex } from "./crypto.js";
import { siteBaseUrl } from "./env.js";
import { NEWSLETTER_SUBSCRIBERS_COLLECTION } from "./collections.js";

// Unsubscribe link target: GET /unsubscribeNewsletter?s=<subscriberId>&t=<rawToken>.
// Deliberately GET, not POST: this is what every campaign email's
// List-Unsubscribe header (and the visible in-body link) points at, and
// mail clients / spam filters expect a plain GET link there. The accepted
// trade-off is that some mail-scanner prefetchers follow links before a
// human ever opens the message, which could unsubscribe an address nobody
// asked to unsubscribe — but the operation is idempotent and low-stakes
// (re-subscribing is one form submission away), and RFC 8058 one-click
// (POST, no confirmation) is the alternative Gmail/most providers actually
// expect for List-Unsubscribe, which this endpoint already matches in
// spirit (no interstitial confirmation page) without requiring a second
// endpoint shape.
export type UnsubscribeNewsletterOutcome = "unsubscribed" | "invalid";

export type UnsubscribeNewsletterSubscriberSnapshot = {
  readonly status: string;
  readonly unsubscribeTokenHash?: string;
};

// The pure decision: everything above the write. `write: true` means the
// caller (the port's transaction) must persist "unsubscribed"; `write: false`
// covers both the invalid outcome and the already-unsubscribed idempotent
// path.
export type UnsubscribeDecision = {
  readonly outcome: UnsubscribeNewsletterOutcome;
  readonly write: boolean;
};

export function decideUnsubscribeOutcome(
  snapshot: UnsubscribeNewsletterSubscriberSnapshot | null,
  token: string,
): UnsubscribeDecision {
  if (snapshot === null || snapshot.unsubscribeTokenHash === undefined) {
    return { outcome: "invalid", write: false };
  }
  if (!hashesEqual(sha256Hex(token), snapshot.unsubscribeTokenHash)) {
    return { outcome: "invalid", write: false };
  }

  // The unsubscribe token never expires (see subscribeNewsletter.ts), so
  // there is no expiry check here — only the hash comparison above.
  if (snapshot.status !== "unsubscribed") {
    return { outcome: "unsubscribed", write: true };
  }
  // Idempotent either way: an already-unsubscribed address with a valid
  // token still redirects to success.
  return { outcome: "unsubscribed", write: false };
}

export type UnsubscribeNewsletterPort = {
  // The read (get), the decision (decide), and the write (conditional
  // markUnsubscribed) all happen inside ONE Firestore transaction, mirroring
  // confirmNewsletterSubscription.ts's runConfirmTransaction. An unsubscribe
  // racing a confirm is lower-stakes than the reverse (ending up unsubscribed
  // is the safer failure mode for a double opt-in list), but the transaction
  // keeps both operations consistent under the same read-decide-write
  // discipline rather than leaving one of the two as a plain get-then-write.
  readonly runUnsubscribeTransaction: (
    subscriberId: string,
    decide: (snapshot: UnsubscribeNewsletterSubscriberSnapshot | null) => UnsubscribeDecision,
  ) => Promise<UnsubscribeNewsletterOutcome>;
};

export async function unsubscribeNewsletterCore(
  input: { readonly subscriberId: string | null; readonly token: string | null },
  port: UnsubscribeNewsletterPort,
): Promise<UnsubscribeNewsletterOutcome> {
  if (input.subscriberId === null || input.token === null) {
    return "invalid";
  }

  const token = input.token;
  return port.runUnsubscribeTransaction(input.subscriberId, (snapshot) => decideUnsubscribeOutcome(snapshot, token));
}

export const unsubscribeNewsletter = onRequest(
  { region: "asia-southeast1", invoker: "public" },
  async (req, res) => {
    try {
      const subscriberId = readQueryParam(req.query["s"]);
      const token = readQueryParam(req.query["t"]);
      const outcome = await unsubscribeNewsletterCore({ subscriberId, token }, firebaseUnsubscribeNewsletterPort());
      res.redirect(302, `${siteBaseUrl()}/newsletter/${outcome === "unsubscribed" ? "unsubscribed" : "invalid"}`);
    } catch (error) {
      // See confirmNewsletterSubscription.ts's identical comment: there is
      // no shared onRequest error-reporting wrapper in this codebase, so
      // this reports inline and always fails toward the safe redirect.
      await reportBackendError({ functionName: "unsubscribeNewsletter", error, fatal: true });
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

function readUnsubscribeSnapshot(data: DocumentData): UnsubscribeNewsletterSubscriberSnapshot {
  const unsubscribeTokenHash = data["unsubscribeTokenHash"];
  return {
    status: readStatus(data["status"]),
    ...(typeof unsubscribeTokenHash === "string" ? { unsubscribeTokenHash } : {}),
  };
}

function firebaseUnsubscribeNewsletterPort(firestore: Firestore = getFirestore()): UnsubscribeNewsletterPort {
  return {
    runUnsubscribeTransaction: async (subscriberId, decide) => {
      const ref = firestore.collection(NEWSLETTER_SUBSCRIBERS_COLLECTION).doc(subscriberId);
      return firestore.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        const current = snapshot.exists ? readUnsubscribeSnapshot(snapshot.data() ?? {}) : null;
        const decision = decide(current);
        if (decision.write) {
          transaction.set(
            ref,
            { status: "unsubscribed", unsubscribedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() },
            { merge: true },
          );
        }
        return decision.outcome;
      });
    },
  };
}
