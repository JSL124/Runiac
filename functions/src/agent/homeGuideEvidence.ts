import type {
  HomeGuideEvidence,
  HomeGuideEvidenceFact,
  TrustedHomeGuideActivity,
} from "./homeGuideContracts.js";

export type HomeGuideEvidenceInput = {
  readonly now: Date;
  readonly activities: readonly TrustedHomeGuideActivity[];
};

type WindowName = "week_to_date" | "rolling_28_days";
type MetricName = "run_count" | "distance" | "active_duration" | "weighted_pace";
type TimeWindow = {
  readonly currentStartsAt: number;
  readonly currentEndsBefore: number;
  readonly priorStartsAt: number;
  readonly priorEndsBefore: number;
};
type Aggregate = {
  readonly runCount: number;
  readonly distanceMeters: number;
  readonly activeDurationSeconds: number;
  readonly paceEligibleRunCount: number;
  readonly paceDistanceMeters: number;
  readonly paceActiveDurationSeconds: number;
};

const singaporeOffsetMillis = 8 * 60 * 60 * 1_000;
const dayMillis = 24 * 60 * 60 * 1_000;

export function buildHomeGuideEvidence(input: HomeGuideEvidenceInput): HomeGuideEvidence {
  const nowMillis = input.now.getTime();
  if (!Number.isFinite(nowMillis)) {
    return { facts: [] };
  }
  const weekFacts = factsForWindow("week_to_date", weekToDateWindow(nowMillis), input.activities, 1);
  const rollingFacts = factsForWindow("rolling_28_days", rollingWindow(nowMillis), input.activities, 3);
  return { facts: [...weekFacts, ...rollingFacts] };
}

function weekToDateWindow(nowMillis: number): TimeWindow {
  const singaporeNow = new Date(nowMillis + singaporeOffsetMillis);
  const weekdayOffset = (singaporeNow.getUTCDay() + 6) % 7;
  const mondayStart = Date.UTC(
    singaporeNow.getUTCFullYear(),
    singaporeNow.getUTCMonth(),
    singaporeNow.getUTCDate() - weekdayOffset,
  ) - singaporeOffsetMillis;
  const elapsed = nowMillis - mondayStart;
  const priorStart = mondayStart - 7 * dayMillis;
  return {
    currentStartsAt: mondayStart,
    currentEndsBefore: nowMillis,
    priorStartsAt: priorStart,
    priorEndsBefore: priorStart + elapsed,
  };
}

function rollingWindow(nowMillis: number): TimeWindow {
  const currentStartsAt = nowMillis - 28 * dayMillis;
  return {
    currentStartsAt,
    currentEndsBefore: nowMillis,
    priorStartsAt: nowMillis - 56 * dayMillis,
    priorEndsBefore: currentStartsAt,
  };
}

function factsForWindow(
  window: WindowName,
  timeWindow: TimeWindow,
  activities: readonly TrustedHomeGuideActivity[],
  minimumRuns: number,
): readonly HomeGuideEvidenceFact[] {
  const current = aggregate(activities, timeWindow.currentStartsAt, timeWindow.currentEndsBefore);
  const prior = aggregate(activities, timeWindow.priorStartsAt, timeWindow.priorEndsBefore);
  if (current.runCount < minimumRuns || prior.runCount < minimumRuns) {
    return [];
  }
  const facts = [
    scalarFact(window, "run_count", current.runCount, prior.runCount),
    scalarFact(window, "distance", current.distanceMeters, prior.distanceMeters),
    scalarFact(window, "active_duration", current.activeDurationSeconds, prior.activeDurationSeconds),
  ];
  const paceFact = weightedPaceFact(window, current, prior);
  return paceFact === null ? facts : [...facts, paceFact];
}

function aggregate(activities: readonly TrustedHomeGuideActivity[], startsAt: number, endsBefore: number): Aggregate {
  let runCount = 0;
  let distanceMeters = 0;
  let activeDurationSeconds = 0;
  let paceEligibleRunCount = 0;
  let paceDistanceMeters = 0;
  let paceActiveDurationSeconds = 0;
  for (const activity of activities) {
    const endedAtMillis = Date.parse(activity.endedAt);
    if (!(endedAtMillis >= startsAt && endedAtMillis < endsBefore)) {
      continue;
    }
    runCount += 1;
    distanceMeters += activity.distanceMeters;
    activeDurationSeconds += activity.activeDurationSeconds;
    if (activity.distanceMeters > 0 && activity.activeDurationSeconds > 0) {
      paceEligibleRunCount += 1;
      paceDistanceMeters += activity.distanceMeters;
      paceActiveDurationSeconds += activity.activeDurationSeconds;
    }
  }
  return {
    runCount,
    distanceMeters,
    activeDurationSeconds,
    paceEligibleRunCount,
    paceDistanceMeters,
    paceActiveDurationSeconds,
  };
}

function scalarFact(window: WindowName, metric: Exclude<MetricName, "weighted_pace">, current: number, prior: number): HomeGuideEvidenceFact {
  const delta = current - prior;
  const percentage = prior > 0 ? Math.round((delta / prior) * 100) : null;
  return {
    id: `${window}.${metric}`,
    window,
    metric,
    direction: directionFor(delta),
    text: `${labelFor(metric)}: ${formatMetric(metric, current)} vs ${formatMetric(metric, prior)} (${formatDelta(metric, delta)}${percentage === null ? "" : `, ${formatPercent(percentage)}`}).`,
  };
}

function weightedPaceFact(window: WindowName, current: Aggregate, prior: Aggregate): HomeGuideEvidenceFact | null {
  if (current.paceEligibleRunCount < 2 || prior.paceEligibleRunCount < 2 || current.paceDistanceMeters <= 0 || prior.paceDistanceMeters <= 0) {
    return null;
  }
  const currentPace = current.paceActiveDurationSeconds / (current.paceDistanceMeters / 1_000);
  const priorPace = prior.paceActiveDurationSeconds / (prior.paceDistanceMeters / 1_000);
  const improvement = priorPace - currentPace;
  const percentage = priorPace > 0 ? Math.round((improvement / priorPace) * 100) : null;
  return {
    id: `${window}.weighted_pace`,
    window,
    metric: "weighted_pace",
    direction: directionFor(improvement),
    text: `Weighted pace: ${formatPace(currentPace)} vs ${formatPace(priorPace)} (${paceDelta(improvement)}${percentage === null ? "" : `, ${formatPercent(percentage)}`}).`,
  };
}

function labelFor(metric: Exclude<MetricName, "weighted_pace">): string {
  switch (metric) {
    case "run_count": return "Run count";
    case "distance": return "Distance";
    case "active_duration": return "Active duration";
  }
}

function formatMetric(metric: Exclude<MetricName, "weighted_pace">, value: number): string {
  switch (metric) {
    case "run_count": {
      const rounded = Math.round(value);
      return `${rounded} ${rounded === 1 ? "run" : "runs"}`;
    }
    case "distance": return `${(value / 1_000).toFixed(1)} km`;
    case "active_duration": return `${Math.round(value / 60)} min`;
  }
}

function formatDelta(metric: Exclude<MetricName, "weighted_pace">, value: number): string {
  if (value === 0) return "no change";
  const sign = value > 0 ? "+" : "-";
  return `${sign}${formatMetric(metric, Math.abs(value))}`;
}

function formatPace(value: number): string {
  const rounded = Math.round(value);
  return `${Math.floor(rounded / 60).toString().padStart(2, "0")}:${(rounded % 60).toString().padStart(2, "0")}/km`;
}

function paceDelta(value: number): string {
  if (value === 0) return "no change";
  return `${value > 0 ? "faster by" : "slower by"} ${formatPace(Math.abs(value))}`;
}

function formatPercent(value: number): string {
  return `${value > 0 ? "+" : ""}${value}%`;
}

function directionFor(value: number): "improving" | "declining" | "steady" {
  return value > 0 ? "improving" : value < 0 ? "declining" : "steady";
}
