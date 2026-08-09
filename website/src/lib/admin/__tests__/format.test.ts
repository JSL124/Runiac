import { describe, expect, it } from "vitest";

import { formatDateTime, formatNumber } from "../format";

describe("formatNumber", () => {
  it("groups thousands using en-GB separators", () => {
    expect(formatNumber(1234567)).toBe("1,234,567");
  });

  it("formats zero as a plain digit", () => {
    expect(formatNumber(0)).toBe("0");
  });

  it("formats negative numbers with a leading minus sign", () => {
    expect(formatNumber(-4200)).toBe("-4,200");
  });
});

describe("formatDateTime", () => {
  it("returns a string ending in ' UTC'", () => {
    expect(formatDateTime("2026-07-15T08:30:00.000Z")).toMatch(/ UTC$/);
  });

  it("is stable for a fixed ISO input", () => {
    const result = formatDateTime("2026-07-15T08:30:00.000Z");
    expect(result).toBe(formatDateTime("2026-07-15T08:30:00.000Z"));
    // Locks the current en-GB, UTC, 24h rendering so an accidental format
    // change (e.g. switching to 12h or a different locale) fails loudly.
    expect(result).toBe("15 Jul 2026, 08:30 UTC");
  });
});
