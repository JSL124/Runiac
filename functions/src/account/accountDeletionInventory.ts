// The account-deletion data inventory: one ordered description of everything
// deleting a Runiac account removes, anonymizes, and deliberately retains.
//
// This module is pure data with no firebase-admin import, for two reasons. It
// is the artifact a privacy review reads, so it has to be legible without
// tracing execution; and it is unit-testable on its own, so a collection added
// to the app later can be caught by an inventory test rather than only by an
// end-to-end fixture that happens to seed it.
//
// Every path here was read out of `firestore.rules` and `functions/src`, not
// assumed. Where a collection is NOT covered, that is a decision, and the
// decision is recorded in RETAINED_COLLECTIONS below rather than left as a
// silent omission.

// Replaces the uid on records that survive deletion. Deliberately not a random
// token: an admin reading a report needs to see that the account was deleted,
// not an opaque id they will try and fail to look up.
export const DELETED_USER_SENTINEL = "deleted-user";

// Subcollections under users/{uid}. Firestore does not cascade, so deleting the
// parent document leaves every one of these orphaned but still readable by
// collection-group queries — which is exactly how the app reads friend edges.
export const USER_SUBCOLLECTIONS: readonly string[] = [
  "friends",
  "blockedUsers",
  "friendRequests",
  "hiddenFeedPosts",
  "challengeHistory",
  "challengeBadges",
  // The Challenge result ceremony's seen-marker. Client-written presentation
  // state, but still account data, so it goes with the account.
  "challengeState",
];

export type AnonymizeField = {
  readonly field: string;
  // Rewrite only when a sibling field holds this value. `reports.targetId` is
  // the motivating case: it holds a FEED POST id when `targetType` is
  // 'feedPost' and a uid only when `targetType` is 'user', so an unconditional
  // rewrite would corrupt every post report whose id happened to match.
  readonly onlyWhen?: { readonly field: string; readonly equals: string };
};

export type DeletionStep =
  // Exit any live challenge through the shared eviction core BEFORE the
  // participation documents are deleted underneath it.
  | { readonly id: string; readonly kind: "challengeExit" }
  // Read userProfiles/{uid}.avatarObjectPath into the Storage delete list while
  // that document still exists. The durable avatar object is NOT under a uid
  // prefix, so this is the only pointer to it.
  | { readonly id: string; readonly kind: "resolveAvatarObjects" }
  // Authored feed posts, removed through the existing feed cleanup pipeline so
  // likes, comments, thumbnails, and other users' hidden markers go with them.
  | { readonly id: string; readonly kind: "feedPosts" }
  // Documents the runner owns, found by an equality filter on one of `fields`.
  | {
      readonly id: string;
      readonly kind: "ownerQuery";
      readonly collection: string;
      readonly fields: readonly string[];
    }
  // Documents whose id is `{uid}_{suffix}` and which carry no owner field.
  | { readonly id: string; readonly kind: "documentIdPrefix"; readonly collection: string }
  // Rows other users hold about this runner, found by collection-group query.
  //
  // EVERY group/field pair below needs an ASCENDING COLLECTION_GROUP entry in
  // the `fieldOverrides` array of firestore.indexes.json. Firestore creates
  // single-field indexes implicitly only at COLLECTION scope, so an
  // undeclared pair does not degrade — it throws FAILED_PRECONDITION, and
  // because accountDeletionCommand.ts has already disabled the Auth user by
  // then, the runner is locked out of an account that was never erased. That
  // shipped once (the `likes`/`userUid` pair, 2026-08-05); the pairing is now
  // enforced by tests/cross-system/account-deletion-index-drift.mjs.
  | {
      readonly id: string;
      readonly kind: "collectionGroup";
      readonly groups: readonly string[];
      readonly field: string;
    }
  // A single document keyed by uid, plus any subcollections under it.
  | {
      readonly id: string;
      readonly kind: "uidDocument";
      readonly collection: string;
      readonly subcollections?: readonly string[];
    }
  // Records that survive with the uid replaced by DELETED_USER_SENTINEL.
  | {
      readonly id: string;
      readonly kind: "anonymize";
      readonly collection: string;
      readonly fields: readonly AnonymizeField[];
    }
  // A uid-keyed marker document living inside ANOTHER document's subcollection,
  // so it is reachable neither by uid-keyed path nor by field query. Needs a
  // bounded scan of the parent collection.
  | {
      readonly id: string;
      readonly kind: "uidMarkerInSubcollection";
      readonly parentCollection: string;
      readonly subcollection: string;
    }
  // friendCooldowns is keyed by a hash of the uid PAIR and cannot be queried by
  // uid, so it needs a bounded scan rather than a query.
  | { readonly id: string; readonly kind: "friendCooldowns" }
  // Storage prefixes plus whatever resolveAvatarObjects collected.
  | { readonly id: string; readonly kind: "storage" }
  // Last, deliberately: while the Auth record exists the uid stays reserved and
  // a partial fan-out can be resumed and audited.
  | { readonly id: string; readonly kind: "authUser" };

// Order is load-bearing. Two constraints in particular are not cosmetic:
// `challenge-exit` must precede any deletion of participation state, and
// `avatar-objects` must precede `identity-documents`, which deletes the
// userProfiles document holding the only pointer to the durable avatar object.
export const ACCOUNT_DELETION_STEPS: readonly DeletionStep[] = [
  { id: "challenge-exit", kind: "challengeExit" },
  { id: "avatar-objects", kind: "resolveAvatarObjects" },
  { id: "feed-posts", kind: "feedPosts" },

  {
    id: "feed-engagement",
    kind: "collectionGroup",
    groups: ["likes"],
    field: "userUid",
  },
  {
    // This step is why `comments.authorUid` carries a `fieldOverrides` entry in
    // `firestore.indexes.json` rather than relying on automatic indexing.
    //
    // That entry must keep declaring BOTH scopes. A fieldOverrides entry
    // REPLACES automatic single-field indexing, so listing only the
    // COLLECTION_GROUP index this sweep needs deletes the COLLECTION-scope ones
    // the Feed's per-post viewer probe queries on
    // (`FirebaseFeedPostMapper.mapReference`), which takes the whole timeline
    // down with `failed-precondition`. Adding a scope here is safe; narrowing
    // the override to one scope is not.
    id: "feed-comments",
    kind: "collectionGroup",
    groups: ["comments"],
    field: "authorUid",
  },
  // The mirror rows other runners hold. This is the same collection-group shape
  // `nicknameFanoutReferences` already queries to fan a rename out, so these
  // three indexes predate this step rather than being added for it — which is
  // why the gap in the other steps went unnoticed until a real deletion ran.
  {
    id: "social-mirrors",
    kind: "collectionGroup",
    groups: ["friends", "friendRequests", "blockedUsers"],
    field: "uid",
  },
  // Other runners' inbox entries ABOUT this runner. Deleted rather than
  // anonymized: the actor's nickname is baked into the rendered title/body
  // prose, so there is no field to overwrite.
  {
    id: "inbox-mentions",
    kind: "collectionGroup",
    groups: ["items"],
    field: "data.actorUid",
  },

  { id: "activities", kind: "ownerQuery", collection: "activities", fields: ["ownerUid"] },
  { id: "run-summaries", kind: "ownerQuery", collection: "runSummaries", fields: ["ownerUid"] },
  {
    id: "progression-events",
    kind: "ownerQuery",
    collection: "progressionEvents",
    fields: ["ownerUid"],
  },
  { id: "shared-routes", kind: "ownerQuery", collection: "sharedRoutes", fields: ["ownerUid"] },
  {
    id: "leaderboard-contributions",
    kind: "ownerQuery",
    collection: "leaderboardContributions",
    fields: ["ownerUid"],
  },
  {
    id: "leaderboard-ranks",
    kind: "ownerQuery",
    collection: "leaderboardUserRanks",
    fields: ["ownerUid"],
  },
  {
    id: "notification-deliveries",
    kind: "ownerQuery",
    collection: "notificationDeliveries",
    fields: ["ownerUid"],
  },
  // Both directions: invitations this runner sent and invitations they received.
  {
    id: "challenge-invitations",
    kind: "ownerQuery",
    collection: "challengeInvitations",
    fields: ["ownerUid", "recipientUid"],
  },

  // agentGuidanceDaily/{uid}_{dayKey} carries no owner field.
  { id: "agent-guidance", kind: "documentIdPrefix", collection: "agentGuidanceDaily" },

  { id: "friend-cooldowns", kind: "friendCooldowns" },

  {
    id: "reports",
    kind: "anonymize",
    collection: "reports",
    fields: [
      { field: "reporterUid" },
      { field: "targetId", onlyWhen: { field: "targetType", equals: "user" } },
    ],
  },
  { id: "feedback", kind: "anonymize", collection: "feedback", fields: [{ field: "uid" }] },
  {
    id: "challenge-reward-grants",
    kind: "anonymize",
    collection: "challengeRewardGrants",
    fields: [{ field: "uid" }],
  },

  {
    id: "identity-documents",
    kind: "uidDocument",
    collection: "users",
    subcollections: USER_SUBCOLLECTIONS,
  },
  { id: "user-profile", kind: "uidDocument", collection: "userProfiles" },
  { id: "generated-plans", kind: "uidDocument", collection: "generatedPlans" },
  { id: "plan-progress", kind: "uidDocument", collection: "planProgress" },
  { id: "adaptive-estimates", kind: "uidDocument", collection: "adaptivePlanEstimates" },
  { id: "home-guide-consents", kind: "uidDocument", collection: "homeGuideConsents" },
  {
    id: "notification-devices",
    kind: "uidDocument",
    collection: "notificationDevices",
    subcollections: ["tokens"],
  },
  {
    id: "notification-inbox",
    kind: "uidDocument",
    collection: "notificationInbox",
    subcollections: ["items"],
  },
  { id: "notification-preferences", kind: "uidDocument", collection: "notificationPreferences" },
  { id: "challenge-slots", kind: "uidDocument", collection: "challengeSlots" },
  { id: "challenge-premium-holds", kind: "uidDocument", collection: "challengePremiumHolds" },
  { id: "leaderboard-current-view", kind: "uidDocument", collection: "leaderboardCurrentViews" },
  { id: "friend-rate-limits", kind: "uidDocument", collection: "friendRateLimits" },
  {
    id: "error-report-rate-limits",
    kind: "uidDocument",
    collection: "errorReportRateLimit",
    subcollections: ["events"],
  },
  // errorGroups/{groupId}/reporters/{uid}. A collection-group query cannot find
  // it: the marker carries no uid FIELD (the uid is the document id), and
  // FieldPath.documentId() comparisons in a collection-group query are matched
  // against full resource paths, not bare ids. Hence the bounded parent scan.
  {
    id: "error-reporter-markers",
    kind: "uidMarkerInSubcollection",
    parentCollection: "errorGroups",
    subcollection: "reporters",
  },

  { id: "storage", kind: "storage" },
  { id: "auth-user", kind: "authUser" },
];

// Storage prefixes owned by the runner. The durable avatar is absent by design:
// `avatarPaths.ts` mints `avatars/{32-hex}.png` with an opaque id, so it is
// resolved at run time by the `avatar-objects` step instead.
export function accountStoragePrefixes(uid: string): readonly string[] {
  return [
    `feed-thumbnails/${uid}/`,
    `feed-thumbnail-staging/${uid}/`,
    `share-cards/${uid}/`,
    `avatar-staging/${uid}/`,
  ];
}

// Collections that deliberately survive an account deletion untouched, with the
// reason. Kept as data so a reviewer can audit the decisions in one place and
// so a test can assert the two lists do not overlap.
export const RETAINED_COLLECTIONS: readonly {
  readonly collection: string;
  readonly reason: string;
}[] = [
  {
    collection: "adminAuditLogs",
    reason:
      "Records Platform Administrator actions, not runner activity. Rewriting it would let " +
      "the subject of an administrative action edit the audit trail of that action.",
  },
  {
    collection: "newsletterSubscribers",
    reason:
      "Keyed by email address, not uid, and has its own confirm/unsubscribe endpoints. " +
      "Explicitly placed out of scope by the user when this capsule was routed.",
  },
  {
    collection: "accountDeletionCommands",
    reason:
      "The deletion's own record. Keyed by the uid so a double request is idempotent, and " +
      "retained afterwards so an operator can answer 'was this account actually erased, and " +
      "how much did each step remove'. Holds the uid, timestamps, and per-step counts — no " +
      "profile, activity, or location data. A re-signup receives a new uid, so a retained " +
      "record never collides with the person who deleted it.",
  },
  {
    collection: "errorGroups",
    reason:
      "The aggregate error group carries no identity; only its uid-keyed reporters marker " +
      "is deleted, by the error-reporter-markers step.",
  },
  {
    collection: "leaderboardSnapshots",
    reason:
      "A published snapshot row (LeaderboardPublicEntry) deliberately carries NO ownerUid — " +
      "see leaderboardTypes.ts:52-57, where the omission is what stops a world-readable " +
      "snapshot from disclosing every ranked runner's uid. There is therefore no way to find " +
      "this runner's row by uid, and matching on publicAlias would risk rewriting a different " +
      "runner's row on a nickname collision. The row is instead superseded by the hourly " +
      "refreshLeaderboardSnapshots pass, which rebuilds snapshots from leaderboardContributions " +
      "that this fan-out has already deleted. Residue window: up to one hour, carrying a public " +
      "alias and a score but no identifier.",
  },
];

export function accountDeletionStepIds(): readonly string[] {
  return ACCOUNT_DELETION_STEPS.map((step) => step.id);
}
