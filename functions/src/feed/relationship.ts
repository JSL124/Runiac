export type FeedRelationshipCheckInput = {
  readonly viewerUid: string;
  readonly authorUid: string;
  readonly viewerHasAuthorFriend: boolean;
  readonly authorHasViewerFriend: boolean;
  readonly viewerBlockedAuthor: boolean;
  readonly authorBlockedViewer: boolean;
};
export type FeedRelationshipDecision =
  | { readonly kind: "allowed_owner" }
  | { readonly kind: "allowed_friend" }
  | { readonly kind: "denied"; readonly reason: "missing_reciprocal_friendship" | "blocked" };

export function evaluateFeedRelationship(input: FeedRelationshipCheckInput): FeedRelationshipDecision {
  if (input.viewerUid === input.authorUid) return { kind: "allowed_owner" };
  if (input.viewerBlockedAuthor || input.authorBlockedViewer) return { kind: "denied", reason: "blocked" };
  if (!input.viewerHasAuthorFriend || !input.authorHasViewerFriend) return { kind: "denied", reason: "missing_reciprocal_friendship" };
  return { kind: "allowed_friend" };
}
