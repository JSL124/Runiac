export const feedPostStatuses = ["published", "deleting", "deleted"] as const;

export type FeedPostStatus = (typeof feedPostStatuses)[number];

export type FeedPost = {
  readonly authorUid: string;
  readonly activityId: string;
  readonly authorDisplayName: string;
  readonly authorAvatarInitials: string;
  readonly authorLevelLabel: string;
  readonly completedAt: string;
  readonly distanceMeters: number;
  readonly durationSeconds: number;
  readonly averagePaceSecondsPerKm: number;
  readonly thumbnailStoragePath: string;
  readonly thumbnailObjectGeneration: string;
  readonly thumbnailSha256: string;
  readonly likeCount: number;
  readonly commentCount: number;
  readonly status: "published";
  readonly schemaVersion: 1;
  readonly createdAt: string;
  readonly updatedAt: string;
};

export type FeedPublishPayload = { readonly activityId: string; readonly stagingPath: string };
export type FeedContractError =
  | { readonly kind: "invalid_payload"; readonly code: "unknown_key" | "invalid_field" | "unsafe_path" }
  | { readonly kind: "invalid_activity"; readonly code: "owner" | "validation" }
  | { readonly kind: "invalid_profile"; readonly code: "owner" | "display" }
  | { readonly kind: "invalid_thumbnail"; readonly code: "path" | "generation" | "sha256" }
  | { readonly kind: "invalid_transition"; readonly from: FeedPostStatus; readonly to: FeedPostStatus };
export type FeedResult<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: FeedContractError };

export type ValidatedOwnedActivity = {
  readonly activityId: string;
  readonly ownerUid: string;
  readonly status: "validated";
  readonly validationStatus: "validated";
  readonly completedAt: string;
  readonly distanceMeters: number;
  readonly durationSeconds: number;
  readonly averagePaceSecondsPerKm: number;
};
export type PrivateProfileSnapshot = { readonly uid: string; readonly displayName: string; readonly avatarInitials: string; readonly levelLabel: string };
export type FinalThumbnail = { readonly storagePath: string; readonly objectGeneration: string; readonly sha256: string };
export type FeedPostBuildInput = {
  readonly activity: ValidatedOwnedActivity;
  readonly profile: PrivateProfileSnapshot;
  readonly thumbnail: FinalThumbnail;
  readonly now: string;
};

const completeRunActivityFields = [
  "ownerUid", "status", "source", "activityType", "startedAt", "endedAt", "durationSeconds",
  "activeDurationSeconds", "elapsedWallSeconds", "pausedDurationSeconds", "distanceMeters",
  "averagePaceSecondsPerKm", "routePrivacy", "clientRunSessionId", "payloadFingerprint", "createdAt",
  "updatedAt", "processedAt", "validationStatus", "validatedActivityContributionState",
  "countsTowardProgression", "countsTowardStreak", "plannedWorkoutRecorded", "validationReason",
  "cadenceAnalysisSeries", "coolDownXpAwarded", "coolDownXpAwardedAt", "coolDownProgressionEventId",
] as const;

export function parsePublishFeedPayload(raw: unknown, ownerUid: string): FeedResult<FeedPublishPayload> {
  if (!isRecord(raw) || !hasOnlyKeys(raw, ["activityId", "stagingPath"])) return payloadError("unknown_key");
  const activityId = raw["activityId"];
  const stagingPath = raw["stagingPath"];
  if (!isIdentifier(activityId) || !isIdentifier(ownerUid) || typeof stagingPath !== "string") return payloadError("invalid_field");
  if (!isOwnedStagingPath(stagingPath, ownerUid, activityId)) return payloadError("unsafe_path");
  return { ok: true, value: { activityId, stagingPath } };
}

export function deterministicFeedIds(activityId: string, reporterUid: string): { readonly postId: string; readonly reportId: string } {
  return { postId: activityId, reportId: `report_${Buffer.byteLength(reporterUid)}_${encodeDocumentSegment(reporterUid)}_${Buffer.byteLength(activityId)}_${encodeDocumentSegment(activityId)}` };
}

export function parseValidatedOwnedActivity(raw: unknown, ownerUid: string, activityId: string): FeedResult<ValidatedOwnedActivity> {
  if (!isRecord(raw) || !hasNoUnknownKeys(raw, completeRunActivityFields)) return { ok: false, error: { kind: "invalid_activity", code: "validation" } };
  if (raw["ownerUid"] !== ownerUid || !isIdentifier(activityId)) return { ok: false, error: { kind: "invalid_activity", code: "owner" } };
  if (raw["status"] !== "validated" || raw["validationStatus"] !== "validated") return { ok: false, error: { kind: "invalid_activity", code: "validation" } };
  if (!isIsoTimestamp(raw["endedAt"]) || !isFinitePositive(raw["distanceMeters"]) || !isFinitePositive(raw["durationSeconds"]) || !isFinitePositive(raw["averagePaceSecondsPerKm"])) {
    return { ok: false, error: { kind: "invalid_activity", code: "validation" } };
  }
  return { ok: true, value: { activityId, ownerUid, status: "validated", validationStatus: "validated", completedAt: raw["endedAt"], distanceMeters: raw["distanceMeters"], durationSeconds: raw["durationSeconds"], averagePaceSecondsPerKm: raw["averagePaceSecondsPerKm"] } };
}

export function transitionFeedPostStatus(from: FeedPostStatus, to: FeedPostStatus): FeedResult<FeedPostStatus> {
  if (feedPostTransitions[from].includes(to)) {
    return { ok: true, value: to };
  }
  return { ok: false, error: { kind: "invalid_transition", from, to } };
}

const feedPostTransitions: { readonly [Status in FeedPostStatus]: readonly FeedPostStatus[] } = {
  published: ["deleting"],
  deleting: ["deleted"],
  deleted: [],
};

export function buildFeedPost(input: FeedPostBuildInput): FeedResult<FeedPost> {
  const { activity, profile, thumbnail, now } = input;
  if (activity.ownerUid !== profile.uid) return { ok: false, error: { kind: "invalid_activity", code: "owner" } };
  if (activity.status !== "validated" || activity.validationStatus !== "validated") return { ok: false, error: { kind: "invalid_activity", code: "validation" } };
  if (!isDisplay(profile.displayName) || !isDisplay(profile.avatarInitials) || !isOptionalDisplay(profile.levelLabel)) return { ok: false, error: { kind: "invalid_profile", code: "display" } };
  if (!isFinalThumbnail(thumbnail, activity.ownerUid, activity.activityId)) return { ok: false, error: { kind: "invalid_thumbnail", code: "path" } };
  if (!isIdentifier(thumbnail.objectGeneration)) return { ok: false, error: { kind: "invalid_thumbnail", code: "generation" } };
  if (!/^[a-f0-9]{64}$/.test(thumbnail.sha256)) return { ok: false, error: { kind: "invalid_thumbnail", code: "sha256" } };
  return {
    ok: true,
    value: {
      authorUid: activity.ownerUid, activityId: activity.activityId, authorDisplayName: profile.displayName,
      authorAvatarInitials: profile.avatarInitials, authorLevelLabel: profile.levelLabel, completedAt: activity.completedAt, distanceMeters: activity.distanceMeters,
      durationSeconds: activity.durationSeconds, averagePaceSecondsPerKm: activity.averagePaceSecondsPerKm,
      thumbnailStoragePath: thumbnail.storagePath, thumbnailObjectGeneration: thumbnail.objectGeneration,
      thumbnailSha256: thumbnail.sha256, likeCount: 0, commentCount: 0, status: "published", schemaVersion: 1,
      createdAt: now, updatedAt: now,
    },
  };
}

export function isOwnedStagingPath(path: string, ownerUid: string, activityId: string): boolean {
  const parts = path.split("/");
  return parts.length === 4 && parts[0] === "feed-thumbnail-staging" && parts[1] === ownerUid && parts[2] === activityId && isUploadName(parts[3]);
}

function isFinalThumbnail(thumbnail: FinalThumbnail, ownerUid: string, activityId: string): boolean {
  return thumbnail.storagePath === `feed-thumbnails/${ownerUid}/${activityId}/route-preview.png`;
}
function hasOnlyKeys(value: Readonly<Record<string, unknown>>, keys: readonly string[]): boolean {
  return Object.keys(value).length === keys.length && Object.keys(value).every((key) => keys.includes(key));
}
function hasNoUnknownKeys(value: Readonly<Record<string, unknown>>, keys: readonly string[]): boolean {
  return Object.keys(value).every((key) => keys.includes(key));
}
function isRecord(value: unknown): value is Readonly<Record<string, unknown>> { return typeof value === "object" && value !== null && !Array.isArray(value); }
function isIdentifier(value: unknown): value is string { return typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value); }
function isUploadName(value: string | undefined): boolean { return value !== undefined && /^[A-Za-z0-9_-]{1,128}\.png$/.test(value); }
function isDisplay(value: string): boolean { return value.trim().length > 0 && value.length <= 80; }
function isOptionalDisplay(value: string): boolean { return value.length <= 80; }
function isFinitePositive(value: unknown): value is number { return typeof value === "number" && Number.isFinite(value) && value > 0; }
function isIsoTimestamp(value: unknown): value is string { return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) && !Number.isNaN(Date.parse(value)); }
function payloadError(code: "unknown_key" | "invalid_field" | "unsafe_path"): FeedResult<never> { return { ok: false, error: { kind: "invalid_payload", code } }; }
function encodeDocumentSegment(value: string): string { return Buffer.from(value, "utf8").toString("base64url"); }
