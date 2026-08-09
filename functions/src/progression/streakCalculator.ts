import { dailyCapDateForCompletedAt } from "./progressionCalculator.js";

export type StreakState = {
  readonly streakCount: number;
  readonly lastStreakRunDate: string | null;
};

export type StreakTransition = {
  readonly previousStreak: number;
  readonly nextStreak: number;
  readonly previousStreakRunDate: string | null;
  readonly nextStreakRunDate: string;
  readonly streakUpdatedAt: string;
  readonly shouldUpdateProfile: boolean;
};

export type StreakRun = {
  readonly completedAt: string;
};

export type StreakExpiryTransition = {
  readonly previousStreak: number;
  readonly nextStreak: number;
  readonly shouldUpdateProfile: boolean;
};

type NextStreakState = {
  readonly streakCount: number;
  readonly lastStreakRunDate: string;
  readonly shouldUpdateProfile: boolean;
};

const utcDateLength = 10;
const millisecondsPerDay = 24 * 60 * 60 * 1000;

export function calculateStreakTransition(
  input: {
    readonly currentState: StreakState;
    readonly completedAt: string;
    readonly protectedRestDates?: readonly string[];
  },
): StreakTransition {
  const runDate = dailyCapDateForCompletedAt(input.completedAt);
  const nextState = nextStreakState(
    input.currentState,
    runDate,
    new Set(input.protectedRestDates ?? []),
  );

  return {
    previousStreak: input.currentState.streakCount,
    nextStreak: nextState.streakCount,
    previousStreakRunDate: input.currentState.lastStreakRunDate,
    nextStreakRunDate: nextState.lastStreakRunDate,
    streakUpdatedAt: input.completedAt,
    shouldUpdateProfile: nextState.shouldUpdateProfile,
  };
}

export function unchangedStreakTransition(
  currentState: StreakState,
  completedAt: string,
): StreakTransition {
  return {
    previousStreak: currentState.streakCount,
    nextStreak: currentState.streakCount,
    previousStreakRunDate: currentState.lastStreakRunDate,
    nextStreakRunDate: currentState.lastStreakRunDate ?? dailyCapDateForCompletedAt(completedAt),
    streakUpdatedAt: completedAt,
    shouldUpdateProfile: false,
  };
}

export function calculateStreakStateFromRuns(
  runs: readonly StreakRun[],
  protectedRestDates: readonly string[] = [],
): StreakState {
  const runDates = [...new Set(runs.map((run) => dailyCapDateForCompletedAt(run.completedAt)))]
    .sort((left, right) => left.localeCompare(right));
  const protectedRestDateSet = new Set(protectedRestDates);
  return runDates.reduce<StreakState>(
    (state, runDate) => {
      const nextState = nextStreakState(state, runDate, protectedRestDateSet);
      return {
        streakCount: nextState.streakCount,
        lastStreakRunDate: nextState.lastStreakRunDate,
      };
    },
    { streakCount: 0, lastStreakRunDate: null },
  );
}

export function calculateStreakExpiryTransition(input: {
  readonly currentState: StreakState;
  readonly asOfDate: string;
  readonly protectedRestDates?: readonly string[];
}): StreakExpiryTransition {
  const previousDate = input.currentState.lastStreakRunDate;
  if (
    input.currentState.streakCount <= 0 ||
    previousDate === null ||
    daysBetween(previousDate, input.asOfDate) <= 1 ||
    isProtectedRestGap(
      previousDate,
      input.asOfDate,
      new Set(input.protectedRestDates ?? []),
    )
  ) {
    return {
      previousStreak: input.currentState.streakCount,
      nextStreak: input.currentState.streakCount,
      shouldUpdateProfile: false,
    };
  }

  return {
    previousStreak: input.currentState.streakCount,
    nextStreak: 0,
    shouldUpdateProfile: true,
  };
}

function nextStreakState(
  currentState: StreakState,
  runDate: string,
  protectedRestDates: ReadonlySet<string>,
): NextStreakState {
  const previousDate = currentState.lastStreakRunDate;
  if (previousDate === null) {
    return { streakCount: 1, lastStreakRunDate: runDate, shouldUpdateProfile: true };
  }

  const dayDelta = daysBetween(previousDate, runDate);
  if (dayDelta === 0) {
    return {
      streakCount: currentState.streakCount,
      lastStreakRunDate: previousDate,
      shouldUpdateProfile: true,
    };
  }

  if (dayDelta === 1) {
    return {
      streakCount: currentState.streakCount + 1,
      lastStreakRunDate: runDate,
      shouldUpdateProfile: true,
    };
  }

  if (dayDelta > 1 && isProtectedRestGap(previousDate, runDate, protectedRestDates)) {
    return {
      streakCount: currentState.streakCount + 1,
      lastStreakRunDate: runDate,
      shouldUpdateProfile: true,
    };
  }

  if (dayDelta > 1) {
    return { streakCount: 1, lastStreakRunDate: runDate, shouldUpdateProfile: true };
  }

  return {
    streakCount: currentState.streakCount,
    lastStreakRunDate: previousDate,
    shouldUpdateProfile: false,
  };
}

function daysBetween(previousDate: string, nextDate: string): number {
  return (Date.parse(`${nextDate}T00:00:00.000Z`) - Date.parse(`${previousDate}T00:00:00.000Z`)) /
    millisecondsPerDay;
}

function isProtectedRestGap(
  previousDate: string,
  nextDate: string,
  protectedRestDates: ReadonlySet<string>,
): boolean {
  for (
    let time = Date.parse(`${previousDate}T00:00:00.000Z`) + millisecondsPerDay;
    time < Date.parse(`${nextDate}T00:00:00.000Z`);
    time += millisecondsPerDay
  ) {
    if (!protectedRestDates.has(new Date(time).toISOString().slice(0, utcDateLength))) {
      return false;
    }
  }

  return true;
}
