// Narrow row types for the Admin-SDK Firestore accessors.
//
// These describe exactly what src/lib/firebase/firestore.ts returns after
// converting Firestore Timestamps to ISO strings. They deliberately do NOT
// import from src/lib/admin/ (owned by another agent) so this Firebase layer
// stays self-contained; the wiring phase maps these rows onto the admin UI
// view models.

export type FirestoreUserRole = "runner" | "platformAdmin";

export type FirestoreSubscriptionStatus = "basic" | "premium";

export type ReportResolutionStatus =
  | "pending"
  | "reviewing"
  | "resolved"
  | "dismissed";

export type FeedbackTriageStatus =
  | "new"
  | "responded"
  | "resolved"
  | "dismissed"
  | "escalated";

export type AdminUserRow = {
  uid: string;
  displayName: string | null;
  nickname: string | null;
  email: string | null;
  userRole: FirestoreUserRole | string;
  subscriptionStatus: FirestoreSubscriptionStatus | string;
  subscriptionExpiresAt: string | null;
  accountStatus: string | null;
  locationLabel: string | null;
  fitnessLevel: string | null;
  createdAt: string | null;
  totalXp: number | null;
  level: number | null;
  monthlyXp: number | null;
  // Whether userProfiles/{uid} currently has a live avatarObjectPath. Drives
  // the admin console's "Clear avatar" control (src/components/admin/
  // UserOperationsPanel.tsx): disabled when there is nothing to take down.
  hasAvatar: boolean;
};

export type ReportRow = {
  id: string;
  reporterUid: string | null;
  targetType: string | null;
  targetId: string | null;
  reason: string | null;
  description: string | null;
  resolutionStatus: ReportResolutionStatus | string;
  resolutionNote: string | null;
  createdAt: string | null;
  // Present on reports created by the admin console's anomaly-detection flow
  // (src/lib/firebase/firestore.ts#createLeaderboardReport); absent (null) on
  // reports the client app writes directly, which are always user reports.
  source: string | null;
};

export type FeedbackRow = {
  id: string;
  uid: string | null;
  category: string | null;
  message: string | null;
  summary: string | null;
  severity: string | null;
  status: FeedbackTriageStatus | string | null;
  duplicateCount: number | null;
  note: string | null;
  closed: boolean;
  receivedAt: string | null;
};

export type ErrorGroupTriageStatus =
  | "new"
  | "investigating"
  | "resolved"
  | "ignored";

// Mirrors errorGroups/{fingerprint} as written by
// functions/src/errors/reportAppError.ts and functions/src/errors/reportBackendError.ts
// — see ErrorGroupDocument in functions/src/errors/errorGroupStore.ts for the
// authoritative shape. Note the doc field is `os` (not `osVersion`) and
// `affectedUserCount` (not `affectedUsers`). `source` is read raw here
// (string | null); the admin-console layer (src/lib/admin/live-data.ts)
// coerces it to the narrow "mobile" | "functions" union, defaulting absent
// or unrecognized values to "mobile" so documents written before the
// backend-capture feature shipped still render correctly.
export type ErrorGroupRow = {
  id: string;
  title: string | null;
  errorType: string | null;
  screen: string | null;
  appVersion: string | null;
  os: string | null;
  platform: string | null;
  source: string | null;
  occurrences: number | null;
  affectedUsers: number | null;
  severity: string | null;
  status: ErrorGroupTriageStatus | string | null;
  firstSeenAt: string | null;
  lastSeenAt: string | null;
  stackSummary: string | null;
  sanitized: boolean;
  note: string | null;
};

export type ActivitySummaryRow = {
  id: string;
  ownerUid: string | null;
  validationStatus: string | null;
  distanceMeters: number | null;
  durationSeconds: number | null;
  startedAt: string | null;
  createdAt: string | null;
};

// Mirrors a single element of `leaderboardSnapshots.{doc}.topEntries` as
// written by functions/src/leaderboard/monthlyLeaderboardPlanner.ts. There is
// deliberately no `uid`/`displayName`/numeric `rank` field here — the backend
// only ever persists the pre-formatted public-facing labels.
export type LeaderboardEntry = {
  publicAlias: string | null;
  rankLabel: string | null;
  scoreLabel: string | null;
  levelLabel: string | null;
  divisionLabel: string | null;
  regionLabel: string | null;
  score: number | null;
};

// Mirrors a `leaderboardSnapshots` document as written by
// functions/src/leaderboard/monthlyLeaderboardWriter.ts. `generatedAt` /
// `refreshesAt` are ISO strings on the backend already; `refreshesAt` is the
// month-rollover boundary, not the next scheduled aggregation run.
export type LeaderboardSnapshotRow = {
  id: string;
  periodKey: string | null;
  periodLabel: string | null;
  regionId: string | null;
  divisionKey: string | null;
  regionLabel: string | null;
  divisionLabel: string | null;
  buildId: string | null;
  generatedAt: string | null;
  refreshesAt: string | null;
  aggregationStatus: string | null;
  entryCount: number | null;
  entries: LeaderboardEntry[];
};

// Mirrors `leaderboardPeriods/monthly_current` as written by
// functions/src/leaderboard/monthlyLeaderboardWriter.ts. This is the entry
// point the mobile app reads first to know which period/build the whole
// leaderboard is currently serving — if it is stale, the whole app
// leaderboard is stale, regardless of what any individual snapshot says.
export type LeaderboardCurrentPeriodRow = {
  periodType: string | null;
  periodKey: string | null;
  periodLabel: string | null;
  timezone: string | null;
  refreshesAt: string | null;
  buildId: string | null;
  generatedAt: string | null;
  aggregationStatus: string | null;
  updatedAt: string | null;
};

// The four terminal + one active status values written onto
// `leaderboardCurrentViews/{ownerUid}` by
// functions/src/leaderboard/monthlyLeaderboardWriter.ts.
export type LeaderboardCurrentViewStatus =
  | "ranked"
  | "unranked"
  | "region_required"
  | "ineligible_premium"
  | "ineligible_min_runs";

// Per-status document counts over `leaderboardCurrentViews`, one document per
// user. Read via `.count()` aggregate queries (see
// countLeaderboardCurrentViewsByStatus in ../firebase/firestore.ts) rather
// than a full collection scan, since this collection has one document per
// user.
export type LeaderboardCurrentViewStatusCounts = Record<
  LeaderboardCurrentViewStatus,
  number
>;

// A `leaderboardSnapshots` document's index metadata WITHOUT `topEntries` —
// used for the coverage view, which only needs to know a snapshot exists and
// how big it is, not who is in it. See listLeaderboardSnapshotSummaries() in
// ../firebase/firestore.ts.
export type LeaderboardSnapshotSummaryRow = {
  id: string;
  periodKey: string | null;
  regionId: string | null;
  divisionKey: string | null;
  regionLabel: string | null;
  divisionLabel: string | null;
  entryCount: number | null;
  generatedAt: string | null;
};

export type LeaderboardAggregationLockStatus =
  | "running"
  | "completed"
  | "failed";

// Mirrors `leaderboardAggregationLocks/monthly_{periodKey}` as written by
// functions/src/leaderboard/monthlyLeaderboardWriter.ts. All timestamps are
// ISO strings on the backend already; the lease duration is 15 minutes.
export type LeaderboardAggregationLockRow = {
  periodKey: string;
  buildId: string | null;
  status: LeaderboardAggregationLockStatus | string;
  startedAt: string | null;
  completedAt: string | null;
  failedAt: string | null;
  leaseExpiresAt: string | null;
  updatedAt: string | null;
};

// Mirrors a `leaderboardContributions/{ownerUid}_monthly_{periodKey}` document
// as written by functions/src/leaderboard/monthlyLeaderboard.ts
// (leaderboardContributionFields/writeLeaderboardContribution), read here only
// for anomaly detection (src/lib/admin/live-data.ts#getLiveSuspiciousScores)
// — the admin console never writes this collection. `qualifyingRunCount` is
// genuinely optional on the backend type (absent until a `countsAsRun: true`
// write resolves it); `mockSeedRunId` is not part of the real writer's schema
// at all and only appears on documents created by the emulator-only seed CLI
// (functions/src/leaderboard/leaderboardMockDataset.ts), so both are read
// tolerantly here.
export type LeaderboardContributionRow = {
  id: string;
  ownerUid: string | null;
  publicAlias: string | null;
  regionId: string | null;
  regionLabel: string | null;
  planningAreaName: string | null;
  divisionKey: string | null;
  divisionLabel: string | null;
  levelLabel: string | null;
  periodKey: string | null;
  scoreXp: number | null;
  eligible: boolean | null;
  eligibilityReason: string | null;
  lastProgressionAt: string | null;
  sourceProgressionEventIds: string[];
  qualifyingRunCount: number | null;
  mockSeedRunId: string | null;
};

export type LeaderboardCommandStatus =
  | "pending"
  | "completed"
  | "skipped_locked"
  | "rejected"
  | "failed";

// Mirrors a `leaderboardAdminCommands/{commandId}` document: written by the
// admin console (the recalculation request) and completed by the
// leaderboardAdminCommandCreated Cloud Function trigger
// (functions/src/leaderboard/leaderboardAdminCommand.ts), which runs the real
// aggregation and merge-writes the outcome back onto the same document. The
// console never computes the outcome itself — this row is always read back
// from what the backend actually did.
export type LeaderboardCommandRow = {
  status: LeaderboardCommandStatus | string;
  error: string | null;
  buildId: string | null;
  snapshotCount: number | null;
  rankCount: number | null;
  currentViewCount: number | null;
  completedAt: string | null;
};

export type ModerationCommandStatus = "pending" | "completed" | "failed";

// Mirrors a `moderationCommands/{commandId}` document: written by the admin
// console (a content-moderation request, e.g. removing a reported feed post)
// and completed by the moderationCommandCreated Cloud Function trigger
// (functions/src/moderation/moderationCommand.ts), which performs the real
// removal and merge-writes the outcome back onto the same document. The
// console never writes to `feedPosts` directly. `removedAuthorUid` is only
// populated when this specific command actually removed a post — see the
// trigger's own comment for why that field exists at all.
export type ModerationCommandRow = {
  status: ModerationCommandStatus | string;
  error: string | null;
  removedAuthorUid: string | null;
  completedAt: string | null;
};

// Mirrors an `adminNotifications/{id}` document: backend-written attention
// items surfaced on the admin overview (e.g. a new critical error group, a
// stale-report escalation). Cloud Functions triggers write `status: "unread"`;
// the console's dismiss action writes "dismissed"; "active" covers documents
// with a missing/unknown status. listAdminNotifications() filters by
// EXCLUSION (`status !== "dismissed"`) — never gate on `=== "unread"` or
// `=== "active"`, the two undismissed spellings must stay interchangeable.
// The in-memory filter (vs a Firestore `.where("status", "!=", ...)`) keeps
// this collection free of composite indexes.
export type AdminNotificationStatus = "unread" | "active" | "dismissed";

export type AdminNotificationRow = {
  id: string;
  kind: string | null;
  severity: string | null;
  title: string | null;
  detail: string | null;
  href: string | null;
  createdAt: string | null;
  status: AdminNotificationStatus | string;
};

export type AuditLogRow = {
  id: string;
  actor: string | null;
  action: string | null;
  targetType: string | null;
  targetId: string | null;
  detail: string | null;
  createdAt: string | null;
};

// A single `config/{name}` change recovered from the audit log. Unlike
// AuditLogRow this keeps the payload fields (`after`, `changedFields`) that the
// config-history UI needs in order to show — and restore — an earlier snapshot.
export type ConfigHistoryRow = {
  id: string;
  actor: string | null;
  action: string | null;
  targetId: string | null;
  changedFields: string[];
  after: Record<string, unknown> | null;
  createdAt: string | null;
};

export type SubscriptionCounts = {
  basic: number;
  premium: number;
  other: number;
  total: number;
};

// --- config docs (config/{name}) ---------------------------------------------
//
// Narrow rows for the admin console's editable backend configuration docs.
// Progression/leaderboard/featureAccess config shapes live in
// src/lib/admin/config-validation.ts (mirroring
// functions/src/config/configLoader.ts) rather than here, since they are
// strongly typed value objects rather than Firestore-row shapes with
// Timestamp coercion.

export type SiteContentFaqRow = {
  id: string;
  question: string;
  answer: string;
};

export type SiteContentRow = {
  announcementText: string | null;
  announcementEnabled: boolean | null;
  heroHeadline: string | null;
  heroSubtext: string | null;
  // Structured pricing-page content (config/siteContent.pricing). Stored as an
  // opaque value here and normalized by mergeSitePricing() at every read
  // boundary, so a missing/partial/malformed document still renders safely.
  pricing: unknown;
  // Structured testimonials-section content (config/siteContent.testimonials).
  // Opaque here and normalized by mergeSiteTestimonials() at every read boundary.
  testimonials: unknown;
  // Structured "problem" section content (config/siteContent.problem). Opaque
  // here and normalized by mergeSiteProblem() at every read boundary.
  problem: unknown;
  // Structured "solution" section content (config/siteContent.solution). Opaque
  // here and normalized by mergeSiteSolution() at every read boundary.
  solution: unknown;
  // Structured "personalized plan" section content
  // (config/siteContent.personalizedPlan). Opaque here and normalized by
  // mergeSitePersonalizedPlan() at every read boundary.
  personalizedPlan: unknown;
  // Structured split-highlight sections (config/siteContent.xpProgression /
  // .territorial / .postRunSummary). Opaque here; normalized by the matching
  // merge helpers at every read boundary.
  journeyMap: unknown;
  xpProgression: unknown;
  territorial: unknown;
  postRunSummary: unknown;
  // Admin-console-only section labels + display order
  // (config/siteContent.sectionTitles / .sectionOrder).
  sectionTitles: unknown;
  sectionOrder: unknown;
  faqs: SiteContentFaqRow[] | null;
  // About-page team section (heading + member cards + supervisor). Opaque here;
  // normalized by mergeSiteTeam() at every read boundary.
  team: unknown;
  // Documents-page content (heading + intro + document cards). Opaque here;
  // normalized by mergeSiteDocuments() at every read boundary.
  documents: unknown;
  // Download-page content (Android/iOS cards, install steps, requirements).
  // Opaque here; normalized by mergeSiteDownload() at every read boundary.
  download: unknown;
};

// --- newsletter (newsletterSubscribers/{sha256(emailLower)},
//     newsletterCampaigns/{id}) ------------------------------------------------
//
// Written by the `subscribeNewsletter` callable (subscribers) and by the
// Firestore-trigger-driven send pipeline (campaigns) — see the backend
// contract in the newsletter capsule. The admin console only ever flips a
// campaign's `status` / writes `testRecipients`; it never fans out mail
// itself. `ipHash` and any token-hash fields on the subscriber document are
// deliberately NOT modeled here, so they can never be read into an admin-UI
// row.

export type NewsletterSubscriberStatus =
  | "pending"
  | "confirmed"
  | "unsubscribed"
  | "bounced";

export type NewsletterSubscriberRow = {
  id: string;
  emailLower: string | null;
  status: NewsletterSubscriberStatus | string | null;
  source: string | null;
  consentAt: string | null;
  confirmedAt: string | null;
  unsubscribedAt: string | null;
  sendFailureCount: number | null;
  createdAt: string | null;
  updatedAt: string | null;
};

export type NewsletterCampaignStatus =
  | "draft"
  | "testQueued"
  | "queued"
  | "sending"
  | "sent"
  | "failed";

export type NewsletterCampaignRow = {
  id: string;
  subject: string | null;
  bodyMarkdown: string | null;
  status: NewsletterCampaignStatus | string | null;
  createdBy: string | null;
  createdAt: string | null;
  queuedAt: string | null;
  sentAt: string | null;
  recipientCount: number | null;
  deliveredCount: number | null;
  failedCount: number | null;
  testRecipients: string[];
  lastTestSentAt: string | null;
  error: string | null;
};

// A single newsletterCampaigns/{id}/deliveries/{subscriberId} document — the
// per-recipient send outcome the trigger writes, surfaced read-only so the
// console can show which specific sends failed and why.
export type NewsletterDeliveryRow = {
  id: string;
  status: string | null;
  error: string | null;
};
