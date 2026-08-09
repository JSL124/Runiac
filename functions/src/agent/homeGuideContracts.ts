// The data contract for the Home guide agent: exactly which fields it may read
// about a runner, and in what shape.
//
// [HOME_GUIDE_ACTIVITY_PROJECTION] is the important one. The agent's prompt is
// built only from these fields, so an activity document gaining new fields
// later cannot quietly widen what gets sent to the model. Anything that should
// never reach an LLM simply stays off this list.
//
// The `Trusted*` types mark values that have already been read through that
// projection — passing a raw Firestore document where one is expected is a type
// error, which is the point.

export const HOME_GUIDE_ACTIVITY_PROJECTION = [
  "ownerUid",
  "status",
  "validationStatus",
  "activityType",
  "endedAt",
  "activeDurationSeconds",
  "distanceMeters",
  "averagePaceSecondsPerKm",
] as const;

export type HomeGuidePlanDisplayContext = {
  readonly planTitle: string;
  readonly weekNumber: number;
  readonly weekFocus: string;
  readonly dayLabel: string;
  readonly workoutTitle: string;
  readonly durationMinutes: number;
  readonly intensity: string;
  readonly description: string;
  readonly steps: readonly string[];
  readonly supportiveNote: string;
};

export type TrustedHomeGuideActivity = {
  readonly endedAt: string;
  readonly activeDurationSeconds: number;
  readonly distanceMeters: number;
  readonly averagePaceSecondsPerKm: number | null;
};

export type HomeGuideActivityBoundary = {
  readonly ownerUid: string;
  readonly startsAt: Date;
  readonly endsBefore: Date;
};

export type HomeGuideActivityQuery = {
  readonly where: (
    fieldPath: string,
    operator: "==" | ">=" | "<",
    value: string,
  ) => HomeGuideActivityQuery;
  readonly select: (...fieldPaths: string[]) => {
    readonly get: () => Promise<{
      readonly docs: readonly { readonly data: () => Readonly<Record<string, unknown>> }[];
    }>;
  };
};

export type HomeGuideActivityQuerySource = {
  readonly collection: (collectionName: "activities") => HomeGuideActivityQuery;
};

export type HomeGuideEvidenceFact = {
  readonly id: string;
  readonly window: "week_to_date" | "rolling_28_days";
  readonly metric: "run_count" | "distance" | "active_duration" | "weighted_pace";
  readonly direction: "improving" | "declining" | "steady";
  readonly text: string;
};

export type HomeGuideEvidence = {
  readonly facts: readonly HomeGuideEvidenceFact[];
};

const MAX_TEXT_LENGTH = 200;
const MAX_DESCRIPTION_LENGTH = 800;
const MAX_STEPS = 12;
const MAX_PLAN_MARKER_LENGTH = 128;
const allowedPlanContextKeys = new Set([
  "planTitle",
  "weekNumber",
  "weekFocus",
  "dayLabel",
  "workoutTitle",
  "durationMinutes",
  "intensity",
  "description",
  "steps",
  "supportiveNote",
]);
const isoTimestampPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

export class HomeGuideContractError extends Error {
  public constructor(readonly field: string, message: string) {
    super(message);
    this.name = "HomeGuideContractError";
  }
}

export function parseHomeGuidePlanDisplayContext(data: unknown): HomeGuidePlanDisplayContext {
  if (!isRecord(data)) {
    throw invalid("payload", "Home guide plan context must be an object.");
  }
  for (const key of Object.keys(data)) {
    if (!allowedPlanContextKeys.has(key)) {
      throw invalid(key, `Unsupported plan context field: ${key}.`);
    }
  }

  return {
    planTitle: readText(data, "planTitle", MAX_TEXT_LENGTH),
    weekNumber: readPositiveInteger(data, "weekNumber"),
    weekFocus: readText(data, "weekFocus", MAX_TEXT_LENGTH),
    dayLabel: readText(data, "dayLabel", MAX_TEXT_LENGTH),
    workoutTitle: readText(data, "workoutTitle", MAX_TEXT_LENGTH),
    durationMinutes: readPositiveInteger(data, "durationMinutes"),
    intensity: readText(data, "intensity", MAX_TEXT_LENGTH),
    description: readText(data, "description", MAX_DESCRIPTION_LENGTH),
    steps: readSteps(data),
    supportiveNote: readText(data, "supportiveNote", MAX_TEXT_LENGTH),
  };
}

export function readTrustedHomeGuideActivity(
  data: Readonly<Record<string, unknown>>,
  boundary: HomeGuideActivityBoundary,
): TrustedHomeGuideActivity | null {
  if (
    data["ownerUid"] !== boundary.ownerUid ||
    data["status"] !== "validated" ||
    data["validationStatus"] !== "validated" ||
    data["activityType"] !== "run"
  ) {
    return null;
  }
  const endedAt = data["endedAt"];
  if (typeof endedAt !== "string" || !isoTimestampPattern.test(endedAt)) {
    return null;
  }
  const endedAtMillis = Date.parse(endedAt);
  if (!Number.isFinite(endedAtMillis) || endedAtMillis < boundary.startsAt.getTime() || endedAtMillis >= boundary.endsBefore.getTime()) {
    return null;
  }
  const activeDurationSeconds = readFiniteNonNegative(data["activeDurationSeconds"]);
  const distanceMeters = readFiniteNonNegative(data["distanceMeters"]);
  const averagePaceSecondsPerKm = readFiniteNonNegative(data["averagePaceSecondsPerKm"]);
  if (activeDurationSeconds === null || distanceMeters === null || averagePaceSecondsPerKm === null) {
    return null;
  }

  return { endedAt, activeDurationSeconds, distanceMeters, averagePaceSecondsPerKm };
}

export function activePlanMarker(value: unknown): string {
  if (typeof value !== "string") {
    return "no-active-plan";
  }
  const marker = normalizeText(value);
  return marker.length > 0 && marker.length <= MAX_PLAN_MARKER_LENGTH ? marker : "no-active-plan";
}

export async function readTrustedHomeGuideActivities(
  source: HomeGuideActivityQuerySource,
  ownerUid: string,
  now: Date,
): Promise<readonly TrustedHomeGuideActivity[]> {
  const endsBefore = now;
  const startsAt = new Date(endsBefore.getTime() - 56 * 24 * 60 * 60 * 1_000);
  if (!Number.isFinite(startsAt.getTime()) || !Number.isFinite(endsBefore.getTime())) {
    return [];
  }
  const snapshot = await source.collection("activities")
    .where("ownerUid", "==", ownerUid)
    .where("endedAt", ">=", startsAt.toISOString())
    .where("endedAt", "<", endsBefore.toISOString())
    .select(...HOME_GUIDE_ACTIVITY_PROJECTION)
    .get();
  const boundary = { ownerUid, startsAt, endsBefore };
  return snapshot.docs.flatMap((document) => {
    const activity = readTrustedHomeGuideActivity(document.data(), boundary);
    return activity === null ? [] : [activity];
  });
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readText(data: Readonly<Record<string, unknown>>, key: string, maximumLength: number): string {
  return readNormalizedText(data[key], key, maximumLength);
}

function readNormalizedText(value: unknown, field: string, maximumLength: number): string {
  if (typeof value !== "string") {
    throw invalid(field, `${field} must be a string.`);
  }
  const normalized = normalizeText(value);
  if (normalized.length === 0 || normalized.length > maximumLength) {
    throw invalid(field, `${field} must contain 1-${maximumLength} characters.`);
  }
  return normalized;
}

function readPositiveInteger(data: Readonly<Record<string, unknown>>, key: string): number {
  const value = data[key];
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
    throw invalid(key, `${key} must be a positive integer.`);
  }
  return value;
}

function readSteps(data: Readonly<Record<string, unknown>>): readonly string[] {
  const value = data["steps"];
  if (!Array.isArray(value) || value.length > MAX_STEPS) {
    throw invalid("steps", `steps must contain at most ${MAX_STEPS} text items.`);
  }
  return value.map((step, index) => readNormalizedText(step, `steps[${index}]`, MAX_TEXT_LENGTH));
}

function normalizeText(value: string): string {
  return value.replace(/\s+/gu, " ").trim();
}

function readFiniteNonNegative(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : null;
}

function invalid(field: string, message: string): HomeGuideContractError {
  return new HomeGuideContractError(field, message);
}
