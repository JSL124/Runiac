// Small helpers shared across the newsletter module's Firebase-backed ports.

// Firestore's Admin SDK surfaces a rejected `.create()` against an existing
// document as a GoogleError carrying the gRPC ALREADY_EXISTS status
// (numeric code 6). The string form is checked too, defensively, matching
// the identical helper already duplicated in staleReportSweep.ts and
// errorGroupNotifications.ts.
export function isAlreadyExistsError(error: unknown): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const code = (error as { code?: unknown }).code;
  return code === 6 || code === "already-exists";
}

// Accepts a Firestore Timestamp (duck-typed via toMillis(), so this also
// works against the emulator's own Timestamp construction path), a raw
// millisecond number, or a Date, and returns milliseconds since epoch or
// null when the value is absent/unrecognised.
export function toMillis(value: unknown): number | null {
  if (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { toMillis?: unknown }).toMillis === "function"
  ) {
    return (value as { toMillis: () => number }).toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}
