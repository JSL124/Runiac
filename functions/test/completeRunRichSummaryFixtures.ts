import assert from "node:assert/strict";

export function validPayload(): Record<string, unknown> {
  return {
    clientRunSessionId: "local-session-rich-summary",
    startedAt: "2026-06-14T09:00:00.000Z",
    completedAt: "2026-06-14T09:25:00.000Z",
    durationSeconds: 1500,
    distanceMeters: 3200,
    avgPaceSecondsPerKm: 469,
    source: "mobile",
    routePrivacy: "private",
  };
}

export function validRoutePreview(segmentCount: number, pointsPerSegment: number): Record<string, unknown> {
  return {
    segments: Array.from({ length: segmentCount }, (_, segmentIndex) => ({
      points: Array.from({ length: pointsPerSegment }, (_, pointIndex) => {
        const index = segmentIndex * pointsPerSegment + pointIndex;
        return {
          latitude: Number((1.3 + (index % 100) / 100000).toFixed(5)),
          longitude: Number((103.8 + (index % 100) / 100000).toFixed(5)),
        };
      }),
    })),
  };
}

export function rawRouteSnapshot(): Record<string, unknown> {
  return {
    segments: [
      {
        points: [
          {
            recordedAt: "2026-06-14T09:00:00.000Z",
            latitude: 1.3001,
            longitude: 103.8301,
            altitudeMeters: 12,
          },
        ],
      },
    ],
  };
}

export function routePreviewWithInvalidOverflowSegment(): Record<string, unknown> {
  const routePreview = validRoutePreview(64, 1);
  const segments = routePreview["segments"];
  assert.ok(Array.isArray(segments));
  return { segments: [...segments, { points: "not-an-array" }] };
}

export function routePreviewWithInvalidOverflowPoint(): Record<string, unknown> {
  const routePreview = validRoutePreview(1, 256);
  const segments = routePreview["segments"];
  assert.ok(Array.isArray(segments));
  const firstSegment = segments[0];
  assert.ok(isRecord(firstSegment));
  const points = firstSegment["points"];
  assert.ok(Array.isArray(points));
  return {
    segments: [{ points: [...points, { latitude: "not-a-number", longitude: 103.8 }] }],
  };
}

export function validPaceAnalysisSeries(): Record<string, unknown> {
  return validPaceAnalysisSeriesWithSampleCount(2);
}

export function validPaceAnalysisSeriesWithSampleCount(sampleCount: number): Record<string, unknown> {
  return paceAnalysisSeriesWithSamples(
    Array.from({ length: sampleCount }, (_, index) =>
      paceSample({
        elapsedSeconds: index * 4,
        cumulativeDistanceMeters: index * 8,
        paceSecondsPerKm: 300 + (index % 5),
      }),
    ),
  );
}

export function paceAnalysisSeriesWithSamples(
  samples: readonly Readonly<Record<string, unknown>>[],
): Record<string, unknown> {
  return { source: "localAccepted", confidence: "derived", samples };
}

export function paceSample(fields: {
  readonly elapsedSeconds: number;
  readonly cumulativeDistanceMeters: number;
  readonly paceSecondsPerKm?: number;
}): Record<string, unknown> {
  return {
    elapsedSeconds: fields.elapsedSeconds,
    cumulativeDistanceMeters: fields.cumulativeDistanceMeters,
    paceSecondsPerKm: fields.paceSecondsPerKm ?? 300,
    status: "accepted",
  };
}

export function validElevationSeries(): Record<string, unknown> {
  return validElevationSeriesWithSampleCount(2);
}

export function validElevationSeriesWithSampleCount(sampleCount: number): Record<string, unknown> {
  return elevationSeriesWithSamples(
    Array.from({ length: sampleCount }, (_, index) => ({
      distanceKm: index * 0.009,
      elevationMeters: 12 + (index % 7),
    })),
  );
}

export function elevationSeriesWithSamples(
  samples: readonly Readonly<Record<string, unknown>>[],
): Record<string, unknown> {
  return { source: "runiacLocalAccepted", confidence: "medium", samples };
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
