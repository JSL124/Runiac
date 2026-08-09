export type RoutePrivacy = "private" | "public";

export type RawRunCompletionPayload = {
  readonly clientRunSessionId: string;
  readonly startedAt: string;
  readonly completedAt: string;
  readonly durationSeconds: number;
  readonly activeDurationSeconds: number;
  readonly elapsedWallSeconds: number;
  readonly pausedDurationSeconds: number;
  readonly distanceMeters: number;
  readonly avgPaceSecondsPerKm: number;
  readonly source: "mobile";
  readonly routePrivacy: RoutePrivacy;
  readonly userConfirmedLowDataSave?: boolean;
  readonly activityTitle?: string;
  readonly routeLabel?: string;
  readonly caloriesEstimate?: number;
  readonly planEnrollmentId?: string;
  readonly scheduledWorkoutId?: string;
  readonly deviceRecordedAt?: string;
  readonly clientAppVersion?: string;
  readonly cadenceAnalysisSeries?: CadenceAnalysisSeriesPayload;
  readonly routePreview?: RoutePreviewPayload;
  readonly paceAnalysisSeries?: PaceAnalysisSeriesPayload;
  readonly elevationSeries?: ElevationSeriesPayload;
};

export type CadenceAnalysisSeriesPayload = {
  readonly source: "phoneSensorEstimated";
  readonly confidence: "low";
  readonly samples: readonly CadenceAnalysisSamplePayload[];
};

export type CadenceAnalysisSamplePayload = {
  readonly elapsedSeconds: number;
  readonly cadenceSpm: number;
  readonly status: "accepted";
};

export type RoutePreviewPayload = {
  readonly segments: readonly RoutePreviewSegmentPayload[];
};

export type RoutePreviewSegmentPayload = {
  readonly points: readonly RoutePreviewPointPayload[];
};

export type RoutePreviewPointPayload = {
  readonly latitude: number;
  readonly longitude: number;
};

export type PaceAnalysisSeriesPayload = {
  readonly source: "localAccepted";
  readonly confidence: "derived";
  readonly samples: readonly PaceAnalysisSamplePayload[];
};

export type PaceAnalysisSamplePayload = {
  readonly elapsedSeconds: number;
  readonly cumulativeDistanceMeters: number;
  readonly paceSecondsPerKm: number;
  readonly status: "accepted";
};

export type ElevationSeriesPayload = {
  readonly source: "runiacLocalAccepted";
  readonly confidence: "medium";
  readonly samples: readonly ElevationSamplePayload[];
};

export type ElevationSamplePayload = {
  readonly distanceKm: number;
  readonly elevationMeters: number;
};

export type CompleteRunIds = {
  readonly activityId: string;
  readonly summaryId: string;
  readonly progressionEventId: string;
};

export type ProgressionDisplay = {
  readonly xpDelta: number;
  readonly countsTowardLeaderboard: boolean;
  readonly status: "awarded" | "not_awarded" | "deferred";
  readonly reason:
    | "run_completion_xp_awarded"
    | "low_data_no_xp"
    | "daily_cap_reached"
    | "premium_no_progression"
    | "progression_formula_deferred"
    | "cool_down_stretch_bonus_awarded"
    | "cool_down_daily_cap_reached";
  readonly totalXp?: number;
  readonly level?: number;
  readonly divisionKey?: string;
  readonly previousTotalXp?: number;
  readonly previousLevel?: number;
  readonly previousLevelProgressPercent?: number;
  readonly levelProgressPercent?: number;
  readonly nextLevelXp?: number | null;
  readonly xpToNextLevel?: number | null;
  readonly previousStreak?: number;
  readonly streak?: number;
};

export type RunSummaryResult = {
  readonly title: string;
  readonly startedAt: string;
  readonly endedAt: string;
  readonly distanceMeters: number;
  readonly durationSeconds: number;
  readonly activeDurationSeconds: number;
  readonly elapsedWallSeconds: number;
  readonly pausedDurationSeconds: number;
  readonly averagePaceSecondsPerKm: number;
  readonly displayDistance: string;
  readonly displayDuration: string;
  readonly displayPace: string;
  readonly routeLabel?: string;
  readonly cadenceAnalysisSeries?: CadenceAnalysisSeriesPayload;
  readonly routePreview?: RoutePreviewPayload;
  readonly paceAnalysisSeries?: PaceAnalysisSeriesPayload;
  readonly elevationSeries?: ElevationSeriesPayload;
};

export type PlanCompletionResult = {
  readonly completed: boolean;
  readonly planEnrollmentId?: string;
  readonly scheduledWorkoutId?: string;
};

export type CompleteRunResult = CompleteRunIds & {
  readonly validationStatus: "validated";
  readonly runSummary: RunSummaryResult;
  readonly progressionDisplay: ProgressionDisplay;
  readonly planCompletion: PlanCompletionResult;
  readonly message: string;
};

export type RawCoolDownCompletionPayload = {
  readonly activityId: string;
  readonly clientRunSessionId: string;
  readonly completedStretchCount: number;
  readonly completedAt: string;
};

export type CompleteCoolDownResult = {
  readonly activityId: string;
  readonly coolDownProgressionEventId: string;
  readonly alreadyAwarded: boolean;
  readonly progressionDisplay: ProgressionDisplay;
};
