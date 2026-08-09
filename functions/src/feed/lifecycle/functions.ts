import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onDocumentDeleted } from "firebase-functions/v2/firestore";
import { cleanupFromActivityDeletion, deleteFeedPostCore, reportFeedPostCore } from "./core.js";
import { firebaseLifecyclePort } from "./firebasePort.js";
import type { DeleteFeedPostResult, ReportFeedPostResult } from "./types.js";
import { withCallableErrorReporting, withTriggerErrorReporting } from "../../errors/withErrorReporting.js";
import { assertAccountNotSuspended } from "../../security/accountStatus.js";

if (getApps().length === 0) initializeApp();

type CallableRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };
type ReportCallableResult = { readonly reportId: string; readonly duplicate: boolean };
type DeleteCallableResult = { readonly status: "deleted" | "already_missing" | "retry_required" };

// Defence-in-depth (see accountStatus.ts). This runs in the onCall
// registration, NOT inside reportFeedPostForCallable/deleteFeedPostForCallable
// below, because those two are unit-tested directly against fake
// FeedLifecyclePort doubles with no real Firestore behind them; keeping the
// suspension check here preserves that pure, port-based unit-test surface
// while still gating every real invocation (production and
// feedEmulatorIntegration.test.ts both go through this onCall wrapper).
// Skips silently when uid is absent so the wrapped callable's own
// unauthenticated check still produces the "unauthenticated" error it always
// has.
async function assertCallerNotSuspended(request: CallableRequest): Promise<void> {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) return;
  const snapshot = await getFirestore().collection("users").doc(uid).get();
  assertAccountNotSuspended(snapshot.data());
}

export const reportFeedPost = onCall<unknown, Promise<ReportCallableResult>>(
  { region: "asia-southeast1" },
  withCallableErrorReporting("reportFeedPost", async (request: CallableRequest) => {
    await assertCallerNotSuspended(request);
    return reportFeedPostForCallable(request, firebaseLifecyclePort());
  }),
);

export const deleteFeedPost = onCall<unknown, Promise<DeleteCallableResult>>(
  { region: "asia-southeast1" },
  withCallableErrorReporting("deleteFeedPost", async (request: CallableRequest) => {
    await assertCallerNotSuspended(request);
    return deleteFeedPostForCallable(request, firebaseLifecyclePort());
  }),
);

export const cleanupDeletedFeedActivity = onDocumentDeleted(
  { document: "activities/{activityId}", region: "asia-southeast1", retry: true },
  withTriggerErrorReporting(
    "cleanupDeletedFeedActivity",
    async (event: { readonly params: { readonly activityId: string } }) => {
      const result = await cleanupFromActivityDeletion({ port: firebaseLifecyclePort(), postId: event.params.activityId });
      if (result.kind === "cleanup" && result.cleanup.kind === "retry_required") throw new FeedCleanupRetryError(result.cleanup.failedStep);
    },
  ),
);

export async function reportFeedPostForCallable(request: CallableRequest, port = firebaseLifecyclePort()): Promise<ReportCallableResult> {
  const uid = authenticatedUid(request);
  const postId = parsePostId(request.data);
  if (postId === null) throw new HttpsError("invalid-argument", "A single postId is required.");
  const result = await reportFeedPostCore({ port, reporterUid: uid, postId });
  return reportCallableResult(result);
}

export async function deleteFeedPostForCallable(request: CallableRequest, port = firebaseLifecyclePort()): Promise<DeleteCallableResult> {
  const uid = authenticatedUid(request);
  const postId = parsePostId(request.data);
  if (postId === null) throw new HttpsError("invalid-argument", "A single postId is required.");
  return deleteCallableResult(await deleteFeedPostCore({ port, ownerUid: uid, postId }));
}

function authenticatedUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) throw new HttpsError("unauthenticated", "Authentication is required.");
  return uid;
}

function parsePostId(raw: unknown): string | null {
  if (!isRecord(raw) || Object.keys(raw).length !== 1 || typeof raw["postId"] !== "string") return null;
  return /^[A-Za-z0-9_-]{1,128}$/.test(raw["postId"]) ? raw["postId"] : null;
}

function reportCallableResult(result: ReportFeedPostResult): ReportCallableResult {
  switch (result.kind) {
    case "reported": return { reportId: result.reportId, duplicate: result.duplicate };
    case "missing": throw new HttpsError("not-found", "The Feed post does not exist.");
    case "denied": throw new HttpsError("permission-denied", "The Feed post is not currently accessible.");
    default: return assertNever(result);
  }
}

function deleteCallableResult(result: DeleteFeedPostResult): DeleteCallableResult {
  switch (result.kind) {
    case "denied": throw new HttpsError("permission-denied", "Only the post owner can delete it.");
    case "already_missing": return { status: "already_missing" };
    case "cleanup": return { status: result.cleanup.kind === "retry_required" ? "retry_required" : "deleted" };
    default: return assertNever(result);
  }
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function assertNever(value: never): never { throw new TypeError(`Unexpected callable result: ${JSON.stringify(value)}`); }

class FeedCleanupRetryError extends Error {
  readonly name = "FeedCleanupRetryError";
  constructor(readonly step: string) { super(`Feed cleanup requires retry at ${step}.`); }
}
