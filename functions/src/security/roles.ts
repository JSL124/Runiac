// Canonical Platform Administrator role check.
//
// The admin console writes the canonical value `"platformAdmin"` to
// `users/{uid}.userRole`. Some already-stored documents (and legacy code
// paths) still use the older display-style string `"Platform Administrator"`.
// Every server-side check for the Platform Administrator role must go
// through this predicate so the two spellings stay interchangeable in one
// place instead of drifting apart across call sites.
const CANONICAL_PLATFORM_ADMIN_ROLE = "platformAdmin";
const LEGACY_PLATFORM_ADMIN_ROLE = "Platform Administrator";

export function isPlatformAdminRole(data: Readonly<Record<string, unknown>> | undefined): boolean {
  const userRole = data?.["userRole"];
  return userRole === CANONICAL_PLATFORM_ADMIN_ROLE || userRole === LEGACY_PLATFORM_ADMIN_ROLE;
}
