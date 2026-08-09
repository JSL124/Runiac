import type { HomeGuideActivityQuery, TrustedHomeGuideActivity } from "../src/agent/homeGuideContracts.js";
import type { RawRunCompletionPayload } from "../src/run/runCompletionTypes.js";

export function validRunPayload(): RawRunCompletionPayload {
  return {
    clientRunSessionId: "baseline-run",
    startedAt: "2026-07-06T00:00:00.000Z",
    completedAt: "2026-07-06T00:30:00.000Z",
    durationSeconds: 1_800,
    activeDurationSeconds: 1_800,
    elapsedWallSeconds: 1_800,
    pausedDurationSeconds: 0,
    distanceMeters: 3_000,
    avgPaceSecondsPerKm: 600,
    source: "mobile",
    routePrivacy: "private",
    userConfirmedLowDataSave: false,
  };
}

export function activityRecord(endedAt: string): Readonly<Record<string, unknown>> {
  return {
    ownerUid: "runner-1",
    status: "validated",
    validationStatus: "validated",
    activityType: "run",
    endedAt,
    activeDurationSeconds: 1_800,
    distanceMeters: 3_000,
    averagePaceSecondsPerKm: 600,
  };
}

export function planContext(): Readonly<Record<string, unknown>> {
  return {
    planTitle: "Beginner plan",
    weekNumber: 2,
    weekFocus: "Build endurance",
    dayLabel: "Wednesday",
    workoutTitle: "Easy run",
    durationMinutes: 25,
    intensity: "easy",
    description: "Steady and comfortable.",
    steps: ["Warm up", "Run easily"],
    supportiveNote: "Keep it comfortable.",
  };
}

export function trustedActivity(
  endedAt: string,
  activeDurationSeconds: number,
  distanceMeters: number,
): TrustedHomeGuideActivity {
  return { endedAt, activeDurationSeconds, distanceMeters, averagePaceSecondsPerKm: 600 };
}

export function activityQueryFixture(calls: string[]): HomeGuideActivityQuery {
  const query: HomeGuideActivityQuery = {
    where(fieldPath, operator, value) {
      calls.push(`where:${fieldPath}:${operator}:${value}`);
      return query;
    },
    select(...fieldPaths) {
      calls.push(`select:${fieldPaths.join(",")}`);
      return {
        async get() {
          return { docs: [{ data: () => activityRecord("2026-06-20T00:00:00.000Z") }] };
        },
      };
    },
  };
  return query;
}
