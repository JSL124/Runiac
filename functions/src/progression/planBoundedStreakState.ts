import { dailyCapDateForCompletedAt } from "./progressionCalculator.js";
import { calculateStreakStateFromRuns, type StreakRun, type StreakState } from "./streakCalculator.js";
import {
  isRecord,
  isRestWorkout,
  readOptionalInteger,
  readOptionalString,
  scheduledDateFor,
  weekdayLabels,
} from "../plan/planProgressParsing.js";

export type TrustedStreakStateInput = {
  readonly profileState: StreakState;
  readonly generatedPlanData: FirebaseFirestore.DocumentData | undefined;
  readonly activityDocuments: readonly FirebaseFirestore.DocumentData[];
};

export function readTrustedStreakState(input: TrustedStreakStateInput): StreakState {
  const planStartDate = readGeneratedPlanStartDate(input.generatedPlanData);
  if (planStartDate === null) {
    return input.profileState;
  }

  return calculateStreakStateFromRuns(
    readPlanBoundedValidatedRuns(input.activityDocuments, planStartDate),
    readPlanBoundedRestDates(input.generatedPlanData, planStartDate),
  );
}

export function readTrustedProtectedRestDates(
  generatedPlanData: FirebaseFirestore.DocumentData | undefined,
): readonly string[] {
  const planStartDate = readGeneratedPlanStartDate(generatedPlanData);
  if (planStartDate === null) {
    return [];
  }

  return readPlanBoundedRestDates(generatedPlanData, planStartDate);
}

function readPlanBoundedValidatedRuns(
  activityDocuments: readonly FirebaseFirestore.DocumentData[],
  planStartDate: string,
): readonly StreakRun[] {
  return activityDocuments.flatMap((activityData) => {
    if (
      activityData["activityType"] !== "run" ||
      activityData["validationStatus"] !== "validated" ||
      activityData["countsTowardStreak"] === false
    ) {
      return [];
    }

    const completedAt = readActivityCompletedAt(activityData);
    // Compare Singapore calendar days, not raw instants: a run just after
    // Singapore midnight on the plan's first day is 16:00Z the day before, and
    // an instant comparison would drop it as pre-start.
    if (completedAt === null || dailyCapDateForCompletedAt(completedAt) < planStartDate) {
      return [];
    }

    return [{ completedAt }];
  });
}

function readActivityCompletedAt(activityData: FirebaseFirestore.DocumentData): string | null {
  const endedAt = activityData["endedAt"];
  if (typeof endedAt === "string") {
    return endedAt;
  }

  const completedAt = activityData["completedAt"];
  return typeof completedAt === "string" ? completedAt : null;
}

// A generated plan expresses rest by OMITTING a day from `weeks[].workouts`,
// not by writing a `kind: "rest"` workout — no plan writer in the codebase ever
// emits one. So a protected rest date is any in-plan calendar day that carries
// no scheduled training workout. Weeks we cannot parse contribute neither
// scheduled nor rest dates, so a malformed week never widens protection.
function readPlanBoundedRestDates(
  generatedPlanData: FirebaseFirestore.DocumentData | undefined,
  planStartDate: string,
): readonly string[] {
  if (generatedPlanData === undefined) {
    return [];
  }

  const startsOnDate = readOptionalString(generatedPlanData["startsOnDate"]);
  const weeks = generatedPlanData["weeks"];
  if (startsOnDate === undefined || !Array.isArray(weeks)) {
    return [];
  }

  const parsedWeeks = weeks.flatMap((week) => {
    if (!isRecord(week)) {
      return [];
    }

    const weekNumber = readOptionalInteger(week["weekNumber"]);
    const workouts = week["workouts"];
    if (weekNumber === undefined || !Array.isArray(workouts)) {
      return [];
    }

    return [{ weekNumber, workouts }];
  });

  // Collect every scheduled date across the whole plan before deciding what
  // rests. Scoping this per week entry would let duplicate `weekNumber` entries
  // protect a day that a sibling entry actually schedules.
  const scheduledDates = new Set(
    parsedWeeks.flatMap(({ weekNumber, workouts }) =>
      workouts.flatMap((workout) => {
        if (!isRecord(workout) || isRestWorkout(workout)) {
          return [];
        }

        const dayLabel = readOptionalString(workout["dayLabel"]);
        const scheduledDate = dayLabel === undefined
          ? null
          : scheduledDateFor(startsOnDate, weekNumber, dayLabel);
        return scheduledDate === null ? [] : [scheduledDate];
      })
    ),
  );

  return [
    ...new Set(parsedWeeks.flatMap(({ weekNumber }) => weekDates(startsOnDate, weekNumber))),
  ].filter((date) =>
    !scheduledDates.has(date) && date >= planStartDate
  );
}

function weekDates(startsOnDate: string, weekNumber: number): readonly string[] {
  return weekdayLabels.flatMap((dayLabel) => {
    const date = scheduledDateFor(startsOnDate, weekNumber, dayLabel);
    return date === null ? [] : [date];
  });
}

// Returns the plan's first day as a Singapore calendar date (YYYY-MM-DD) so
// every plan bound is compared day-to-day. Timestamp sources are converted
// through the same Singapore mapping runs use; `startsOnDate` is already one.
function readGeneratedPlanStartDate(
  generatedPlanData: FirebaseFirestore.DocumentData | undefined,
): string | null {
  if (generatedPlanData === undefined) {
    return null;
  }

  const startedAt = readTimestampLikeString(generatedPlanData["createdAt"]) ??
    readTimestampLikeString(generatedPlanData["updatedAt"]);
  if (startedAt !== null) {
    return dailyCapDateForCompletedAt(startedAt);
  }

  return readDateString(generatedPlanData["startsOnDate"]);
}

function readTimestampLikeString(value: unknown): string | null {
  if (typeof value === "string" && Number.isFinite(Date.parse(value))) {
    return value;
  }

  if (isFirestoreTimestamp(value)) {
    return value.toDate().toISOString();
  }

  return null;
}

function readDateString(value: unknown): string | null {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return null;
  }

  return value;
}

function isFirestoreTimestamp(value: unknown): value is { readonly toDate: () => Date } {
  return typeof value === "object" && value !== null && "toDate" in value && typeof value.toDate === "function";
}
