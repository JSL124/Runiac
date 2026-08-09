// Type definitions for the Platform Administrator console.
//
// These describe the shapes the admin UI renders. In production they are backed
// by Firebase / Cloud Functions APIs; here they are populated by the placeholder
// data in ./mock-data.ts. The admin console reads backend-owned state and edits
// rule *configuration* only — it never computes or writes user XP, rank, streak,
// or leaderboard scores directly.

// Backend-owned config doc types (config/progression, config/leaderboard,
// config/featureAccess) live in ./config-validation.ts, mirroring
// functions/src/config/configLoader.ts field-for-field. Re-exported here so
// admin-console code can import config types alongside the view types below
// without reaching into config-validation.ts directly.
export type {
  AutomationConfig,
  ConfigValidationResult,
  FeatureAccessConfig,
  FeatureAccessEntry,
  LeaderboardConfig,
  ProgressionConfig,
  ProgressionCoolDownConfig,
} from "./config-validation";

// Canonical structured pricing/testimonials schemas (config/siteContent.*)
// shared with the marketing render layer. Re-exported so admin-console code can
// import them alongside the view types below.
export type { SitePricing, SitePricingTier } from "@/lib/site-pricing";
export type { SiteTestimonial, SiteTestimonials } from "@/lib/site-testimonials";
export type { SiteProblem, ProblemChartPoint } from "@/lib/site-problem";
export type { SiteSolution } from "@/lib/site-solution";
export type { SitePersonalizedPlan } from "@/lib/site-personalized-plan";
export type { SiteHighlight, SitePostRunSummary } from "@/lib/site-highlight";
export type { SiteSectionTitles, SectionTitleKey } from "@/lib/site-section-titles";
export type {
  SiteTeam,
  SiteTeamMember,
  SiteTeamSupervisor,
} from "@/lib/site-team";
export type { SiteDocuments, SiteDocumentCard } from "@/lib/site-documents";
export type { SiteDownload, SiteDownloadStep } from "@/lib/site-download";
import type { SitePricing } from "@/lib/site-pricing";
import type { SiteTestimonials } from "@/lib/site-testimonials";
import type { SiteProblem } from "@/lib/site-problem";
import type { SiteSolution } from "@/lib/site-solution";
import type { SitePersonalizedPlan } from "@/lib/site-personalized-plan";
import type { SiteHighlight, SitePostRunSummary } from "@/lib/site-highlight";
import type {
  SiteSectionTitles,
  SectionTitleKey,
} from "@/lib/site-section-titles";
import type { SiteTeam } from "@/lib/site-team";
import type { SiteDocuments } from "@/lib/site-documents";
import type { SiteDownload } from "@/lib/site-download";

export type Severity = "low" | "medium" | "high" | "critical";

export type SystemStatus = "operational" | "degraded" | "down";

// Field names below mirror the Firestore schema so the mock -> live swap in
// src/lib/admin/data.ts touches no UI code. Human-readable labels are derived
// via helpers in src/lib/admin/format.ts.
export type UserRole = "runner" | "platformAdmin";

export type SubscriptionStatus = "basic" | "premium";

export type AccountStatus = "active" | "suspended" | "banned";

// --- Overview ---------------------------------------------------------------

export type OverviewStat = {
  id: string;
  label: string;
  value: number;
  hint: string;
  tone: "neutral" | "accent" | "critical";
  href?: string;
};

export type SystemHealthComponent = {
  id: string;
  name: string;
  description: string;
  status: SystemStatus;
  lastCheckedAt: string;
};

export type AttentionItem = {
  id: string;
  title: string;
  detail: string;
  severity: Severity;
  href: string;
};

export type ActiveUsersPoint = {
  label: string;
  activeUsers: number;
};

// --- Exception Queue --------------------------------------------------------

// Moderation + integrity cases only. Crash/error signals live on the Errors &
// Crashes page (ErrorGroup) and general product complaints live on the
// Feedback page (FeedbackItem) — the Exception Queue's job is strictly
// "cases where a user may have harmed another user or gamed the system".
// `unclassified` is the safe fallback for a `reports` document whose
// `targetType` is absent or unrecognized; it must never be silently mapped
// onto one of the real moderation types below. It is not decoration:
// firestore.rules `match /reports/{reportId}` constrains who may create a
// report and forbids targetType 'feedPost' from clients, but it does NOT
// allowlist the value itself, so an authenticated client can still write an
// unrecognized targetType. This type is what keeps such a document visible
// and honestly labelled instead of rendering a blank case type.
//
// Only the three types below are produced today, one per writer:
//   reported-feed-post  <- functions/src/feed/lifecycle/core.ts
//   reported-user       <- the app's report_user_writer.dart
//   suspicious-xp       <- createLeaderboardReport() (Leaderboard Oversight)
export type ExceptionType =
  | "reported-feed-post"
  | "reported-user"
  | "suspicious-xp"
  | "unclassified";

export type ExceptionSource = "user-report" | "anomaly-detection";

export type ExceptionStatus = "pending" | "reviewing" | "resolved" | "dismissed";

export type ExceptionCase = {
  id: string;
  type: ExceptionType;
  severity: Severity;
  summary: string;
  source: ExceptionSource;
  status: ExceptionStatus;
  createdAt: string;
  subjectLabel: string;
  details: string[];
  sanitized: boolean;
  // Present when the case originated from the `reports` collection.
  reporterUid?: string;
  targetType?: ReportTargetType;
  targetId?: string;
  reason?: string;
  // reported-feed-post cases only. `reports` never stores the post author's
  // uid (see functions/src/moderation/moderationCommand.ts), so this is
  // resolved server-side in src/lib/admin/live-data.ts by reading
  // feedPosts/{targetId}.authorUid, falling back to the removedAuthorUid a
  // prior moderationCommands removal recorded once the post itself is gone.
  // Undefined when neither source can resolve it (e.g. the post was never
  // removed through this console and no longer exists), which is exactly
  // what suspensionTarget() in ExceptionQueue.tsx keys off to disable
  // "Suspend user" with a reason rather than silently no-opping.
  authorUid?: string;
  // Count of OTHER `reports` documents sharing this case's targetId — a
  // repeat-offender / repeat-report signal computed in-memory in
  // getLiveExceptionCases() from the already-fetched report set, never a
  // second Firestore query or composite index. Undefined when targetId is
  // absent.
  duplicateReportCount?: number;
};

// Direct mirror of the Firestore `reports` collection. User reports feed the
// Exception Queue (as ExceptionCase entries with source "user-report").
// "feedPost" is written by reportFeedPostCore()
// (functions/src/feed/lifecycle/core.ts) when a runner reports a feed post.
// "activity" is written by createLeaderboardReport() from Leaderboard
// Oversight. "user" is written by the app's report_user_writer.dart.
//
// "route" and "plan" are deliberately absent: no writer has ever produced
// either. Anything unrecognized falls through toCaseType() to
// "unclassified" rather than being narrowed here.
export type ReportTargetType = "user" | "activity" | "feedPost";

export type ReportResolutionStatus =
  | "pending"
  | "reviewing"
  | "resolved"
  | "dismissed";

export type Report = {
  id: string;
  reporterUid: string;
  targetType: ReportTargetType;
  targetId: string;
  reason: string;
  description: string;
  createdAt: string;
  resolutionStatus: ReportResolutionStatus;
};

// Mirror of `activities` / `runSummaries`. Surfaced only as anomaly signals in
// the Exception Queue and leaderboard oversight; never edited by the admin.
export type ActivityValidationStatus =
  | "valid"
  | "flagged"
  | "invalid"
  | "pending";

export type Activity = {
  id: string;
  ownerUid: string;
  validationStatus: ActivityValidationStatus;
  distanceMeters: number;
  durationSeconds: number;
  recordedAt: string;
};

// --- Users ------------------------------------------------------------------

export type AdminUser = {
  id: string;
  uid: string;
  displayName: string;
  nickname: string;
  email: string;
  userRole: UserRole;
  subscriptionStatus: SubscriptionStatus;
  // ISO instant an admin-granted Premium lapses, or null when it never does.
  subscriptionExpiresAt: string | null;
  accountStatus: AccountStatus;
  // Resolved from the Firebase Auth record's creationTime, since no Firestore
  // document carries one. Null for a uid with no Auth account — a seeded or
  // imported directory row — which the table renders as a dash.
  joinedAt: string | null;
  region: string;
  note: string;
  totalXp: number | null;
  level: number | null;
  monthlyXp: number | null;
  // Whether the user currently has a live avatar object. Optional because the
  // placeholder mock directory (./mock-data.ts) predates the avatar feature
  // and has no such field; getLiveUsers() in ./live-data.ts always sets a
  // real boolean. Undefined is treated the same as false by the UI — never
  // enabling a takedown control on data that cannot confirm an avatar exists.
  hasAvatar?: boolean;
};

export type AdminActionLogEntry = {
  id: string;
  actor: string;
  action: string;
  target: string;
  timestamp: string;
};

// --- Gamification -----------------------------------------------------------

export type XpRule = {
  id: string;
  action: string;
  description: string;
  xp: number;
};

export type LevelThreshold = {
  level: number;
  xpRequired: number;
};

export type StreakReward = {
  id: string;
  milestoneDays: number;
  bonusXp: number;
};

// One recorded change to a backend configuration document, derived from the
// admin audit log rather than a dedicated history collection. `active` marks
// the newest entry — the snapshot currently applied — and `restored` marks an
// entry that was itself produced by restoring an earlier snapshot.
export type ConfigVersionEntry = {
  id: string;
  version: number | null;
  actor: string;
  savedAt: string;
  changedFields: string[];
  restored: boolean;
  active: boolean;
};

// --- Leaderboard ------------------------------------------------------------

export type AggregationJob = {
  name: string;
  lastRunAt: string;
  durationSeconds: number;
  status: SystemStatus;
  nextRunAt: string;
  // Real fields surfaced once the job is backed by a live snapshot + lock
  // (see src/lib/admin/live-data.ts#getLiveAggregationJob). Null when the
  // underlying document does not have the field (e.g. no lock has been taken
  // for this period yet).
  periodKey: string | null;
  buildId: string | null;
  startedAt: string | null;
  // True when the lock is still `status: "running"` past its leaseExpiresAt
  // — the job claimed a lease and never released it (a stuck run), rather
  // than a run that is merely in progress.
  staleLease: boolean;
};

export type LeaderboardSettings = {
  seasonLengthDays: number;
  regionalGrouping: boolean;
  minRunsToQualify: number;
};

// Fixed catalog sizes for Runiac's monthly leaderboard: 37 supported
// Singapore planning areas (regions) and 10 league tiers (divisions).
// Mirrors functions/src/leaderboard/singaporePlanningAreas.ts and
// functions/src/leaderboard/leaderboardLeagues.ts. Not imported directly —
// website/ and functions/ are separate packages with no shared import
// boundary — so these are exported here as plain numbers, and the full
// region/division catalogs are hardcoded in
// src/components/admin/LeaderboardOversight.tsx, so the coverage summary and
// the standings viewer always agree on the same totals.
export const TOTAL_SUPPORTED_LEADERBOARD_REGIONS = 37;
export const TOTAL_LEADERBOARD_LEAGUE_TIERS = 10;

// Mirrors leaderboardPeriods/monthly_current — the single document the
// mobile app reads first to know which period/build the whole leaderboard is
// currently serving. Distinct from AggregationJob below: this is the
// app-facing period state, while AggregationJob is the operational,
// lock-derived health of the backend job that produces it.
export type LeaderboardCurrentPeriod = {
  periodKey: string | null;
  periodLabel: string | null;
  timezone: string | null;
  refreshesAt: string | null;
  buildId: string | null;
  generatedAt: string | null;
  aggregationStatus: string | null;
};

// Per-status counts over leaderboardCurrentViews/{ownerUid}, one document per
// user.
//
// `total` is NOT the size of the user base. A currentView document only comes
// into existence once its owner has produced a leaderboardContribution — see
// monthlyLeaderboardWriter.ts, which plans views from this period's
// contributions and rolls over the ones that already exist. Someone who signed
// up and never completed a run is absent from the whole collection, which is
// why `registeredUsers` is carried alongside: the difference between the two is
// the never-ran cohort, and without it the page cannot express participation as
// a share of anything.
//
// `regionRequired` is a health signal, not a user-behaviour one. The profile
// form only stores a label the shared planning-area catalog already contains
// (validateLocationLabel in user_profile_persistence_repository.dart), so a
// non-zero count means the stored label stopped resolving — a regenerated
// catalog, a renamed area with no alias, or a half-finished account deletion
// that removed userProfiles/{uid} while leaving the view behind.
export type LeaderboardParticipationBreakdown = {
  ranked: number;
  unranked: number;
  regionRequired: number;
  ineligiblePremium: number;
  ineligibleMinRuns: number;
  total: number;
  registeredUsers: number;
};

// One `leaderboardSnapshots` document's index metadata, without
// `topEntries` — the coverage view only needs to know a snapshot exists and
// how big it is.
export type LeaderboardSnapshotSummary = {
  id: string;
  periodKey: string | null;
  regionId: string | null;
  divisionKey: string | null;
  regionLabel: string | null;
  divisionLabel: string | null;
  entryCount: number | null;
  generatedAt: string | null;
};

// Aggregate coverage over every leaderboardSnapshots document: how many
// exist, how much of the region x division grid they cover, and which
// period keys still have data. Retention keeps the current month plus the 2
// previous months (see retainedPeriodKeys() in
// functions/src/leaderboard/monthlyLeaderboardPeriod.ts); older period
// projections are deleted by the backend.
export type LeaderboardCoverageSummary = {
  snapshotCount: number;
  regionsCovered: number;
  divisionsCovered: number;
  totalEntries: number;
  periodKeys: string[];
};

export type SuspiciousScore = {
  id: string;
  user: string;
  region: string;
  flaggedScore: number;
  reason: string;
  detectedAt: string;
  // Added for real anomaly detection (src/lib/admin/live-data.ts) and the
  // "Send to Exception Queue" write (src/lib/actions/admin.ts
  // flagLeaderboardScore -> src/lib/firebase/firestore.ts
  // createLeaderboardReport): the flagged owner's uid, and the id of the
  // Firestore document the evidence came from — a leaderboardContributions
  // doc for the score-based rules, or an activities doc for the
  // implausible-activity rule. Becomes reports.targetId.
  ownerUid: string;
  contributionId: string;
};

// Matches the slice() cap applied in getLiveSuspiciousScores()
// (src/lib/admin/live-data.ts). Exported as a value (not just used as a type
// file) so LeaderboardOversight.tsx — a Client Component that cannot import
// the Admin-SDK-backed live-data module — can tell the admin when the list
// was truncated without hard-coding the number a second time.
export const SUSPICIOUS_SCORE_LIST_CAP = 50;

// --- Website Content --------------------------------------------------------

export type FaqEntry = {
  id: string;
  question: string;
  answer: string;
};

export type WebsiteContent = {
  announcementText: string;
  announcementEnabled: boolean;
  heroHeadline: string;
  heroSubtext: string;
  // Structured, admin-editable "problem" section content
  // (config/siteContent.problem).
  problem: SiteProblem;
  // Structured, admin-editable "solution" section content
  // (config/siteContent.solution).
  solution: SiteSolution;
  // Structured, admin-editable "personalized plan" section content
  // (config/siteContent.personalizedPlan).
  personalizedPlan: SitePersonalizedPlan;
  // Structured, admin-editable split-highlight sections.
  journeyMap: SiteHighlight;
  xpProgression: SiteHighlight;
  territorial: SiteHighlight;
  postRunSummary: SitePostRunSummary;
  // Admin-console-only, renameable accordion section labels + drag order.
  sectionTitles: SiteSectionTitles;
  sectionOrder: SectionTitleKey[];
  // Structured, admin-editable pricing-page content (config/siteContent.pricing).
  // Mirrors the marketing render schema so the admin form and the live page
  // stay in lock-step.
  pricing: SitePricing;
  // Structured, admin-editable testimonials-section content
  // (config/siteContent.testimonials).
  testimonials: SiteTestimonials;
  // Structured, admin-editable About-page team section
  // (config/siteContent.team): heading, member cards, and supervisor.
  team: SiteTeam;
  faqs: FaqEntry[];
  // Structured, admin-editable Documents-page content
  // (config/siteContent.documents): heading, intro, and document cards.
  documents: SiteDocuments;
  // Structured, admin-editable Download-page content
  // (config/siteContent.download): Android/iOS cards, install steps, and
  // system requirements.
  download: SiteDownload;
};

// --- Feedback ---------------------------------------------------------------

export type FeedbackCategory = "bug" | "plan issue" | "billing" | "abuse" | "other";

export type FeedbackStatus =
  | "new"
  | "responded"
  | "resolved"
  | "dismissed"
  | "escalated";

export type FeedbackItem = {
  id: string;
  category: FeedbackCategory;
  summary: string;
  severity: Severity;
  duplicateCount: number;
  status: FeedbackStatus;
  receivedAt: string;
  note: string;
  closed: boolean;
};

// --- Errors -----------------------------------------------------------------

export type ErrorStatus = "new" | "investigating" | "resolved" | "ignored";

// "mobile" for Dart-level errors reported by the Flutter app via
// reportAppError; "functions" for Cloud Functions faults and non-fatal
// degraded events reported via reportBackendError. Documents written before
// this field existed have no `source` at all and are mapped to "mobile" at
// the read boundary (see src/lib/admin/live-data.ts#toErrorSource) — never
// left undefined.
export type ErrorSource = "mobile" | "functions";

export type ErrorGroup = {
  id: string;
  title: string;
  screen: string;
  appVersion: string;
  os: string;
  source: ErrorSource;
  occurrences: number;
  affectedUsers: number;
  severity: Severity;
  status: ErrorStatus;
  firstSeenAt: string;
  lastSeenAt: string;
  stackSummary: string;
  sanitized: boolean;
  note?: string;
};

// --- Audit ------------------------------------------------------------------

// Derived from an entry's action name by toAuditCategory in live-data.ts, not
// stored on the row.
export type AuditCategory =
  | "admin-action"
  | "role-change"
  | "subscription-change"
  | "rule-activation"
  | "backend-job";

export type AuditEntry = {
  id: string;
  actor: string;
  action: string;
  target: string;
  category: AuditCategory;
  timestamp: string;
};

// --- Newsletter (newsletterSubscribers, newsletterCampaigns) ----------------
//
// Read-only console over the `subscribeNewsletter` callable's Firestore
// output and the campaign send pipeline. The console can delete a subscriber
// (privacy/GDPR requests) and flip a campaign's status forward
// (draft -> testQueued / queued) — it never promotes a subscriber to
// "confirmed" (that would fabricate double-opt-in evidence) and never fans
// out mail itself; a Firestore trigger owns the actual send.

export type NewsletterSubscriberStatus =
  | "pending"
  | "confirmed"
  | "unsubscribed"
  | "bounced";

export type NewsletterSubscriber = {
  id: string;
  emailLower: string;
  status: NewsletterSubscriberStatus;
  source: string;
  consentAt: string | null;
  confirmedAt: string | null;
  unsubscribedAt: string | null;
  sendFailureCount: number;
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

export type NewsletterCampaign = {
  id: string;
  subject: string;
  bodyMarkdown: string;
  status: NewsletterCampaignStatus;
  createdBy: string;
  createdAt: string | null;
  queuedAt: string | null;
  sentAt: string | null;
  recipientCount: number;
  deliveredCount: number;
  failedCount: number;
  testRecipients: string[];
  lastTestSentAt: string | null;
  error: string | null;
};

export type NewsletterDelivery = {
  id: string;
  status: string;
  error: string | null;
};
