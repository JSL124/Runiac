import type { Firestore } from "firebase-admin/firestore";
import { loadAutomationConfig, type AutomationConfig } from "./configLoader.js";

/**
 * Gate a scheduled platform sweep (leaderboard snapshot refresh, subscription
 * expiry sweep, push notification dispatch, ...) behind config/automation.
 *
 * This is fail-open by construction. `loadAutomationConfig` already falls
 * back to `DEFAULT_AUTOMATION_CONFIG` — where every `scheduled.*` flag is
 * `true` — whenever config/automation is missing, unreadable, or invalid.
 * A corrupt or absent config document must never silently halt platform
 * sweeps; the only way to pause one is an explicit `false` written by an
 * admin.
 */
export async function scheduledAutomationEnabled(
  db: Firestore,
  key: keyof AutomationConfig["scheduled"],
  functionName: string,
): Promise<boolean> {
  const config = await loadAutomationConfig(db);
  const enabled = config.scheduled[key];

  if (!enabled) {
    console.log(`${functionName}: skipped — scheduled.${key} disabled by config/automation`);
  }

  return enabled;
}
