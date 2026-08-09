import { FieldValue, getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { rejectUnsupportedFields } from "../run/rejectUnsupportedFields.js";
import { withCallableErrorReporting } from "../errors/withErrorReporting.js";
import { generateRawToken, sha256Hex, subscriberIdForEmail } from "./crypto.js";
import { functionsBaseUrl } from "./env.js";
import { buildConfirmationMail } from "./mailRender.js";
import { checkAndConsumeIpRateLimit } from "./rateLimit.js";
import { MAIL_COLLECTION, NEWSLETTER_SUBSCRIBERS_COLLECTION } from "./collections.js";

// PUBLIC, UNAUTHENTICATED CALLABLE — invoker "public", App Check
// deliberately OFF. This is invoked from the marketing website's hero
// signup form (a separate Next.js app, not the Flutter client), which has
// no App Check provider initialised at all; enforcing App Check here would
// simply fail every legitimate call. The real defences against abuse are:
//   1. A honeypot field ("website") that a real visitor never sees or
//      fills; a filled value is answered identically to success but
//      performs zero reads/writes.
//   2. A 5-per-hour-per-IP transactional rate limit (newsletterRateLimits).
//   3. Double opt-in: an address is never mailed a campaign until it clicks
//      the confirmation link, so even a successfully-spammed known-good
//      address never receives more than the one confirmation email.
const ALLOWED_PAYLOAD_KEYS = new Set(["email", "website"]);
const MAX_EMAIL_LENGTH = 254;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const CONFIRM_TOKEN_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export type SubscribeNewsletterResult = { readonly status: "pending" | "already-subscribed" };

type SubscribeNewsletterRequest = {
  // `auth` is never read — this callable is deliberately public/unauthenticated
  // (see the file header) — but it is declared here so this type structurally
  // overlaps with errors/withErrorReporting.ts's CallableLikeRequest
  // constraint (a "weak type" with only an optional `auth` property; TypeScript
  // requires at least one shared property against a weak type).
  readonly auth?: { readonly uid: string };
  readonly rawRequest?: { readonly ip: string | undefined };
  readonly data: unknown;
};

export type NewsletterSubscriberSnapshot = {
  readonly status: "pending" | "confirmed" | "unsubscribed" | "bounced";
  readonly unsubscribeTokenHash?: string;
  readonly unsubscribeTokenRaw?: string;
};

export type SubscribeNewsletterPort = {
  readonly now: () => Date;
  readonly serverTimestamp: () => unknown;
  readonly generateToken: () => string;
  // Returns false when the caller is over budget; true otherwise (and the
  // attempt has already been counted).
  readonly checkAndConsumeRateLimit: (ipHash: string) => Promise<boolean>;
  readonly getSubscriber: (subscriberId: string) => Promise<NewsletterSubscriberSnapshot | null>;
  readonly upsertSubscriber: (subscriberId: string, fields: Readonly<Record<string, unknown>>) => Promise<void>;
  readonly sendConfirmationMail: (args: {
    readonly to: string;
    readonly subscriberId: string;
    readonly rawToken: string;
  }) => Promise<void>;
};

export const subscribeNewsletter = onCall<unknown, Promise<SubscribeNewsletterResult>>(
  { region: "asia-southeast1", enforceAppCheck: false, invoker: "public" },
  withCallableErrorReporting<SubscribeNewsletterRequest, SubscribeNewsletterResult>(
    "subscribeNewsletter",
    async (request) => subscribeNewsletterForCallable(request, firebaseSubscribeNewsletterPort()),
  ),
);

export async function subscribeNewsletterForCallable(
  request: SubscribeNewsletterRequest,
  port: SubscribeNewsletterPort = firebaseSubscribeNewsletterPort(),
): Promise<SubscribeNewsletterResult> {
  const payload = parsePayload(request.data);

  // Honeypot check runs before any I/O at all — including the rate
  // limiter. A bot filling this field costs us zero Firestore operations,
  // so it needs no throttling, and NOT consuming rate-limit budget here
  // means a bot cannot use honeypot hits to burn through a shared-IP (e.g.
  // NAT/office network) budget that real visitors behind the same IP rely
  // on.
  if (isHoneypotFilled(payload.website)) {
    return { status: "pending" };
  }

  const email = normalizeEmail(payload.email);
  const ipHash = sha256Hex(request.rawRequest?.ip ?? "unknown-ip");

  const allowed = await port.checkAndConsumeRateLimit(ipHash);
  if (!allowed) {
    throw new HttpsError("resource-exhausted", "Too many subscription attempts. Please try again later.");
  }

  const subscriberId = subscriberIdForEmail(email);
  const existing = await port.getSubscriber(subscriberId);

  if (existing !== null && existing.status === "confirmed") {
    // Already confirmed: report success but send NOTHING. Otherwise the
    // public form becomes a way to spam a known-good address with repeat
    // "confirm again" mail.
    return { status: "already-subscribed" };
  }

  const rawConfirmToken = port.generateToken();
  const confirmTokenHash = sha256Hex(rawConfirmToken);
  const confirmTokenExpiresAt = new Date(port.now().getTime() + CONFIRM_TOKEN_TTL_MS);

  // JUDGMENT CALL: the unsubscribe token is minted ONCE, ever, per
  // subscriberId (which is itself deterministic from the email address) and
  // is never rotated on a later re-subscribe. Unlike the confirm token
  // (single-use, consumed within minutes of being minted), the unsubscribe
  // token must keep validating against every campaign email ever sent to
  // this address — including ones sent months ago — for as long as that
  // email might still sit in an inbox ("links live in old emails forever").
  // A hash alone cannot be used to reconstruct the same raw value for a
  // NEW campaign's email months later, so the raw value is retained
  // alongside its hash (unsubscribeTokenRaw, in addition to the specified
  // unsubscribeTokenHash). This is safe because: (1) newsletterSubscribers
  // is fully client-denied in firestore.rules — only Cloud Functions via
  // the Admin SDK can ever read it; (2) the blast radius of the token
  // leaking is low (someone unsubscribes an address they don't own — a
  // nuisance, not an account compromise or data exposure).
  const unsubscribeTokenRaw = existing?.unsubscribeTokenRaw ?? port.generateToken();
  const unsubscribeTokenHash = existing?.unsubscribeTokenHash ?? sha256Hex(unsubscribeTokenRaw);

  const fields: Record<string, unknown> = {
    emailLower: email,
    status: "pending",
    source: "website_hero",
    consentAt: port.serverTimestamp(),
    confirmTokenHash,
    confirmTokenExpiresAt,
    unsubscribeTokenHash,
    unsubscribeTokenRaw,
    ipHash,
    sendFailureCount: 0,
    updatedAt: port.serverTimestamp(),
    // `createdAt` here means "start of the current pending window", not
    // "when this document was first created" — it is the sweep's clock
    // (sweepUnconfirmedSubscribers.ts deletes `pending` docs whose
    // `createdAt` is older than 30 days). It is ALWAYS re-armed to now on
    // every (re-)subscribe, including for an existing document, not just a
    // brand-new one. Without this, a subscriber who unsubscribes (or never
    // confirms) and then returns after 30+ days gets a fresh 7-day confirm
    // token, but the sweep — reading the ORIGINAL createdAt — could delete
    // the record before that new token is ever clicked. A separate
    // `pendingSince` field would express the same intent more literally, but
    // would require a new composite index alongside the existing deployed
    // status+createdAt one (see firestore.indexes.json); reusing `createdAt`
    // as the sweep's clock avoids that index change entirely.
    createdAt: port.serverTimestamp(),
  };
  await port.upsertSubscriber(subscriberId, fields);
  await port.sendConfirmationMail({ to: email, subscriberId, rawToken: rawConfirmToken });

  return { status: "pending" };
}

function parsePayload(data: unknown): { readonly email: unknown; readonly website: unknown } {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "A subscription payload object is required.");
  }
  rejectUnsupportedFields(data, ALLOWED_PAYLOAD_KEYS, "Newsletter subscription payload");
  return { email: data["email"], website: data["website"] };
}

// A real visitor never sees or fills the "website" field (it is hidden from
// sighted and screen-reader users alike by the form). Any non-empty value —
// including an unexpected non-string shape, which is treated as filled
// rather than rejected — marks the request as automated.
function isHoneypotFilled(website: unknown): boolean {
  if (website === undefined || website === null) {
    return false;
  }
  if (typeof website !== "string") {
    return true;
  }
  return website.trim().length > 0;
}

function normalizeEmail(raw: unknown): string {
  if (typeof raw !== "string") {
    throw new HttpsError("invalid-argument", "email must be a string.");
  }
  const normalized = raw.trim().toLowerCase();
  if (normalized.length === 0 || normalized.length > MAX_EMAIL_LENGTH || !EMAIL_PATTERN.test(normalized)) {
    throw new HttpsError("invalid-argument", "email must be a valid email address of at most 254 characters.");
  }
  return normalized;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readSubscriberStatus(value: unknown): NewsletterSubscriberSnapshot["status"] {
  return value === "confirmed" || value === "pending" || value === "unsubscribed" || value === "bounced"
    ? value
    : "pending";
}

function firebaseSubscribeNewsletterPort(firestore: Firestore = getFirestore()): SubscribeNewsletterPort {
  return {
    now: () => new Date(),
    serverTimestamp: () => FieldValue.serverTimestamp(),
    generateToken: generateRawToken,
    checkAndConsumeRateLimit: (ipHash) => checkAndConsumeIpRateLimit(firestore, ipHash, Date.now()),
    getSubscriber: async (subscriberId) => {
      const snapshot = await firestore.collection(NEWSLETTER_SUBSCRIBERS_COLLECTION).doc(subscriberId).get();
      if (!snapshot.exists) {
        return null;
      }
      const data = snapshot.data() ?? {};
      const unsubscribeTokenHash = data["unsubscribeTokenHash"];
      const unsubscribeTokenRaw = data["unsubscribeTokenRaw"];
      return {
        status: readSubscriberStatus(data["status"]),
        ...(typeof unsubscribeTokenHash === "string" ? { unsubscribeTokenHash } : {}),
        ...(typeof unsubscribeTokenRaw === "string" ? { unsubscribeTokenRaw } : {}),
      };
    },
    upsertSubscriber: async (subscriberId, fields) => {
      await firestore.collection(NEWSLETTER_SUBSCRIBERS_COLLECTION).doc(subscriberId).set(fields, { merge: true });
    },
    sendConfirmationMail: async ({ to, subscriberId, rawToken }) => {
      const confirmUrl = `${functionsBaseUrl()}/confirmNewsletterSubscription?s=${subscriberId}&t=${rawToken}`;
      await firestore.collection(MAIL_COLLECTION).add(buildConfirmationMail({ to, confirmUrl }));
    },
  };
}
