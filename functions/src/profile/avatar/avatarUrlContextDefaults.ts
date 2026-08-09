// The safe default AvatarUrlContext for read-fan-in surfaces (runner public
// profile, friend levels, Feed author levels, challenge roster) that have not
// been threaded the real context from profile/avatar/context.ts — currently
// only test callers that omit the parameter.
//
// Deliberately NOT exported from avatarPaths.ts: that file is mirrored
// verbatim into website/src/lib/avatarPaths.ts and
// tests/cross-system/avatar-path-contract-drift.mjs fails the build the
// moment the two files' exports diverge. This default is a backend-only
// convenience with no admin-console equivalent, so it lives in its own
// module instead of forcing an unrelated mirror update.
import type { AvatarUrlContext } from "./avatarPaths.js";

// A context that can never match a real avatar download URL: every bucket
// this backend ever serves has a non-empty name, so
// avatarPaths.ts's "/v0/b/{bucket}/o/..." check can never succeed against an
// empty one. Used as the default AvatarUrlContext on read-fan-in surfaces so
// a caller that has not threaded the real context through still fails closed
// to "" (the same as "no avatar set") instead of throwing or resolving a
// wrong value.
export const NULL_AVATAR_URL_CONTEXT: AvatarUrlContext = { bucket: "" };
