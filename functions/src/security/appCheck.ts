/**
 * Production callable endpoints require Firebase App Check. The local
 * Functions emulator has no App Check emulator, so deterministic HTTP surface
 * tests keep enforcement disabled only when Firebase sets FUNCTIONS_EMULATOR.
 */
export function shouldEnforceAppCheck(): boolean {
  return process.env["FUNCTIONS_EMULATOR"] !== "true";
}
