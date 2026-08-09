import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  ActivityFeedbackContractError,
  parseActivityFeedbackRequest,
} from "../src/agent/activityFeedbackContracts.js";

describe("activity feedback derived-metrics boundary", () => {
  it("accepts the exact derived-metrics request contract", () => {
    // Given
    const request = validRequest();

    // When
    const parsed = parseActivityFeedbackRequest(request);

    // Then
    assert.equal(parsed.schemaVersion, 1);
    assert.equal(parsed.summary.distanceKm, 5.2);
    assert.equal(parsed.pace?.splits?.length, 2);
    assert.equal(parsed.cadence?.isEstimated, true);
  });

  it("rejects raw route, persistent identity, and demo-only fields at every depth", () => {
    // Given
    const forbiddenRequests = [
      { ...validRequest(), routeName: "Home loop" },
      { ...validRequest(), activityId: "activity-123" },
      { ...validRequest(), route: { points: [] } },
      { ...validRequest(), polyline: "encoded-geometry" },
      { ...validRequest(), coordinates: [{ latitude: 1.3, longitude: 103.8 }] },
      { ...validRequest(), demoOnly: true },
      { ...validRequest(), summary: { ...validRequest().summary, activityId: "activity-123" } },
      {
        ...validRequest(),
        pace: {
          ...validRequest().pace,
          splits: [{ distanceKm: 1, paceSecondsPerKm: 370, isPartial: false, coordinates: [] }],
        },
      },
      { ...validRequest(), cadence: { ...validRequest().cadence, demoOnly: "170 spm" } },
    ];

    // When / Then
    for (const request of forbiddenRequests) {
      assert.throws(() => parseActivityFeedbackRequest(request), ActivityFeedbackContractError);
    }
  });

  it("rejects demo imports and malformed or unbounded derived values", () => {
    // Given
    const invalidRequests = [
      { ...validRequest(), summary: { ...validRequest().summary, sourceLabel: "Demo import" } },
      { ...validRequest(), summary: { ...validRequest().summary, distanceKm: Number.NaN } },
      { ...validRequest(), summary: { ...validRequest().summary, durationSeconds: -1 } },
      { ...validRequest(), performance: { score: 101 } },
      { ...validRequest(), pace: { splits: Array.from({ length: 201 }, () => ({ distanceKm: 1, paceSecondsPerKm: 360, isPartial: false })) } },
      { ...validRequest(), unavailable: ["x".repeat(121)] },
    ];

    // When / Then
    for (const request of invalidRequests) {
      assert.throws(() => parseActivityFeedbackRequest(request), ActivityFeedbackContractError);
    }
  });

  it("normalizes bounded derived labels while preserving cadence estimation metadata", () => {
    // Given
    const request = {
      ...validRequest(),
      performance: { qualityLabel: "  Steady\n effort  " },
      cadence: { averageSpm: 166, isEstimated: true, confidence: " estimated " },
    };

    // When
    const parsed = parseActivityFeedbackRequest(request);

    // Then
    assert.equal(parsed.performance?.qualityLabel, "Steady effort");
    assert.deepEqual(parsed.cadence, {
      averageSpm: 166,
      isEstimated: true,
      confidence: "estimated",
    });
  });
});

function validRequest() {
  return {
    schemaVersion: 1,
    summary: {
      distanceKm: 5.2,
      durationSeconds: 1920,
      averagePaceSecondsPerKm: 369,
      caloriesKcal: 321,
      sourceLabel: "Runiac GPS",
    },
    performance: {
      score: 78,
      qualityLabel: "Steady effort",
      takeaway: "The pace stayed controlled.",
      nextFocus: "Keep the opening kilometre relaxed.",
      scoreConfidenceLabel: "Derived from local run metrics",
    },
    pace: {
      fastestPaceSecondsPerKm: 350,
      slowestPaceSecondsPerKm: 390,
      stabilityLabel: "Stable",
      splits: [
        { distanceKm: 1, paceSecondsPerKm: 370, isPartial: false, elevationMeters: 4 },
        { distanceKm: 0.2, paceSecondsPerKm: 380, isPartial: true },
      ],
    },
    cadence: {
      averageSpm: 166,
      status: "Consistent",
      strideConsistency: "Stable",
      isEstimated: true,
      confidence: "estimated",
      sourceReason: "estimatedFromPhoneSensors",
    },
    elevation: {
      totalGainMeters: 34,
      highestPointMeters: 48,
      lowestPointMeters: 12,
      difficulty: "Mostly Flat",
    },
    unavailable: ["cadence.zones"],
  };
}
