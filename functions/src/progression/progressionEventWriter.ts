import type { ProgressionDisplay } from "../run/runCompletionTypes.js";

export function deferredProgressionDisplay(): ProgressionDisplay {
  return {
    xpDelta: 0,
    countsTowardLeaderboard: false,
    status: "deferred",
    reason: "progression_formula_deferred",
  };
}
