import { deterministicFeedIds } from "../contracts.js";
import { cleanupFeedPost } from "../cleanup.js";
import type {
  BeginCleanupInput,
  BeginCleanupResult,
  DeleteFeedPostResult,
  FeedLifecycleTransaction,
  ReportFeedPostInput,
  ReportFeedPostResult,
} from "./types.js";

export async function reportFeedPostCore(input: ReportFeedPostInput): Promise<ReportFeedPostResult> {
  if (!isIdentifier(input.reporterUid) || !isIdentifier(input.postId)) return { kind: "denied" };
  return input.port.runTransaction(async (transaction) => reportInTransaction(transaction, input));
}

export async function deleteFeedPostCore(input: BeginCleanupInput): Promise<DeleteFeedPostResult> {
  if (!isIdentifier(input.ownerUid) || !isIdentifier(input.postId)) return { kind: "denied" };
  const beginning = await beginFeedPostCleanup(input);
  switch (beginning.kind) {
    case "denied": return beginning;
    case "already_missing": return beginning;
    case "ready": return { kind: "cleanup", cleanup: await cleanupFeedPost(input.port, beginning.post) };
    default: return assertNever(beginning);
  }
}

export async function cleanupFromActivityDeletion(input: Omit<BeginCleanupInput, "ownerUid">): Promise<DeleteFeedPostResult> {
  if (!isIdentifier(input.postId)) return { kind: "already_missing" };
  const beginning = await beginFeedPostCleanup(input);
  switch (beginning.kind) {
    case "denied": return beginning;
    case "already_missing": return beginning;
    case "ready": return { kind: "cleanup", cleanup: await cleanupFeedPost(input.port, beginning.post) };
    default: return assertNever(beginning);
  }
}

export async function beginFeedPostCleanup(input: BeginCleanupInput): Promise<BeginCleanupResult> {
  return input.port.runTransaction(async (transaction) => {
    const post = await transaction.getPost(input.postId);
    if (post === null) return { kind: "already_missing" };
    if (input.ownerUid !== undefined && post.authorUid !== input.ownerUid) return { kind: "denied" };
    if (post.status === "published") transaction.setDeleting(post.postId);
    return { kind: "ready", post: { ...post, status: "deleting" } };
  });
}

async function reportInTransaction(
  transaction: FeedLifecycleTransaction,
  input: ReportFeedPostInput,
): Promise<ReportFeedPostResult> {
  const post = await transaction.getPost(input.postId);
  if (post === null) return { kind: "missing" };
  if (post.status !== "published" || !await transaction.canReadPost(input.reporterUid, post)) return { kind: "denied" };
  const ids = deterministicFeedIds(input.postId, input.reporterUid);
  const existing = await transaction.getReport(ids.reportId);
  if (existing === null) {
    const createdAt = input.port.now();
    transaction.setReport(ids.reportId, {
      reporterUid: input.reporterUid, targetType: "feedPost", targetId: input.postId,
      reason: "feed_inappropriate", description: "", createdAt,
    });
    transaction.setHiddenMarker(input.reporterUid, input.postId, createdAt);
    return { kind: "reported", reportId: ids.reportId, duplicate: false };
  }
  transaction.setHiddenMarker(input.reporterUid, input.postId, existing.createdAt);
  return { kind: "reported", reportId: ids.reportId, duplicate: true };
}

function isIdentifier(value: string | undefined): value is string {
  return value !== undefined && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function assertNever(value: never): never {
  throw new TypeError(`Unexpected lifecycle result: ${JSON.stringify(value)}`);
}
