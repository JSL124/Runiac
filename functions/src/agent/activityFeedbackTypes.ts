export type ActivityFeedbackSummaryMetrics = {
  readonly distanceKm: number;
  readonly durationSeconds: number;
  readonly averagePaceSecondsPerKm: number;
  readonly caloriesKcal?: number;
  readonly sourceLabel: string;
};

export type ActivityFeedbackPerformanceMetrics = {
  readonly score?: number;
  readonly qualityLabel?: string;
  readonly takeaway?: string;
  readonly nextFocus?: string;
  readonly scoreConfidenceLabel?: string;
};

export type ActivityFeedbackSplitMetrics = {
  readonly distanceKm: number;
  readonly paceSecondsPerKm: number;
  readonly isPartial: boolean;
  readonly elevationMeters?: number;
};

export type ActivityFeedbackPaceMetrics = {
  readonly fastestPaceSecondsPerKm?: number;
  readonly slowestPaceSecondsPerKm?: number;
  readonly stabilityLabel?: string;
  readonly splits?: readonly ActivityFeedbackSplitMetrics[];
};

export type ActivityFeedbackCadenceMetrics = {
  readonly averageSpm?: number;
  readonly status?: string;
  readonly strideConsistency?: string;
  readonly isEstimated?: boolean;
  readonly confidence?: string;
  readonly sourceReason?: string;
};

export type ActivityFeedbackElevationMetrics = {
  readonly totalGainMeters?: number;
  readonly highestPointMeters?: number;
  readonly lowestPointMeters?: number;
  readonly difficulty?: string;
};

export type ActivityFeedbackRequest = {
  readonly schemaVersion: 1;
  readonly summary: ActivityFeedbackSummaryMetrics;
  readonly performance?: ActivityFeedbackPerformanceMetrics;
  readonly pace?: ActivityFeedbackPaceMetrics;
  readonly cadence?: ActivityFeedbackCadenceMetrics;
  readonly elevation?: ActivityFeedbackElevationMetrics;
  readonly unavailable?: readonly string[];
};

export type ActivityFeedbackSections = {
  readonly summary: string;
  readonly wentWell: string;
  readonly improve: string;
  readonly nextFocus: string;
};

export type ActivityFeedbackAgentResponse =
  | { readonly source: "agent"; readonly delivery: "generated"; readonly sections: ActivityFeedbackSections }
  | { readonly source: "unavailable"; readonly delivery: "fallback"; readonly sections: ActivityFeedbackSections }
  | { readonly source: "quota"; readonly delivery: "quota"; readonly sections: ActivityFeedbackSections; readonly retryAfterDate: string };
