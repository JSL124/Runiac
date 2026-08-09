import type { ProgressionDisplay } from "../run/runCompletionTypes.js";

export function progressionReason(input: {
  // Being premium is NOT by itself a reason to withhold XP — only an active
  // `config/progression.premiumEarnsXp: false` is. Callers must pass that
  // resolved decision, not the raw subscription tier, or a premium runner
  // earning XP normally would be reported as "premium_no_progression".
  readonly premiumXpSuppressed: boolean;
  readonly activityReason: "run_completion_xp_awarded" | "low_data_no_xp";
  readonly xpDeltaBeforeDailyCap: number;
  readonly xpDelta: number;
}): ProgressionDisplay["reason"] {
  if (input.premiumXpSuppressed) {
    return "premium_no_progression";
  }
  if (input.activityReason === "low_data_no_xp") {
    return "low_data_no_xp";
  }
  if (input.xpDeltaBeforeDailyCap > 0 && input.xpDelta === 0) {
    return "daily_cap_reached";
  }
  return "run_completion_xp_awarded";
}

export function readTotalXp(profileData: FirebaseFirestore.DocumentData | undefined): number {
  const totalXp = profileData?.["totalXp"];
  return typeof totalXp === "number" && Number.isInteger(totalXp) && totalXp > 0 ? totalXp : 0;
}

export function sumDailyXp(
  progressionEventDocuments: readonly FirebaseFirestore.DocumentData[],
  dailyCapDate: string,
): number {
  return progressionEventDocuments.reduce((total, eventData) => {
    const eventDailyCapDate = eventData["dailyCapDate"];
    const xpDelta = eventData["xpDelta"];
    if (eventDailyCapDate !== dailyCapDate || typeof xpDelta !== "number" || xpDelta <= 0) {
      return total;
    }
    // Streak milestone bonuses are exempt from the daily cap, so they must not
    // consume the day's budget either — otherwise a 600 XP milestone would
    // block every later run that day from earning anything, which is the same
    // conflation the exemption exists to remove. Net it out of the stored
    // xpDelta (absent on events written before the field existed, and on
    // cool-down events, which never carry one).
    const streakBonusXp = eventData["streakBonusXp"];
    const countedXp =
      typeof streakBonusXp === "number" && streakBonusXp > 0
        ? Math.max(0, xpDelta - streakBonusXp)
        : xpDelta;
    return total + countedXp;
  }, 0);
}

export function sumMonthlyXp(
  progressionEventDocuments: readonly FirebaseFirestore.DocumentData[],
  monthlyPeriod: string,
): number {
  return progressionEventDocuments.reduce((total, eventData) => {
    const eventMonthlyPeriod = eventData["monthlyPeriod"];
    const xpDelta = eventData["xpDelta"];
    if (eventMonthlyPeriod === monthlyPeriod && typeof xpDelta === "number" && xpDelta > 0) {
      return total + xpDelta;
    }
    return total;
  }, 0);
}

export function formatXpLabel(xp: number): string {
  return `${xp.toLocaleString("en-US")} XP`;
}

export function isPremiumSubscription(
  data: FirebaseFirestore.DocumentData | undefined,
  nowMs: number,
): boolean {
  const subscriptionStatus = data?.["subscriptionStatus"];
  if (subscriptionStatus !== "premium" && subscriptionStatus !== "Premium") {
    return false;
  }
  const expiresAtMs = readSubscriptionExpiresAtMs(data?.["subscriptionExpiresAt"]);
  // Absent/unreadable expiry means "no expiry" so existing docs keep their
  // current always-premium behaviour; only a resolvable, past expiry lapses.
  return expiresAtMs === null || expiresAtMs > nowMs;
}

// `subscriptionExpiresAt` is contractually a Firestore Timestamp: the only
// writer is the admin console's setUserSubscription(), which stores
// Timestamp.fromDate().
//
// Reading other shapes here would create a divergence the expiry sweep cannot
// resolve. The sweep selects lapsed documents with a `<= Timestamp` range
// query, and Firestore inequality filters are type-scoped, so a value stored
// as an ISO string is never selected no matter how long ago it lapsed. If this
// reader honoured that string, the in-request check would deny premium while
// the sweep left `subscriptionStatus: "premium"` in place forever — and
// firestore.rules, which can only read the materialised status, would keep
// granting access indefinitely.
//
// Restricting this reader to Timestamp keeps the three consistent by
// construction: a non-Timestamp value is "no expiry" to the helper, is not
// selected by the sweep, and reads as premium in rules. Wrong data is then
// uniformly visible rather than half-enforced.
function readSubscriptionExpiresAtMs(value: unknown): number | null {
  if (
    value !== null &&
    typeof value === "object" &&
    typeof (value as { toMillis?: unknown }).toMillis === "function"
  ) {
    const millis = (value as { toMillis: () => number }).toMillis();
    return typeof millis === "number" && Number.isFinite(millis) ? millis : null;
  }
  return null;
}
