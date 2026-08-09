import type { DocumentData, DocumentReference, Transaction } from "firebase-admin/firestore";
import type { CompleteRunIds, RawRunCompletionPayload } from "../run/runCompletionTypes.js";

type PersistAdaptiveEstimateInput = {
  readonly transaction: Transaction;
  readonly estimateRef: DocumentReference;
  readonly uid: string;
  readonly ids: CompleteRunIds;
  readonly payload: RawRunCompletionPayload;
  readonly estimateData: DocumentData | undefined;
};

export function persistAdaptiveEstimateLearning(input: PersistAdaptiveEstimateInput): void {
  const previousRunCount = readNonNegativeInteger(input.estimateData?.["completedRunCount"]);
  const completedRunCount = previousRunCount + 1;
  const currentPace = readNonNegativeNumber(input.payload.avgPaceSecondsPerKm) ?? 0;
  const previousAveragePace = readPositiveNumber(input.estimateData?.["averageRecentPaceSecondsPerKm"]);
  const previousPositivePaceRunCount = readPositivePaceRunCount(input.estimateData, previousAveragePace, previousRunCount);
  const positivePaceRunCount = currentPace > 0 ? previousPositivePaceRunCount + 1 : previousPositivePaceRunCount;
  const averageRecentPaceSecondsPerKm =
    currentPace > 0 ? averagePace(previousAveragePace, previousPositivePaceRunCount, currentPace, positivePaceRunCount) : previousAveragePace ?? 0;

  input.transaction.set(input.estimateRef, {
    ownerUid: input.uid,
    latestActivityId: input.ids.activityId,
    latestAcceptedActivityId: input.ids.activityId,
    latestClientRunSessionId: input.payload.clientRunSessionId,
    completedRunCount,
    lastRunStartedAt: input.payload.startedAt,
    lastRunEndedAt: input.payload.completedAt,
    lastRunCompletedAt: input.payload.completedAt,
    lastRunDistanceMeters: input.payload.distanceMeters,
    lastRunDurationSeconds: input.payload.durationSeconds,
    averageRecentPaceSecondsPerKm,
    positivePaceRunCount,
    readinessBand: currentPace > 0 ? "learning" : "conservative",
    source: "completeRun",
    updatedAt: input.payload.completedAt,
  });
}

function averagePace(
  previousAveragePace: number | undefined,
  previousRunCount: number,
  currentPace: number,
  completedRunCount: number,
): number {
  if (previousAveragePace === undefined || previousRunCount === 0) {
    return Math.round(currentPace);
  }

  return Math.round((previousAveragePace * previousRunCount + currentPace) / completedRunCount);
}

function readNonNegativeInteger(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : 0;
}

function readNonNegativeNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : undefined;
}

function readPositiveNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : undefined;
}

function readPositivePaceRunCount(
  estimateData: DocumentData | undefined,
  previousAveragePace: number | undefined,
  previousRunCount: number,
): number {
  const persistedCount = readNonNegativeInteger(estimateData?.["positivePaceRunCount"]);
  if (persistedCount > 0) {
    return persistedCount;
  }

  return previousAveragePace === undefined ? 0 : previousRunCount;
}
