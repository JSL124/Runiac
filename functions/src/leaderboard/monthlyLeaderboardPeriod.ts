import { leaderboardTimezone } from "./leaderboardTypes.js";

export function currentSingaporeMonthKey(now: Date): string {
  const singaporeTime = new Date(now.getTime() + 8 * 60 * 60 * 1000);
  return singaporeTime.toISOString().slice(0, 7);
}
export function nextSingaporeMonthStart(periodKey: string): string {
  const parsed = parsePeriodKey(periodKey);
  if (parsed === null) {
    return "";
  }
  return new Date(
    Date.UTC(parsed.year, parsed.month, 0, 16, 0, 0, 0),
  ).toISOString();
}

export function singaporeMonthLabel(periodKey: string): string {
  const parsed = parsePeriodKey(periodKey);
  if (parsed === null) {
    return "";
  }
  return new Intl.DateTimeFormat("en-US", {
    month: "long",
    year: "numeric",
    timeZone: leaderboardTimezone,
  }).format(new Date(Date.UTC(parsed.year, parsed.month - 1, 1)));
}

export function retainedPeriodKeys(periodKey: string): ReadonlySet<string> {
  const parsed = parsePeriodKey(periodKey);
  if (parsed === null) {
    return new Set([periodKey]);
  }
  const periods = new Set<string>();
  for (let offset = 0; offset < 3; offset += 1) {
    const date = new Date(Date.UTC(parsed.year, parsed.month - 1 - offset, 1));
    periods.add(
      `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`,
    );
  }
  return periods;
}

function parsePeriodKey(
  periodKey: string,
): { readonly year: number; readonly month: number } | null {
  const match = /^(\d{4})-(\d{2})$/.exec(periodKey);
  if (match === null) {
    return null;
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  return Number.isInteger(year) &&
    Number.isInteger(month) &&
    month >= 1 &&
    month <= 12
    ? { year, month }
    : null;
}

