// The single place, across the whole avatar read fan-in (runner public
// profile, friend levels, Feed author levels, challenge roster), that
// constructs the real AvatarUrlContext from firebase-admin/runtime concerns:
// the live Storage bucket name and the storage emulator host environment
// variable. Every callable that needs to resolve a stored avatarUrl into a
// display value must call this helper — never read process.env or call
// getStorage() directly, and never construct this context anywhere else.
// Keeping it to one place is what keeps every read surface agreeing on
// exactly which bucket/emulator-host pair a stored avatarUrl is checked
// against.
import { getStorage } from "firebase-admin/storage";
import type { AvatarUrlContext } from "./avatarPaths.js";

export function avatarUrlContextFromEnvironment(): AvatarUrlContext {
  const bucket = getStorage().bucket().name;
  const emulatorHost = process.env["FIREBASE_STORAGE_EMULATOR_HOST"];
  return emulatorHost !== undefined && emulatorHost.length > 0 ? { bucket, emulatorHost } : { bucket };
}
