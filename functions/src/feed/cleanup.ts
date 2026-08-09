import type { CleanupOperation, FeedLifecyclePort, LifecyclePost, LifecycleStepResult } from "./lifecycle/types.js";

export type FeedCleanupStep = "likes" | "comments" | "reports" | "hidden_markers" | "thumbnail" | "post";
export type FeedCleanupStepResult = { readonly step: FeedCleanupStep; readonly deleted: boolean };
export type FeedCleanupResult =
  | { readonly kind: "completed"; readonly postId: string; readonly steps: readonly FeedCleanupStepResult[] }
  | { readonly kind: "already_missing"; readonly postId: string }
  | { readonly kind: "retry_required"; readonly postId: string; readonly failedStep: FeedCleanupStep };

export function cleanupResultIsTerminal(result: FeedCleanupResult): boolean {
  return result.kind === "completed" || result.kind === "already_missing";
}

const cleanupOperations: readonly CleanupOperation[] = [
  { step: "likes", run: (port, post) => port.deleteLikes(post.postId) },
  { step: "comments", run: (port, post) => port.deleteComments(post.postId) },
  { step: "reports", run: (port, post) => port.deleteReportsAndHiddenMarkers(post.postId) },
  { step: "hidden_markers", run: async () => ({ kind: "already_missing" }) },
  { step: "thumbnail", run: (port, post) => port.deleteExactThumbnail(post) },
  { step: "post", run: (port, post) => port.deletePost(post.postId) },
];

export async function cleanupFeedPost(port: FeedLifecyclePort, post: LifecyclePost): Promise<FeedCleanupResult> {
  const steps: FeedCleanupStepResult[] = [];
  for (const operation of cleanupOperations) {
    const result = await operation.run(port, post);
    if (requiresRetry(result)) return { kind: "retry_required", postId: post.postId, failedStep: operation.step };
    steps.push({ step: operation.step, deleted: result.kind === "completed" });
  }
  return { kind: "completed", postId: post.postId, steps };
}

function requiresRetry(result: LifecycleStepResult): boolean {
  return result.kind === "retry_required";
}
