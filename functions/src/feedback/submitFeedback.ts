import { FieldValue, getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { rejectUnsupportedFields } from "../run/rejectUnsupportedFields.js";
import { shouldEnforceAppCheck } from "../security/appCheck.js";
import { withCallableErrorReporting } from "../errors/withErrorReporting.js";

const FEEDBACK_CATEGORIES = new Set(["bug", "plan issue", "billing", "other"]);
const ALLOWED_PAYLOAD_KEYS = new Set(["category", "message"]);
const MAX_MESSAGE_LENGTH = 2000;
const MAX_SUMMARY_LENGTH = 120;
const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
const RATE_LIMIT_MAX = 5;

type SubmitFeedbackRequest = {
  readonly auth?: { readonly uid: string };
  readonly data: unknown;
};

type SubmitFeedbackResult = { readonly feedbackId: string };

export type FeedbackRecord = {
  readonly uid: string;
  readonly category: string;
  readonly message: string;
  readonly summary: string;
  readonly severity: "low";
  readonly status: "new";
  readonly duplicateCount: number;
  readonly note: string;
  readonly receivedAt: unknown;
};

export type SubmitFeedbackPort = {
  readonly now: () => Date;
  readonly serverTimestamp: () => unknown;
  readonly recentFeedbackCount: (uid: string, since: Date) => Promise<number>;
  readonly addFeedback: (record: FeedbackRecord) => Promise<string>;
};

export const submitFeedback = onCall<unknown, Promise<SubmitFeedbackResult>>(
  { region: "asia-southeast1", enforceAppCheck: shouldEnforceAppCheck() },
  withCallableErrorReporting("submitFeedback", async (request: SubmitFeedbackRequest) =>
    submitFeedbackForCallable(request, firebaseFeedbackPort())),
);

export async function submitFeedbackForCallable(
  request: SubmitFeedbackRequest,
  port: SubmitFeedbackPort = firebaseFeedbackPort(),
): Promise<SubmitFeedbackResult> {
  const uid = authenticatedUid(request);
  const payload = parsePayload(request.data);

  // Best-effort, non-transactional rate limit: two concurrent submissions from
  // the same caller can both observe a count below the threshold and both
  // succeed, but the query bound keeps sustained abuse in check.
  const since = new Date(port.now().getTime() - RATE_LIMIT_WINDOW_MS);
  const recentCount = await port.recentFeedbackCount(uid, since);
  if (recentCount >= RATE_LIMIT_MAX) {
    throw new HttpsError("resource-exhausted", "Too many feedback submissions. Please try again later.");
  }

  const feedbackId = await port.addFeedback({
    uid,
    category: payload.category,
    message: payload.message,
    summary: buildSummary(payload.message),
    severity: "low",
    status: "new",
    duplicateCount: 1,
    note: "",
    receivedAt: port.serverTimestamp(),
  });

  return { feedbackId };
}

function authenticatedUid(request: SubmitFeedbackRequest): string {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return uid;
}

function parsePayload(data: unknown): { readonly category: string; readonly message: string } {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "A feedback payload object is required.");
  }
  rejectUnsupportedFields(data, ALLOWED_PAYLOAD_KEYS, "Feedback payload");

  const category = data["category"];
  if (typeof category !== "string" || !FEEDBACK_CATEGORIES.has(category)) {
    throw new HttpsError("invalid-argument", "category must be one of: bug, plan issue, billing, other.");
  }

  const rawMessage = data["message"];
  if (typeof rawMessage !== "string") {
    throw new HttpsError("invalid-argument", "message must be a string.");
  }
  const message = rawMessage.trim();
  if (message.length === 0 || message.length > MAX_MESSAGE_LENGTH) {
    throw new HttpsError("invalid-argument", "message must be non-empty and at most 2000 characters.");
  }

  return { category, message };
}

function buildSummary(message: string): string {
  return message.replace(/\s+/g, " ").trim().slice(0, MAX_SUMMARY_LENGTH);
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function firebaseFeedbackPort(firestore: Firestore = getFirestore()): SubmitFeedbackPort {
  return {
    now: () => new Date(),
    serverTimestamp: () => FieldValue.serverTimestamp(),
    recentFeedbackCount: async (uid, since) => {
      const snapshot = await firestore
        .collection("feedback")
        .where("uid", "==", uid)
        .where("receivedAt", ">", since)
        .limit(RATE_LIMIT_MAX)
        .get();
      return snapshot.size;
    },
    addFeedback: async (record) => {
      const reference = await firestore.collection("feedback").add(record);
      return reference.id;
    },
  };
}
