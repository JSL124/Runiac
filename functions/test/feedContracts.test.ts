import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  buildFeedPost,
  deterministicFeedIds,
  parseValidatedOwnedActivity,
  parsePublishFeedPayload,
  transitionFeedPostStatus,
} from "../src/feed/contracts.js";
import { validateFeedThumbnailPng } from "../src/feed/png.js";
import { evaluateFeedRelationship } from "../src/feed/relationship.js";

describe("Feed contracts", () => {
  it("parses only the exact publish payload and safe owned staging paths", () => {
    const parsed = parsePublishFeedPayload({
      activityId: "activity-a",
      stagingPath: "feed-thumbnail-staging/author-a/activity-a/upload-a.png",
    }, "author-a");
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.value.activityId, "activity-a");

    for (const value of [
      { activityId: "activity-a", stagingPath: "feed-thumbnail-staging/author-a/activity-a/upload-a.png", extra: true },
      { activityId: " ", stagingPath: "feed-thumbnail-staging/author-a/activity-a/upload-a.png" },
      { activityId: 1, stagingPath: "feed-thumbnail-staging/author-a/activity-a/upload-a.png" },
      { activityId: "activity-a", stagingPath: "feed-thumbnail-staging/author-a/../activity-a/upload-a.png" },
      { activityId: "activity-a", stagingPath: "feed-thumbnail-staging/other/activity-a/upload-a.png" },
    ]) {
      const rejected = parsePublishFeedPayload(value, "author-a");
      assert.deepEqual(rejected.ok, false);
    }
  });

  it("builds a minimal immutable post with deterministic IDs and no sensitive fields", () => {
    const ids = deterministicFeedIds("activity-a", "viewer-a");
    assert.deepEqual(ids, { postId: "activity-a", reportId: "report_8_dmlld2VyLWE_10_YWN0aXZpdHktYQ" });
    assert.notEqual(deterministicFeedIds("c", "a_b").reportId, deterministicFeedIds("b_c", "a").reportId);
    assert.equal(deterministicFeedIds("activity/with/slash", "viewer/with/slash").reportId.includes("/"), false);

    const built = buildFeedPost({
      activity: {
        activityId: "activity-a",
        ownerUid: "author-a",
        status: "validated",
        validationStatus: "validated",
        completedAt: "2026-07-11T00:00:00.000Z",
        distanceMeters: 3200,
        durationSeconds: 1500,
        averagePaceSecondsPerKm: 469,
      },
      profile: { uid: "author-a", displayName: "Ava", avatarInitials: "AV", levelLabel: "Level 6" },
      thumbnail: {
        storagePath: "feed-thumbnails/author-a/activity-a/route-preview.png",
        objectGeneration: "1",
        sha256: "a".repeat(64),
      },
      now: "2026-07-11T00:00:00.000Z",
    });
    assert.equal(built.ok, true);
    if (!built.ok) return;
    assert.deepEqual(Object.keys(built.value).sort(), feedPostKeys());
    assert.equal(built.value.activityId, "activity-a");
    assert.equal(built.value.authorLevelLabel, "Level 6");
    assert.equal("coordinates" in built.value, false);
    assert.equal("xp" in built.value, false);
    assert.equal("leaderboardScore" in built.value, false);

    const rejected = buildFeedPost({
      activity: {
        activityId: "activity-a",
        ownerUid: "other",
        status: "validated",
        validationStatus: "validated",
        completedAt: "2026-07-11T00:00:00.000Z",
        distanceMeters: 3200,
        durationSeconds: 1500,
        averagePaceSecondsPerKm: 469,
      },
      profile: { uid: "author-a", displayName: "Ava", avatarInitials: "AV", levelLabel: "Level 6" },
      thumbnail: {
        storagePath: "feed-thumbnails/author-a/activity-a/route-preview.png",
        objectGeneration: "1",
        sha256: "a".repeat(64),
      },
      now: "2026-07-11T00:00:00.000Z",
    });
    assert.deepEqual(rejected.ok, false);
  });

  it("uses explicit lifecycle transitions", () => {
    assert.equal(transitionFeedPostStatus("published", "deleting").ok, true);
    assert.equal(transitionFeedPostStatus("published", "deleted").ok, false);
    assert.equal(transitionFeedPostStatus("deleting", "deleted").ok, true);
  });

  it("projects the trusted completeRun activity shape from endedAt without exposing non-feed fields", () => {
    const parsed = parseValidatedOwnedActivity(completeRunActivity(), "author-a", "activity-a");
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.deepEqual(parsed.value, {
      activityId: "activity-a",
      ownerUid: "author-a",
      status: "validated",
      validationStatus: "validated",
      completedAt: "2026-07-11T00:00:00.000Z",
      distanceMeters: 3200,
      durationSeconds: 1500,
      averagePaceSecondsPerKm: 469,
    });
    assert.equal("routePrivacy" in parsed.value, false);
    assert.equal("cadenceAnalysisSeries" in parsed.value, false);
    assert.equal("validatedActivityContributionState" in parsed.value, false);
  });

  // Regression (daee0021): completeRun stamps countsTowardStreak and
  // plannedWorkoutRecorded, and completeCoolDown stamps the coolDownXpAwarded*
  // trio onto every real activity document, but the publish allowlist rejected
  // them as unknown keys — so no post-progression run could ever be shared.
  it("accepts an activity carrying streak and cool-down progression fields", () => {
    const parsed = parseValidatedOwnedActivity(
      {
        ...completeRunActivity(),
        countsTowardStreak: true,
        plannedWorkoutRecorded: false,
        coolDownXpAwarded: true,
        coolDownXpAwardedAt: "2026-07-11T00:10:00.000Z",
        coolDownProgressionEventId: "cooldown_author-a_client-run-a",
      },
      "author-a",
      "activity-a",
    );
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.value.activityId, "activity-a");
    assert.equal(parsed.value.completedAt, "2026-07-11T00:00:00.000Z");
    // The progression fields are accepted but never projected into the feed.
    assert.equal("countsTowardStreak" in parsed.value, false);
    assert.equal("plannedWorkoutRecorded" in parsed.value, false);
    assert.equal("coolDownXpAwarded" in parsed.value, false);
    assert.equal("coolDownXpAwardedAt" in parsed.value, false);
    assert.equal("coolDownProgressionEventId" in parsed.value, false);
  });

  it("rejects foreign, unvalidated, and malformed activity projections", () => {
    const valid = completeRunActivity();
    assert.equal(parseValidatedOwnedActivity(valid, "author-a", "activity-a").ok, true);
    for (const invalid of [
      { ...valid, ownerUid: "other" },
      { ...valid, validationStatus: "pending" },
      { ...valid, endedAt: 1 },
      { ...valid, distanceMeters: 0 },
      { ...valid, durationSeconds: Number.NaN },
      { ...valid, averagePaceSecondsPerKm: -1 },
      { ...valid, coordinates: [1, 2] },
      { ...valid, xp: 30 },
    ]) assert.equal(parseValidatedOwnedActivity(invalid, "author-a", "activity-a").ok, false);
    assert.deepEqual(evaluateFeedRelationship({ viewerUid: "viewer", authorUid: "author", viewerHasAuthorFriend: true, authorHasViewerFriend: false, viewerBlockedAuthor: false, authorBlockedViewer: false }), { kind: "denied", reason: "missing_reciprocal_friendship" });
  });

  it("accepts only safe bounded PNGs and rejects unsafe chunk fields, metadata, ordering, and terminal states", () => {
    for (const width of [88, 176, 264]) assert.equal(validateFeedThumbnailPng(png({ width, height: width })).ok, true);
    for (const [width, height] of [[344, 184], [688, 368], [1032, 552]] as const) {
      assert.equal(validateFeedThumbnailPng(png({ width, height })).ok, true);
    }
    assert.equal(validateFeedThumbnailPng(png({
      width: 1032,
      height: 552,
      ihdrFields: [16, 6, 0, 0, 0],
      ancillary: [chunk("sBIT", [10, 10, 10, 10])],
    })).ok, true);
    for (const ancillary of canonicalAncillaryChunks()) assert.equal(validateFeedThumbnailPng(png({ width: 88, height: 88, ancillary: [ancillary] })).ok, true);
    for (const bytes of [
      png({ width: 265, height: 265 }),
      png({ width: 264, height: 263 }),
      png({ width: 89, height: 89 }),
      png({ width: 264, height: 264, ihdrFields: [16, 6, 0, 0, 0] }),
      png({ width: 1032, height: 552, ihdrFields: [16, 6, 0, 0, 0] }),
      png({ width: 1032, height: 552, ihdrFields: [16, 6, 0, 0, 0], ancillary: [chunk("sBIT", [8, 8, 8, 8])] }),
      png({ width: 264, height: 264, ihdrFields: [8, 2, 0, 0, 0] }),
      ...["eXIf", "iTXt", "zTXt", "tIME", "iCCP", "pHYs", "tEXt"].map((type) => png({ width: 264, height: 264, extraChunk: chunk(type, []) })),
      png({ width: 264, height: 264, extraChunk: chunk("ABCD", []) }),
      png({ width: 264, height: 264, ancillary: [chunk("sRGB", [])] }),
      png({ width: 264, height: 264, ancillary: [chunk("cHRM", Array<number>(32).fill(0))] }),
      png({ width: 264, height: 264, ancillary: [chunk("cHRM", Array<number>(28).fill(0))] }),
      png({ width: 264, height: 264, ancillary: [chunk("gAMA", uint32(1))] }),
      png({ width: 264, height: 264, ancillary: [chunk("gAMA", [0, 0, 0])] }),
      png({ width: 264, height: 264, ancillary: [chunk("sRGB", [3])] }),
      png({ width: 264, height: 264, ancillary: [chunk("sRGB", [0, 0])] }),
      png({ width: 264, height: 264, ancillary: [chunk("sBIT", [8, 8, 8, 7])] }),
      png({ width: 264, height: 264, ancillary: [chunk("sBIT", [8, 8, 8])] }),
      png({ width: 264, height: 264, ancillary: [chunk("sRGB", [0]), chunk("sRGB", [0])] }),
      png({ width: 264, height: 264, ancillary: [chunk("sBIT", [8, 8, 8, 8]), chunk("sBIT", [8, 8, 8, 8])] }),
    ]) {
      assert.equal(validateFeedThumbnailPng(bytes).ok, false);
    }
    assert.equal(validateFeedThumbnailPng(new Uint8Array(1_048_577)).ok, false);
    assert.equal(validateFeedThumbnailPng(png({ width: 264, height: 264, omitIdat: true })).ok, false);
    assert.deepEqual(validateFeedThumbnailPng(png({ width: 264, height: 264, emptyIdat: true })), { ok: false, error: "empty_idat" });
    assert.deepEqual(validateFeedThumbnailPng(png({ width: 264, height: 264, emptyIdat: true, postIdatChunks: [chunk("IDAT", [0])] })), { ok: false, error: "empty_idat" });
    assert.equal(validateFeedThumbnailPng(png({ width: 264, height: 264, idatBeforeIhdr: true })).ok, false);
    assert.equal(validateFeedThumbnailPng(png({ width: 264, height: 264, nonzeroIend: true })).ok, false);
    assert.equal(validateFeedThumbnailPng(png({ width: 264, height: 264, duplicateIhdr: true })).ok, false);
    assert.equal(validateFeedThumbnailPng(png({ width: 264, height: 264, postIdatChunks: [chunk("gAMA", [0, 1, 134, 160]), chunk("IDAT", [])] })).ok, false);
    assert.equal(validateFeedThumbnailPng(png({ width: 264, height: 264, trailingChunk: chunk("IEND", []) })).ok, false);
  });

  it("accepts the canonical Flutter ancillary sequence before image data", () => {
    const actualFlutterSequence = [
      chunk("sBIT", [8, 8, 8, 8]),
      chunk("sRGB", [0]),
      chunk("gAMA", uint32(45_455)),
      chunk("cHRM", canonicalChromaticities()),
    ];
    assert.equal(validateFeedThumbnailPng(png({ width: 264, height: 264, ancillary: actualFlutterSequence })).ok, true);
  });

  it("rejects empty IDAT chunks in every split position and accepts consecutive nonempty IDAT chunks", () => {
    assert.deepEqual(validateFeedThumbnailPng(png({ width: 264, height: 264, emptyIdat: true, postIdatChunks: [chunk("IDAT", [1])] })), { ok: false, error: "empty_idat" });
    assert.deepEqual(validateFeedThumbnailPng(png({ width: 264, height: 264, postIdatChunks: [chunk("IDAT", []), chunk("IDAT", [2])] })), { ok: false, error: "empty_idat" });
    assert.deepEqual(validateFeedThumbnailPng(png({ width: 264, height: 264, postIdatChunks: [chunk("IDAT", [])] })), { ok: false, error: "empty_idat" });
    assert.deepEqual(validateFeedThumbnailPng(png({ width: 264, height: 264, postIdatChunks: [chunk("IDAT", [1]), chunk("IDAT", [2])] })), { ok: true, width: 264, height: 264 });
  });

  it("rejects structurally plausible PNG bytes when a chunk checksum is corrupt", () => {
    const structurallyPlausibleButUnchecked = png({ width: 88, height: 88, corruptCrc: true });
    assert.equal(validateFeedThumbnailPng(structurallyPlausibleButUnchecked).ok, false);
  });
});

function feedPostKeys(): string[] {
  return [
    "activityId", "authorAvatarInitials", "authorDisplayName", "authorLevelLabel", "authorUid", "averagePaceSecondsPerKm",
    "commentCount", "completedAt", "createdAt", "distanceMeters", "durationSeconds", "likeCount",
    "schemaVersion", "status", "thumbnailObjectGeneration", "thumbnailSha256", "thumbnailStoragePath", "updatedAt",
  ].sort();
}

function completeRunActivity(): Record<string, unknown> {
  return {
    ownerUid: "author-a",
    status: "validated",
    source: "mobile",
    activityType: "run",
    startedAt: "2026-07-10T23:35:00.000Z",
    endedAt: "2026-07-11T00:00:00.000Z",
    durationSeconds: 1500,
    activeDurationSeconds: 1500,
    elapsedWallSeconds: 1500,
    pausedDurationSeconds: 0,
    distanceMeters: 3200,
    averagePaceSecondsPerKm: 469,
    routePrivacy: "private",
    clientRunSessionId: "client-run-a",
    payloadFingerprint: "a".repeat(64),
    createdAt: "2026-07-11T00:00:00.000Z",
    updatedAt: "2026-07-11T00:00:00.000Z",
    processedAt: "2026-07-11T00:00:00.000Z",
    validationStatus: "validated",
    validatedActivityContributionState: "awarded",
    countsTowardProgression: true,
    validationReason: "run_completion_xp_awarded",
    cadenceAnalysisSeries: {
      source: "phoneSensorEstimated",
      confidence: "low",
      samples: [{ elapsedSeconds: 10, cadenceSpm: 160, status: "accepted" }],
    },
  };
}

function png(options: { readonly width: number; readonly height: number; readonly ancillary?: readonly number[][]; readonly extraChunk?: readonly number[]; readonly omitIdat?: boolean; readonly emptyIdat?: boolean; readonly idatBeforeIhdr?: boolean; readonly nonzeroIend?: boolean; readonly duplicateIhdr?: boolean; readonly postIdatChunks?: readonly number[][]; readonly trailingChunk?: readonly number[]; readonly corruptCrc?: boolean; readonly ihdrFields?: readonly number[] }): Uint8Array {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  const ihdr = chunk("IHDR", [...uint32(options.width), ...uint32(options.height), ...(options.ihdrFields ?? [8, 6, 0, 0, 0])]);
  const idat = options.omitIdat === true ? [] : chunk("IDAT", options.emptyIdat === true ? [] : [0]);
  const iend = chunk("IEND", options.nonzeroIend === true ? [0] : []);
  const chunks = options.idatBeforeIhdr === true ? [...idat, ...ihdr] : [...ihdr, ...(options.ancillary ?? []).flat(), ...idat];
  const result = [...signature, ...chunks, ...(options.duplicateIhdr === true ? ihdr : []), ...(options.extraChunk ?? []), ...(options.postIdatChunks ?? []).flat(), ...iend, ...(options.trailingChunk ?? [])];
  if (options.corruptCrc === true) result[result.length - 1] = (result[result.length - 1] ?? 0) ^ 1;
  return Uint8Array.from(result);
}

function uint32(value: number): number[] {
  return [(value >>> 24) & 255, (value >>> 16) & 255, (value >>> 8) & 255, value & 255];
}

function canonicalAncillaryChunks(): readonly number[][] {
  return [
    chunk("sBIT", [8, 8, 8, 8]),
    chunk("sRGB", [0]),
    chunk("gAMA", uint32(45_455)),
    chunk("cHRM", canonicalChromaticities()),
  ];
}

function canonicalChromaticities(): number[] {
  return [31_270, 32_900, 64_000, 33_000, 30_000, 60_000, 15_000, 6_000].flatMap(uint32);
}

function chunk(type: string, data: readonly number[]): number[] {
  const typeBytes = [...type].map((character) => character.charCodeAt(0));
  return [...uint32(data.length), ...typeBytes, ...data, ...uint32(crc32([...typeBytes, ...data]))];
}

function crc32(bytes: readonly number[]): number {
  let crc = 0xffff_ffff;
  for (const value of bytes) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc & 1) === 1 ? (crc >>> 1) ^ 0xedb8_8320 : crc >>> 1;
  }
  return (crc ^ 0xffff_ffff) >>> 0;
}
