import { HttpsError } from "firebase-functions/v2/https";

export function rejectUnsupportedFields(
  value: Readonly<Record<string, unknown>>,
  allowedKeys: ReadonlySet<string>,
  fieldName: string,
): void {
  for (const key of Object.keys(value)) {
    if (!allowedKeys.has(key)) {
      throw new HttpsError(
        "invalid-argument",
        `${fieldName} contains unsupported field: ${key}.`,
      );
    }
  }
}
