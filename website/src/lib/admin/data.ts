// Data-access layer for the Platform Administrator console.
//
// Every page and component reads admin data through the async functions below —
// never by importing ./mock-data.ts or the Firebase layer directly. When
// Firebase is configured (hasFirebaseEnv(): emulator or live service account),
// functions with a backend source read live Firestore data via ./live-data.ts;
// everything else — and every live read that fails (e.g. the emulator is
// down) — falls back to the placeholder data in ./mock-data.ts so a page never
// crashes. Firestore collections per area:
//   users, userProfiles, reports, activities, leaderboardSnapshots,
//   adminAuditLogs.

import { hasFirebaseEnv } from "@/lib/firebase/config";
import {
  ACTIVE_USERS_TREND,
  ADMIN_USERS,
  AGGREGATION_JOB,
  ATTENTION_ITEMS,
  AUDIT_ENTRIES,
  ERROR_GROUPS,
  EXCEPTION_CASES,
  FEEDBACK_ITEMS,
  LEADERBOARD_COVERAGE,
  LEADERBOARD_CURRENT_PERIOD,
  LEADERBOARD_PARTICIPATION,
  LEADERBOARD_SETTINGS,
  LEVEL_THRESHOLDS,
  NEWSLETTER_CAMPAIGNS,
  NEWSLETTER_SUBSCRIBERS,
  OVERVIEW_STATS,
  SUSPICIOUS_SCORES,
  SYSTEM_HEALTH,
  USER_ACTION_HISTORY,
  WEBSITE_CONTENT,
  XP_RULES,
} from "./mock-data";
import {
  getLiveAggregationJob,
  getLiveAttentionItems,
  getLiveAuditLog,
  getLiveAutomationConfig,
  getLiveChallengeAccessConfig,
  getLiveCharacterAccessConfig,
  getLiveConfigSummaries,
  getLiveErrorGroups,
  getLiveExceptionCases,
  getLiveFeatureAccessConfig,
  getLiveFeedbackItems,
  getLiveLeaderboardConfig,
  getLiveLeaderboardCoverage,
  getLiveLeaderboardCurrentPeriod,
  getLiveLeaderboardParticipation,
  getLiveActiveUsersTrend,
  getLiveLeaderboardSettings,
  getLiveLevelThresholds,
  getLiveNewsletterCampaigns,
  getLiveNewsletterSubscribers,
  getLiveOverviewStats,
  getLivePaywallConfig,
  getLivePaywallHistory,
  getLiveProgressionConfig,
  getLiveProgressionHistory,
  getLiveSuspiciousScores,
  getLiveSystemHealth,
  getLiveUserActionHistory,
  getLiveUsers,
  getLiveWebsiteContent,
  getLiveXpRules,
} from "./live-data";
import type { ConfigSummary } from "./live-data";
import {
  DEFAULT_AUTOMATION_CONFIG,
  DEFAULT_CHALLENGE_ACCESS_CONFIG,
  DEFAULT_CHARACTER_ACCESS_CONFIG,
  DEFAULT_FEATURE_ACCESS_CONFIG,
  DEFAULT_LEADERBOARD_CONFIG,
  DEFAULT_PROGRESSION_CONFIG,
} from "./config-validation";
import { DEFAULT_PAYWALL_CONFIG, type PaywallConfig } from "./paywall-config";
import type {
  AutomationConfig,
  ChallengeAccessConfig,
  CharacterAccessConfig,
  FeatureAccessConfig,
  LeaderboardConfig,
  ProgressionConfig,
} from "./config-validation";
import type {
  ActiveUsersPoint,
  AdminActionLogEntry,
  AdminUser,
  AggregationJob,
  AttentionItem,
  AuditEntry,
  ConfigVersionEntry,
  ErrorGroup,
  ExceptionCase,
  FeedbackItem,
  LeaderboardCoverageSummary,
  LeaderboardCurrentPeriod,
  LeaderboardParticipationBreakdown,
  LeaderboardSettings,
  LevelThreshold,
  NewsletterCampaign,
  NewsletterSubscriber,
  OverviewStat,
  SuspiciousScore,
  SystemHealthComponent,
  WebsiteContent,
  XpRule,
} from "./types";

// Runs the live read when Firebase is configured; any thrown Firestore/Auth
// error degrades to the mock value with a warning instead of crashing a page.
async function liveOrMock<T>(
  label: string,
  live: () => Promise<T>,
  mock: T,
): Promise<T> {
  if (!hasFirebaseEnv()) {
    return mock;
  }

  try {
    return await live();
  } catch (error) {
    console.warn(
      `[admin-data] Live read failed for ${label}; serving mock data.`,
      error,
    );
    return mock;
  }
}

// --- Overview ----------------------------------------------------------------

export async function getOverviewStats(): Promise<OverviewStat[]> {
  return liveOrMock("overview stats", getLiveOverviewStats, OVERVIEW_STATS);
}

// Four real backend probes (Firestore reachability, the leaderboard
// aggregation job, recent Cloud Functions error groups, recent critical app
// error groups) via getLiveSystemHealth() in ./live-data.ts. Falls back to
// the mock component list when Firebase is not configured or the live read
// throws.
export async function getSystemHealth(): Promise<SystemHealthComponent[]> {
  return liveOrMock("system health", getLiveSystemHealth, SYSTEM_HEALTH);
}

// Version/last-updated metadata for each backend config document, for the
// overview's System Configuration panel. Mock fallback reports the shipped
// defaults as "not yet configured" rather than inventing fake history.
export async function getConfigSummaries(): Promise<ConfigSummary[]> {
  const mock: ConfigSummary[] = [
    {
      id: "progression",
      label: "Progression (XP & levels)",
      href: "/admin/gamification",
      version: DEFAULT_PROGRESSION_CONFIG.version,
      updatedAt: null,
      updatedBy: null,
      configured: false,
    },
    {
      id: "leaderboard",
      label: "Leaderboard",
      href: "/admin/leaderboard",
      version: DEFAULT_LEADERBOARD_CONFIG.version,
      updatedAt: null,
      updatedBy: null,
      configured: false,
    },
    {
      id: "featureAccess",
      label: "Feature access",
      href: "/admin/policies",
      version: DEFAULT_FEATURE_ACCESS_CONFIG.version,
      updatedAt: null,
      updatedBy: null,
      configured: false,
    },
    {
      id: "automation",
      label: "Automation & policies",
      href: "/admin/policies",
      version: DEFAULT_AUTOMATION_CONFIG.version,
      updatedAt: null,
      updatedBy: null,
      configured: false,
    },
    {
      id: "challengeAccess",
      label: "Challenge tier access",
      href: "/admin/policies",
      version: DEFAULT_CHALLENGE_ACCESS_CONFIG.version,
      updatedAt: null,
      updatedBy: null,
      configured: false,
    },
    {
      id: "characterAccess",
      label: "Character access",
      href: "/admin/policies",
      version: DEFAULT_CHARACTER_ACCESS_CONFIG.version,
      updatedAt: null,
      updatedBy: null,
      configured: false,
    },
    {
      id: "siteContent",
      label: "Website content",
      href: "/admin/content",
      version: null,
      updatedAt: null,
      updatedBy: null,
      configured: false,
    },
  ];

  return liveOrMock("config summaries", getLiveConfigSummaries, mock);
}

export async function getAttentionItems(): Promise<AttentionItem[]> {
  return liveOrMock("attention items", getLiveAttentionItems, ATTENTION_ITEMS);
}

// Monthly active-user counts (distinct activity owners per Singapore-month
// window) for the trailing MAU_TREND_MONTHS months, via
// getLiveActiveUsersTrend() in ./live-data.ts. Falls back to the mock trend
// when Firebase is not configured or the live read throws.
export async function getActiveUsersTrend(): Promise<ActiveUsersPoint[]> {
  return liveOrMock(
    "active users trend",
    getLiveActiveUsersTrend,
    ACTIVE_USERS_TREND,
  );
}

// --- Exception Queue (reports) ------------------------------------------------

export async function getExceptionCases(): Promise<ExceptionCase[]> {
  return liveOrMock("exception cases", getLiveExceptionCases, EXCEPTION_CASES);
}

// --- Users & roles (users, userProfiles) ---------------------------------------

export const DEFAULT_USER_PAGE_SIZE = 50;
export const MAX_USER_PAGE_SIZE = 500;

// `limit` bounds the scan read from Firestore, and the returned flags describe
// that scan rather than the filtered result.
//
// An email or uid query is resolved directly and is never limited by `limit`.
// A partial-name query is a substring filter over the scanned window only, so
// when `windowFull` is true the result is explicitly incomplete and the UI must
// say so instead of implying the directory ended there.
export type UsersPage = {
  users: AdminUser[];
  windowFull: boolean;
  resolvedExactly: boolean;
};

export async function getUsers(
  query = "",
  limit = DEFAULT_USER_PAGE_SIZE,
): Promise<UsersPage> {
  const trimmed = query.trim().toLowerCase();
  const scanned = ADMIN_USERS.slice(0, limit);
  const mock: UsersPage = {
    users: !trimmed
      ? scanned
      : scanned.filter((user) =>
          [user.displayName, user.nickname, user.email, user.region]
            .join(" ")
            .toLowerCase()
            .includes(trimmed),
        ),
    // `>=`, matching the live path: a scan that exactly fills its limit cannot
    // tell "that was everything" from "there is more", and both modes must be
    // conservative in the same direction.
    windowFull: ADMIN_USERS.length >= limit,
    resolvedExactly: false,
  };

  return liveOrMock("users", () => getLiveUsers(query, limit), mock);
}

export async function getUserActionHistory(): Promise<AdminActionLogEntry[]> {
  return liveOrMock(
    "user action history",
    getLiveUserActionHistory,
    USER_ACTION_HISTORY,
  );
}

// --- Gamification (config/progression) ---------------------------------------

export async function getXpRules(): Promise<XpRule[]> {
  return liveOrMock("xp rules", getLiveXpRules, XP_RULES);
}

export async function getLevelThresholds(): Promise<LevelThreshold[]> {
  return liveOrMock("level thresholds", getLiveLevelThresholds, LEVEL_THRESHOLDS);
}

// Full config/progression document (base/per-km/per-min/plan-bonus XP, caps,
// max level, cool-down, level increments) for the admin console's editable
// progression form. getXpRules()/getLevelThresholds() above stay in place for
// any other read-only consumers of the derived view shapes.
export async function getProgressionConfig(): Promise<ProgressionConfig> {
  return liveOrMock(
    "progression config",
    getLiveProgressionConfig,
    DEFAULT_PROGRESSION_CONFIG,
  );
}

// Real config/progression change history from the admin audit log. The mock
// fallback is deliberately EMPTY: fabricated version history would misrepresent
// what was actually saved, which is exactly what this feature replaces.
export async function getProgressionHistory(): Promise<ConfigVersionEntry[]> {
  return liveOrMock("progression history", getLiveProgressionHistory, []);
}

// --- App paywall (config/paywall) -------------------------------------------

// Full config/paywall document (title, badge, feature rows, prices, CTA,
// footer links, highlight interval) for the admin console's paywall editor.
// Signed-in mobile clients read this document directly.
export async function getPaywallConfig(): Promise<PaywallConfig> {
  return liveOrMock("paywall config", getLivePaywallConfig, DEFAULT_PAYWALL_CONFIG);
}

// Real config/paywall change history from the admin audit log; empty mock
// fallback for the same reason as the progression history above.
export async function getPaywallHistory(): Promise<ConfigVersionEntry[]> {
  return liveOrMock("paywall history", getLivePaywallHistory, []);
}

// --- Leaderboard (leaderboardSnapshots) ------------------------------------------

export async function getAggregationJob(): Promise<AggregationJob> {
  return liveOrMock(
    "aggregation job",
    async () => {
      // An unseeded database has no snapshot yet — degrade to the mock card.
      const job = await getLiveAggregationJob();
      return job ?? AGGREGATION_JOB;
    },
    AGGREGATION_JOB,
  );
}

// leaderboardPeriods/monthly_current — what the mobile app is actually
// reading right now. Null (both live and mock-degraded) means no aggregation
// run has ever completed.
export async function getLeaderboardCurrentPeriod(): Promise<LeaderboardCurrentPeriod | null> {
  return liveOrMock(
    "leaderboard current period",
    getLiveLeaderboardCurrentPeriod,
    LEADERBOARD_CURRENT_PERIOD,
  );
}

// Per-status counts over leaderboardCurrentViews (one document per user):
// ranked / unranked / region-required / ineligible-premium /
// ineligible-min-runs.
export async function getLeaderboardParticipation(): Promise<LeaderboardParticipationBreakdown> {
  return liveOrMock(
    "leaderboard participation",
    getLiveLeaderboardParticipation,
    LEADERBOARD_PARTICIPATION,
  );
}

// Aggregate coverage over leaderboardSnapshots: how many exist, how much of
// the region x division grid they cover, and which period keys still have
// data.
export async function getLeaderboardCoverage(): Promise<LeaderboardCoverageSummary> {
  return liveOrMock(
    "leaderboard coverage",
    getLiveLeaderboardCoverage,
    LEADERBOARD_COVERAGE,
  );
}

export async function getLeaderboardSettings(): Promise<LeaderboardSettings> {
  return liveOrMock(
    "leaderboard settings",
    getLiveLeaderboardSettings,
    LEADERBOARD_SETTINGS,
  );
}

// Full config/leaderboard document for the admin console's editable form.
// getLeaderboardSettings() above keeps serving the read-only view shape
// (including the not-yet-backend regionalGrouping flag) for other consumers.
export async function getLeaderboardConfig(): Promise<LeaderboardConfig> {
  return liveOrMock(
    "leaderboard config",
    getLiveLeaderboardConfig,
    DEFAULT_LEADERBOARD_CONFIG,
  );
}

// Computed from real leaderboardContributions/activities documents by
// getLiveSuspiciousScores() — see src/lib/admin/live-data.ts for the
// detection rules. Falls back to the mock list when Firebase is not
// configured, or when the live read throws (e.g. an unseeded database).
export async function getSuspiciousScores(): Promise<SuspiciousScore[]> {
  return liveOrMock("suspicious scores", getLiveSuspiciousScores, SUSPICIOUS_SCORES);
}

// --- Website content (config/siteContent) --------------------------------------

export async function getWebsiteContent(): Promise<WebsiteContent> {
  return liveOrMock("website content", getLiveWebsiteContent, WEBSITE_CONTENT);
}

// --- Feedback (feedback collection, written by the submitFeedback Cloud Function) --

export async function getFeedbackItems(): Promise<FeedbackItem[]> {
  return liveOrMock("feedback items", getLiveFeedbackItems, FEEDBACK_ITEMS);
}

// --- App errors ---------------------------------------------------------------

export async function getErrorGroups(): Promise<ErrorGroup[]> {
  return liveOrMock("error groups", getLiveErrorGroups, ERROR_GROUPS);
}

// --- Policies (config/featureAccess, config/automation) ----------------------

// Full config/featureAccess document for the admin console's editable
// per-feature tier/enabled editor.
export async function getFeatureAccessConfig(): Promise<FeatureAccessConfig> {
  return liveOrMock(
    "feature access config",
    getLiveFeatureAccessConfig,
    DEFAULT_FEATURE_ACCESS_CONFIG,
  );
}

// Full config/automation document for the admin console's editable
// automation & notification-policy editor.
export async function getAutomationConfig(): Promise<AutomationConfig> {
  return liveOrMock(
    "automation config",
    getLiveAutomationConfig,
    DEFAULT_AUTOMATION_CONFIG,
  );
}

// Full config/challengeAccess document for the admin console's premium
// challenge-tier gating editor.
export async function getChallengeAccessConfig(): Promise<ChallengeAccessConfig> {
  return liveOrMock(
    "challenge access config",
    getLiveChallengeAccessConfig,
    DEFAULT_CHALLENGE_ACCESS_CONFIG,
  );
}

// Full config/characterAccess document for the admin console's premium
// guide-character gating editor.
export async function getCharacterAccessConfig(): Promise<CharacterAccessConfig> {
  return liveOrMock(
    "character access config",
    getLiveCharacterAccessConfig,
    DEFAULT_CHARACTER_ACCESS_CONFIG,
  );
}

// --- Audit log (adminAuditLogs) -----------------------------------------------------

export async function getAuditLog(): Promise<AuditEntry[]> {
  return liveOrMock("audit log", getLiveAuditLog, AUDIT_ENTRIES);
}

// --- Newsletter (newsletterSubscribers, newsletterCampaigns) ----------------

export async function getNewsletterSubscribers(): Promise<
  NewsletterSubscriber[]
> {
  return liveOrMock(
    "newsletter subscribers",
    getLiveNewsletterSubscribers,
    NEWSLETTER_SUBSCRIBERS,
  );
}

export async function getNewsletterCampaigns(): Promise<NewsletterCampaign[]> {
  return liveOrMock(
    "newsletter campaigns",
    getLiveNewsletterCampaigns,
    NEWSLETTER_CAMPAIGNS,
  );
}
