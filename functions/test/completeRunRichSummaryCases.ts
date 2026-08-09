import {
  elevationSeriesWithSamples,
  paceAnalysisSeriesWithSamples,
  paceSample,
  rawRouteSnapshot,
  routePreviewWithInvalidOverflowPoint,
  routePreviewWithInvalidOverflowSegment,
  validElevationSeries,
  validElevationSeriesWithSampleCount,
  validPaceAnalysisSeries,
  validPaceAnalysisSeriesWithSampleCount,
} from "./completeRunRichSummaryFixtures.js";

type RejectionScenario = {
  readonly name: string;
  readonly richData: Readonly<Record<string, unknown>>;
  readonly expectedMessage: string;
};

export function rejectionScenarios(): readonly RejectionScenario[] {
  return [
    {
      name: "rejects raw route snapshots",
      richData: { routeSnapshot: rawRouteSnapshot() },
      expectedMessage: "Unsupported field is not accepted: routeSnapshot.",
    },
    routePointFieldScenario("timestamps", "recordedAt", "2026-06-14T09:00:00.000Z"),
    routePointFieldScenario("altitude", "altitudeMeters", 12),
    routePointFieldScenario("horizontal accuracy", "horizontalAccuracyMeters", 4),
    routePointFieldScenario("speed", "speedMetersPerSecond", 2),
    {
      name: "rejects unquantized route preview coordinates",
      richData: {
        routePreview: {
          segments: [{ points: [{ latitude: 1.3000001, longitude: 103.8 }] }],
        },
      },
      expectedMessage: "routePreview.segments.points.latitude must be quantized to 5 decimal places.",
    },
    {
      name: "rejects unsupported pace analysis series fields",
      richData: {
        paceAnalysisSeries: { ...validPaceAnalysisSeries(), routeSnapshot: {} },
      },
      expectedMessage: "paceAnalysisSeries contains unsupported field: routeSnapshot.",
    },
    {
      name: "rejects unsupported pace analysis sample fields",
      richData: {
        paceAnalysisSeries: paceAnalysisSeriesWithSamples([
          { ...paceSample({ elapsedSeconds: 60, cumulativeDistanceMeters: 200 }), latitude: 1.3 },
        ]),
      },
      expectedMessage: "paceAnalysisSeries.samples contains unsupported field: latitude.",
    },
    {
      name: "rejects malformed pace analysis samples",
      richData: {
        paceAnalysisSeries: paceAnalysisSeriesWithSamples([
          {
            elapsedSeconds: 60,
            cumulativeDistanceMeters: 200,
            paceSecondsPerKm: 300,
            status: "rejected",
          },
        ]),
      },
      expectedMessage: "paceAnalysisSeries.samples.status must be accepted.",
    },
    {
      name: "rejects unsupported elevation series fields",
      richData: { elevationSeries: { ...validElevationSeries(), routeSnapshot: {} } },
      expectedMessage: "elevationSeries contains unsupported field: routeSnapshot.",
    },
    {
      name: "rejects unsupported elevation sample fields",
      richData: {
        elevationSeries: elevationSeriesWithSamples([
          { distanceKm: 0, elevationMeters: 12, longitude: 103.8 },
        ]),
      },
      expectedMessage: "elevationSeries.samples contains unsupported field: longitude.",
    },
    {
      name: "rejects malformed elevation analysis samples",
      richData: {
        elevationSeries: elevationSeriesWithSamples([
          { distanceKm: 0, elevationMeters: "high" },
        ]),
      },
      expectedMessage: "elevationSeries.samples.elevationMeters must be a finite number.",
    },
    {
      name: "rejects route previews above 64 segments before inspecting segment bodies",
      richData: { routePreview: routePreviewWithInvalidOverflowSegment() },
      expectedMessage: "routePreview.segments must contain between 1 and 64 segments.",
    },
    {
      name: "rejects route previews above 256 points before inspecting excess points",
      richData: { routePreview: routePreviewWithInvalidOverflowPoint() },
      expectedMessage: "routePreview must contain between 1 and 256 total points.",
    },
    {
      name: "rejects pace analysis series above 360 samples",
      richData: { paceAnalysisSeries: validPaceAnalysisSeriesWithSampleCount(361) },
      expectedMessage: "paceAnalysisSeries.samples must contain between 1 and 360 samples.",
    },
    {
      name: "rejects elevation series above 360 samples",
      richData: { elevationSeries: validElevationSeriesWithSampleCount(361) },
      expectedMessage: "elevationSeries.samples must contain between 1 and 360 samples.",
    },
    paceScenario(
      "rejects pace samples beyond the run duration tolerance",
      [paceSample({ elapsedSeconds: 1561, cumulativeDistanceMeters: 200 })],
      "paceAnalysisSeries.samples.elapsedSeconds exceeds run duration tolerance.",
    ),
    paceScenario(
      "rejects pace samples beyond the run distance tolerance",
      [paceSample({ elapsedSeconds: 60, cumulativeDistanceMeters: 3571 })],
      "paceAnalysisSeries.samples.cumulativeDistanceMeters exceeds run distance tolerance.",
    ),
    paceScenario(
      "rejects non-increasing pace sample elapsed time",
      [
        paceSample({ elapsedSeconds: 60, cumulativeDistanceMeters: 200 }),
        paceSample({ elapsedSeconds: 60, cumulativeDistanceMeters: 400 }),
      ],
      "paceAnalysisSeries.samples.elapsedSeconds must be strictly increasing.",
    ),
    paceScenario(
      "rejects decreasing pace sample distance",
      [
        paceSample({ elapsedSeconds: 60, cumulativeDistanceMeters: 400 }),
        paceSample({ elapsedSeconds: 120, cumulativeDistanceMeters: 200 }),
      ],
      "paceAnalysisSeries.samples.cumulativeDistanceMeters must be monotonic.",
    ),
    elevationScenario(
      "rejects elevation distance beyond the run tolerance",
      [{ distanceKm: 3.58, elevationMeters: 12 }],
      "elevationSeries.samples.distanceKm exceeds run distance tolerance.",
    ),
    elevationScenario(
      "rejects elevation above the sane range",
      [{ distanceKm: 0, elevationMeters: 9001 }],
      "elevationSeries.samples.elevationMeters must be between -500 and 9000.",
    ),
    elevationScenario(
      "rejects elevation below the sane range",
      [{ distanceKm: 0, elevationMeters: -501 }],
      "elevationSeries.samples.elevationMeters must be between -500 and 9000.",
    ),
    elevationScenario(
      "rejects non-increasing elevation sample distance",
      [
        { distanceKm: 0.5, elevationMeters: 12 },
        { distanceKm: 0.5, elevationMeters: 18 },
      ],
      "elevationSeries.samples.distanceKm must be strictly increasing.",
    ),
  ];
}

function routePointFieldScenario(
  label: string,
  field: string,
  value: unknown,
): RejectionScenario {
  return {
    name: `rejects route preview ${label}`,
    richData: {
      routePreview: {
        segments: [{ points: [{ latitude: 1.3, longitude: 103.8, [field]: value }] }],
      },
    },
    expectedMessage: `routePreview.segments.points contains unsupported field: ${field}.`,
  };
}

function paceScenario(
  name: string,
  samples: readonly Readonly<Record<string, unknown>>[],
  expectedMessage: string,
): RejectionScenario {
  return { name, richData: { paceAnalysisSeries: paceAnalysisSeriesWithSamples(samples) }, expectedMessage };
}

function elevationScenario(
  name: string,
  samples: readonly Readonly<Record<string, unknown>>[],
  expectedMessage: string,
): RejectionScenario {
  return { name, richData: { elevationSeries: elevationSeriesWithSamples(samples) }, expectedMessage };
}
