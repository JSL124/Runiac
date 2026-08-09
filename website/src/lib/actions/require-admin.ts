// Plain (non "use server") module holding the admin-console auth check
// shared by src/lib/actions/admin.ts. Every server action there re-verifies
// the caller by calling requireAdmin() before touching Firestore — never
// trust the client. This lives outside admin.ts (and outside any "use
// server" file) so it can be imported by non-action code later — e.g. a
// route handler streaming a document download — without that "use server"
// directive forcing every export of the importing file to be an async
// server action.
//
// Behavior is unchanged from the requireAdmin() previously defined inline in
// src/lib/actions/admin.ts.

import { getCurrentUser } from "@/lib/auth";

export type ActingAdmin = { uid: string; email: string };

export type RequireAdminResult =
  | { ok: true; admin: ActingAdmin }
  | { ok: false; error: string };

// Verifies the caller and normalizes the actor identity used in audit logs.
export async function requireAdmin(): Promise<RequireAdminResult> {
  const current = await getCurrentUser();

  if (!current.isAdmin || !current.user) {
    return {
      ok: false,
      error: "You are not authorized to perform this action.",
    };
  }

  return {
    ok: true,
    admin: {
      uid: current.user.uid ?? "unknown-admin",
      email: current.user.email ?? "unknown-admin",
    },
  };
}
