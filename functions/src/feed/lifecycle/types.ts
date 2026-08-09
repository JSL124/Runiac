import type { FeedCleanupResult, FeedCleanupStep } from "../cleanup.js";

export type LifecyclePostStatus = "published" | "deleting";

export type LifecyclePost = {
  readonly postId: string;
  readonly authorUid: string;
  readonly status: LifecyclePostStatus;
  readonly thumbnailStoragePath: string;
  readonly thumbnailObjectGeneration: string;
};

export type FeedReport = {
  readonly reporterUid: string;
  readonly targetType: "feedPost";
  readonly targetId: string;
  readonly reason: "feed_inappropriate";
  readonly description: "";
  readonly createdAt: unknown;
};

export type LifecycleStepResult =
  | { readonly kind: "completed" }
  | { readonly kind: "already_missing" }
  | { readonly kind: "retry_required" };

export type FeedLifecycleTransaction = {
  getPost(postId: string): Promise<LifecyclePost | null>;
  canReadPost(viewerUid: string, post: LifecyclePost): Promise<boolean>;
  getReport(reportId: string): Promise<FeedReport | null>;
  setReport(reportId: string, report: FeedReport): void;
  setHiddenMarker(uid: string, postId: string, createdAt: unknown): void;
  setDeleting(postId: string): void;
};

export type FeedLifecyclePort = {
  runTransaction<T>(operation: (transaction: FeedLifecycleTransaction) => Promise<T>): Promise<T>;
  now(): unknown;
  deleteLikes(postId: string): Promise<LifecycleStepResult>;
  deleteComments(postId: string): Promise<LifecycleStepResult>;
  deleteReportsAndHiddenMarkers(postId: string): Promise<LifecycleStepResult>;
  deleteExactThumbnail(post: LifecyclePost): Promise<LifecycleStepResult>;
  deletePost(postId: string): Promise<LifecycleStepResult>;
};

export type ReportFeedPostInput = {
  readonly port: FeedLifecyclePort;
  readonly reporterUid: string;
  readonly postId: string;
};

export type ReportFeedPostResult =
  | { readonly kind: "reported"; readonly reportId: string; readonly duplicate: boolean }
  | { readonly kind: "denied" }
  | { readonly kind: "missing" };

export type BeginCleanupInput = {
  readonly port: FeedLifecyclePort;
  readonly postId: string;
  readonly ownerUid?: string;
};

export type BeginCleanupResult =
  | { readonly kind: "ready"; readonly post: LifecyclePost }
  | { readonly kind: "denied" }
  | { readonly kind: "already_missing" };

export type DeleteFeedPostResult =
  | { readonly kind: "denied" }
  | { readonly kind: "already_missing" }
  | { readonly kind: "cleanup"; readonly cleanup: FeedCleanupResult };

export type CleanupOperation = {
  readonly step: FeedCleanupStep;
  readonly run: (port: FeedLifecyclePort, post: LifecyclePost) => Promise<LifecycleStepResult>;
};
