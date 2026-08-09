// Wire types for the planned-workout briefing agent.
//
// Everything the client sends is short display copy the runner is already
// looking at on the workout detail screen. There is deliberately no identifier,
// timestamp, nickname, or location field anywhere in this contract: the model's
// job is to explain what is on screen, not to look anything up.

export type WorkoutBriefingMetric = {
  readonly label: string;
  readonly value: string;
};

export type WorkoutBriefingStep = {
  readonly title: string;
  readonly detail: string;
};

export type WorkoutBriefingWorkout = {
  readonly dayLabel: string;
  readonly planTitle: string;
  readonly effortGuide: string;
  readonly weekNumber?: number;
  readonly weekFocus?: string;
};

export type WorkoutBriefingRequest = {
  readonly schemaVersion: 1;
  readonly workout: WorkoutBriefingWorkout;
  readonly metrics: readonly WorkoutBriefingMetric[];
  readonly steps: readonly WorkoutBriefingStep[];
  readonly coachNotes: readonly string[];
};

export type WorkoutBriefingSections = {
  readonly todaySession: string;
  readonly whyItHelps: string;
  readonly howItFeels: string;
  readonly beforeYouStart: string;
};

export type WorkoutBriefingAgentResponse =
  | {
      readonly source: "agent";
      readonly delivery: "generated";
      readonly sections: WorkoutBriefingSections;
    }
  | {
      readonly source: "unavailable";
      readonly delivery: "fallback";
      readonly sections: WorkoutBriefingSections;
    }
  | {
      readonly source: "quota";
      readonly delivery: "quota";
      readonly sections: WorkoutBriefingSections;
      readonly retryAfterDate: string;
    };
