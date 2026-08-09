import { createHash } from "node:crypto";

/**
 * Pure sanitisation and classification helpers for reportAppError. No
 * Firebase imports here by design: these functions unit-test without an
 * emulator, and the callable is the only place they meet Firestore.
 */

export type Severity = "low" | "medium" | "high" | "critical";

const REDACTED = "[redacted]";
const APP_FRAME_MARKER = "package:runiac_app/";
// Node stack frames from our own Cloud Functions bundle, e.g.
// "at completeRunForCallable (/workspace/functions/lib/src/run/completeRun.js:56:10)"
// (compiled output, running under the "functions/" directory the emulator
// and deploy both use) or the equivalent path under a source-mapped /src/
// tree. Deliberately excludes bare "node:internal/..." frames (no
// "/functions/" segment) and anything under node_modules (checked
// separately below).
const FUNCTIONS_FRAME_PATTERN = /\/functions\/(lib|src)\//;
const NODE_MODULES_MARKER = "node_modules";

const EMAIL_PATTERN = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
// A latitude/longitude pair, e.g. "1.3521, 103.8198" or "(1.35210,103.81980)".
// DIGIT_RUN_PATTERN below only fires on runs of 5+ digits, and a decimal point
// breaks a coordinate into runs of 1-4, so real Singapore coordinates survived
// every other pattern here and were persisted verbatim into an error report
// flagged `sanitized: true`.
//
// The 3+ decimal places (~100m precision) is a heuristic, and it is
// deliberately biased towards over-redaction: a non-location pair such as
// "5.000, 6.000" is also redacted. Losing a number out of a debugging string is
// cheap; leaking a runner's position is not.
const COORDINATE_PAIR_PATTERN = /[-+]?\d{1,3}\.\d{3,}\s*[,;]\s*[-+]?\d{1,3}\.\d{3,}/g;
// The labelled form, e.g. "latitude=1.3521 longitude=103.8198" or "lat: 1.3521".
// A single labelled value carries a position just as much as a pair does, and
// no pair pattern can catch one that arrives on its own.
const LABELLED_COORDINATE_PATTERN =
  /\b(?:lat|lat(?:itude)?|lon|lng|long(?:itude)?)\b\s*[=:]\s*[-+]?\d{1,3}\.\d{3,}/gi;
// A "?" followed by non-whitespace covers URL query strings (?key=value&...).
const QUERY_STRING_PATTERN = /\?\S+/g;
// Coordinates, ids, and numeric tokens: any run of 5+ digits.
const DIGIT_RUN_PATTERN = /\d{5,}/g;
// Hex-only runs of 32+ chars (md5/sha-style hashes). Real Dart identifiers
// always contain letters outside a-f, so this never matches class/method
// names such as RunSummaryController.
const HEX_RUN_PATTERN = /\b[0-9a-fA-F]{32,}\b/g;
// Long base64/token-ish runs (secrets, ids) that survive the patterns above.
// Deliberately excludes "/" so a "package:runiac_app/some/long/path.dart"
// stack frame is not mistaken for one long encoded token. Requires the run
// to contain both a digit and a letter and be 32+ chars: ordinary
// snake_case/PascalCase identifiers (RunSummaryController,
// run_summary_controller) are all-letters-and-underscores and well under
// that length, so they survive; genuine tokens do not.
const LONG_TOKEN_PATTERN = /(?=[A-Za-z0-9+_-]*[0-9])(?=[A-Za-z0-9+_-]*[A-Za-z])[A-Za-z0-9+_-]{32,}=*/g;

const SANITIZED_MESSAGE_MAX_LENGTH = 200;
const MAX_FRAMES = 8;
const MAX_FRAME_LENGTH = 200;

/**
 * Redacts emails, URL query strings, long digit runs, and long token-like
 * runs, then caps the result to 200 characters. Applied to the free-text
 * `message` field before it is ever persisted or logged.
 */
export function sanitizeMessage(raw: string): string {
  const collapsed = raw.replace(/\s+/g, " ").trim();
  const redacted = redactSensitiveSubstrings(collapsed);
  return redacted.slice(0, SANITIZED_MESSAGE_MAX_LENGTH);
}

/**
 * Keeps only frames that originate from the app itself (dropping SDK/plugin
 * frames) — either a mobile `package:runiac_app/` frame or a Node frame from
 * our own Cloud Functions bundle — caps the frame count to 8, redacts each
 * retained frame the same way `sanitizeMessage` does, and caps each frame to
 * 200 characters.
 */
export function sanitizeFrames(frames: readonly string[]): string[] {
  return frames
    .filter(isRetainedFrame)
    .slice(0, MAX_FRAMES)
    .map((frame) => redactSensitiveSubstrings(frame).slice(0, MAX_FRAME_LENGTH));
}

function isRetainedFrame(frame: string): boolean {
  if (frame.includes(NODE_MODULES_MARKER)) {
    return false;
  }
  return frame.includes(APP_FRAME_MARKER) || FUNCTIONS_FRAME_PATTERN.test(frame);
}

/**
 * Deterministic group id: first 16 hex characters of
 * sha256(errorType | topAppFrame | screen). Never influenced by uid, so
 * identical errors from different users collapse into one group.
 */
export function buildFingerprint(input: {
  readonly errorType: string;
  readonly topFrame: string;
  readonly screen: string;
}): string {
  const digest = createHash("sha256")
    .update(`${input.errorType}|${input.topFrame}|${input.screen}`)
    .digest("hex");
  return digest.slice(0, 16);
}

/**
 * Severity ladder, recomputed on every ingest so a group escalates as it
 * spreads. No client input feeds this — only server-derived counters.
 */
export function deriveSeverity(input: {
  readonly fatal: boolean;
  readonly occurrences: number;
  readonly affectedUserCount: number;
}): Severity {
  if (input.fatal && input.affectedUserCount >= 10) {
    return "critical";
  }
  if (input.fatal) {
    return "high";
  }
  if (input.occurrences >= 50) {
    return "medium";
  }
  return "low";
}

function redactSensitiveSubstrings(value: string): string {
  return value
    .replace(EMAIL_PATTERN, REDACTED)
    // Before the digit/token runs, which would otherwise chew a coordinate
    // into pieces these patterns can no longer recognise. The labelled form
    // goes first so "lat=1.3521, lon=103.8198" is redacted as two labelled
    // values rather than being half-consumed by the pair pattern.
    .replace(LABELLED_COORDINATE_PATTERN, REDACTED)
    .replace(COORDINATE_PAIR_PATTERN, REDACTED)
    .replace(QUERY_STRING_PATTERN, REDACTED)
    .replace(HEX_RUN_PATTERN, REDACTED)
    .replace(LONG_TOKEN_PATTERN, REDACTED)
    .replace(DIGIT_RUN_PATTERN, REDACTED);
}
