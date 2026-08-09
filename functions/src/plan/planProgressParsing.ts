const weekdayOffsets: Readonly<Record<string, number>> = {
  Mon: 0,
  Tue: 1,
  Wed: 2,
  Thu: 3,
  Fri: 4,
  Sat: 5,
  Sun: 6,
} as const;

export const weekdayLabels: readonly string[] = Object.keys(weekdayOffsets);

/**
 * Accepts the canonical short labels plus longer spellings such as "Friday" or
 * "friday". Plans written by the notification path use those, and returning
 * `undefined` for them would leave the day with no scheduled date at all — which
 * downstream rest-day derivation would then read as a rest day.
 */
export function weekdayOffsetFor(dayLabel: string): number | undefined {
  const exact = weekdayOffsets[dayLabel];
  if (exact !== undefined) {
    return exact;
  }

  const normalized = dayLabel.trim().toLowerCase().slice(0, 3);
  return Object.entries(weekdayOffsets).find(
    ([label]) => label.toLowerCase() === normalized,
  )?.[1];
}

export function scheduledDateFor(
  startsOnDate: string | undefined,
  weekNumber: number,
  dayLabel: string,
): string | null {
  if (startsOnDate === undefined) {
    return null;
  }

  const weekdayOffset = weekdayOffsetFor(dayLabel);
  if (weekdayOffset === undefined) {
    return null;
  }

  const startTime = Date.parse(`${startsOnDate}T00:00:00.000Z`);
  if (Number.isNaN(startTime)) {
    return null;
  }

  const millisecondsPerDay = 86_400_000;
  const dayOffset = (weekdayOffset - startWeekdayOffset(startTime) + 7) % 7;
  const date = new Date(startTime + ((weekNumber - 1) * 7 + dayOffset) * millisecondsPerDay);
  return date.toISOString().slice(0, 10);
}

/**
 * `dayLabel` denotes a real weekday (it comes from the user's preferred days),
 * but `startsOnDate` is whatever day onboarding finished. Week N therefore runs
 * for seven days from that start, and a label resolves to the one date in that
 * window whose actual weekday matches. When the plan starts on a Monday this is
 * identical to anchoring offset 0 to Monday, so Monday-start plans are unchanged.
 */
function startWeekdayOffset(startTime: number): number {
  return (new Date(startTime).getUTCDay() + 6) % 7;
}

export function fallbackWorkoutId(weekNumber: number, dayLabel: string, title: string): string {
  const titleSlug = title.toLowerCase().replaceAll(/[^a-z0-9]+/g, "-").replaceAll(/^-|-$/g, "");
  return `week-${weekNumber}-${dayLabel.toLowerCase()}-${titleSlug || "workout"}`;
}

export function datePart(isoDate: string): string {
  return isoDate.slice(0, 10);
}

export function readOptionalString(value: unknown): string | undefined {
  if (typeof value !== "string" || value.trim().length === 0) {
    return undefined;
  }
  return value;
}

export function readOptionalInteger(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    return undefined;
  }

  return value;
}

export function readOptionalPositiveNumber(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return undefined;
  }

  return value;
}

export function isRestWorkout(value: Readonly<Record<string, unknown>>): boolean {
  const kind = readOptionalString(value["kind"]);
  return kind === "rest" || kind === "restDay";
}

export function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
