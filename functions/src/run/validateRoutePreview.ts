import { HttpsError } from "firebase-functions/v2/https";
import type { RoutePreviewPayload } from "./runCompletionTypes.js";
import { rejectUnsupportedFields } from "./rejectUnsupportedFields.js";

const maxRoutePreviewSegmentCount = 64;
const maxRoutePreviewPointCount = 256;
const routePreviewKeys = new Set(["segments"]);
const routeSegmentKeys = new Set(["points"]);
const routePointKeys = new Set(["latitude", "longitude"]);

export function readOptionalRoutePreview(
  data: Readonly<Record<string, unknown>>,
): RoutePreviewPayload | undefined {
  const value = data["routePreview"];
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    throw invalid("routePreview must be an object when provided.");
  }
  rejectUnsupportedFields(value, routePreviewKeys, "routePreview");

  const rawSegments = value["segments"];
  if (
    !Array.isArray(rawSegments) ||
    rawSegments.length === 0 ||
    rawSegments.length > maxRoutePreviewSegmentCount
  ) {
    throw invalid("routePreview.segments must contain between 1 and 64 segments.");
  }

  const segments: RoutePreviewPayload["segments"][number][] = [];
  let pointCount = 0;
  for (const rawSegment of rawSegments) {
    if (!isRecord(rawSegment)) {
      throw invalid("routePreview.segments entries must be objects.");
    }
    rejectUnsupportedFields(rawSegment, routeSegmentKeys, "routePreview.segments");
    const rawPoints = rawSegment["points"];
    if (!Array.isArray(rawPoints) || rawPoints.length === 0) {
      throw invalid("routePreview.segments.points must be a non-empty array.");
    }
    pointCount += rawPoints.length;
    if (pointCount > maxRoutePreviewPointCount) {
      throw invalid("routePreview must contain between 1 and 256 total points.");
    }
    segments.push({ points: rawPoints.map(readRoutePreviewPoint) });
  }

  return { segments };
}

function readRoutePreviewPoint(value: unknown): RoutePreviewPayload["segments"][number]["points"][number] {
  if (!isRecord(value)) {
    throw invalid("routePreview.segments.points entries must be objects.");
  }
  rejectUnsupportedFields(value, routePointKeys, "routePreview.segments.points");
  const latitude = readCoordinate(value, "latitude", -90, 90);
  const longitude = readCoordinate(value, "longitude", -180, 180);
  return { latitude, longitude };
}

function readCoordinate(
  data: Readonly<Record<string, unknown>>,
  key: "latitude" | "longitude",
  minimum: number,
  maximum: number,
): number {
  const value = data[key];
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw invalid(`routePreview.segments.points.${key} must be a finite number.`);
  }
  if (value < minimum || value > maximum) {
    throw invalid(`routePreview.segments.points.${key} is outside coordinate limits.`);
  }
  // Five decimals (~1.1 m) is the ceiling the client quantizes to
  // (`RunCompletionRequestPayloadSerializer._quantizeCoordinate`). The previous
  // three-decimal ceiling (~111 m) was coarser than the preview's own ~32 m
  // sampling, which reduced every stored route to an axis-aligned staircase.
  if (Number(value.toFixed(5)) !== value) {
    throw invalid(`routePreview.segments.points.${key} must be quantized to 5 decimal places.`);
  }
  return value;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function invalid(message: string): HttpsError {
  return new HttpsError("invalid-argument", message);
}
