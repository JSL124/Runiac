// Single choke point for every avatar Cloud Storage object path and every
// avatar download URL the client is ever allowed to read, or the backend is
// ever allowed to hand to a Storage delete call.
//
// The bucket this module reasons about also holds feed-thumbnail-staging/,
// feed-thumbnails/, share-cards/, and project-documents/ objects (see
// storage.rules). A Cloud Function computes the object path that later gets
// passed straight to a Storage delete, and the website admin console's
// Admin SDK bypasses Storage security rules entirely — so a poisoned or
// buggy path value here could delete an unrelated user's object. Every
// avatar path/URL the backend or the admin console ever trusts MUST be
// produced or validated by this module; nothing downstream is allowed to
// hand-roll a path or parse a URL itself.
//
// website/src/lib/avatarPaths.ts is a hand-mirrored, verbatim copy of this
// file (the website is a separate npm package and must not import from
// functions/). tests/cross-system/avatar-path-contract-drift.mjs fails
// loudly if the two files drift. If you change this file, mirror the same
// change into the website copy in the same change.

// Object path for the durable, published avatar: exactly one path segment
// under avatars/, a fixed 32-character lowercase-hex id, a fixed .png
// extension. No leading slash, no nested directories, nothing else.
export const AVATAR_OBJECT_PATH_PATTERN = /^avatars\/[0-9a-f]{32}\.png$/;

export function isAvatarObjectPath(value: unknown): value is string {
  return typeof value === "string" && AVATAR_OBJECT_PATH_PATTERN.test(value);
}

const AVATAR_ID_PATTERN = /^[0-9a-f]{32}$/;

// Builds the durable object path for a freshly minted avatar. Takes the id
// as a parameter instead of calling randomUUID()/crypto itself, so this
// stays a pure, deterministically testable function — the caller mints the
// id and this module only ever validates and assembles the path.
export function newAvatarObjectPath(randomHex32: string): string {
  if (!AVATAR_ID_PATTERN.test(randomHex32)) {
    throw new Error(
      `newAvatarObjectPath: id must be exactly 32 lowercase hex characters, got: ${JSON.stringify(randomHex32)}`,
    );
  }
  return `avatars/${randomHex32}.png`;
}

// Staging object paths written by the client upload flow, one directory per
// owner, before a Cloud Function moves the bytes to the durable avatars/
// path above. Deliberately does not trust a regex-only match on the full
// path: the owner segment is compared to the caller-supplied ownerUid by
// exact equality after an explicit split, the same defensive shape as
// isOwnedStagingPath in functions/src/feed/contracts.ts.
export const AVATAR_STAGING_PATH_PATTERN = /^avatar-staging\/[^/]+\/[A-Za-z0-9_-]{1,128}\.png$/;

export function isOwnedAvatarStagingPath(path: string, ownerUid: string): boolean {
  const parts = path.split("/");
  return (
    parts.length === 3 &&
    parts[0] === "avatar-staging" &&
    parts[1] === ownerUid &&
    isAvatarUploadName(parts[2])
  );
}

function isAvatarUploadName(value: string | undefined): boolean {
  return value !== undefined && /^[A-Za-z0-9_-]{1,128}\.png$/.test(value);
}

const DOWNLOAD_TOKEN_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

function isDownloadToken(value: unknown): value is string {
  return typeof value === "string" && DOWNLOAD_TOKEN_PATTERN.test(value);
}

export type BuildAvatarDownloadUrlInput = {
  readonly bucket: string;
  readonly objectPath: string;
  readonly token: string;
  readonly emulatorHost?: string;
};

// Builds the Firebase Storage download URL for a durable avatar object.
// Throws (does not silently degrade) if the object path or token is not
// exactly the shape this module mints, because this function is the write
// side: a bad value here means the caller is about to persist a broken or
// dangerous URL.
export function buildAvatarDownloadUrl(input: BuildAvatarDownloadUrlInput): string {
  const { bucket, objectPath, token, emulatorHost } = input;
  if (!isAvatarObjectPath(objectPath)) {
    throw new Error(`buildAvatarDownloadUrl: not an avatar object path: ${JSON.stringify(objectPath)}`);
  }
  if (!isDownloadToken(token)) {
    throw new Error(`buildAvatarDownloadUrl: not a valid download token: ${JSON.stringify(token)}`);
  }
  const encodedPath = encodeURIComponent(objectPath);
  const query = `alt=media&token=${token}`;
  const useEmulator = typeof emulatorHost === "string" && emulatorHost.length > 0;
  const origin = useEmulator ? `http://${emulatorHost}` : "https://firebasestorage.googleapis.com";
  return `${origin}/v0/b/${bucket}/o/${encodedPath}?${query}`;
}

export type ResolveAvatarUrlOptions = {
  readonly bucket: string;
  readonly emulatorHost?: string;
};

// Same shape as ResolveAvatarUrlOptions, under the name every server-side read
// fan-in surface (runner public profile, friend levels, Feed author levels,
// challenge roster) injects this as: the firebase-admin/runtime concerns
// (Storage bucket name, storage emulator host) a `core.ts` is never allowed to
// read for itself. functions/src/profile/avatar/context.ts is the single
// place that constructs the real value from the environment; see
// functions/src/profile/avatar/avatarUrlContextDefaults.ts for the safe
// fallback default other callers use. (That default lives in its own module,
// not here, because this file is mirrored verbatim into
// website/src/lib/avatarPaths.ts and the default is a backend-only
// convenience, not part of the shared path/URL contract.)
export type AvatarUrlContext = ResolveAvatarUrlOptions;

// The read-side sanitiser every server and client read path must call
// before ever rendering a stored avatarUrl. Never throws: garbage,
// attacker-controlled, or partially-written Firestore data all resolve to
// "" (treated the same as "no avatar set") instead of raising.
export function resolveProfileAvatarUrl(data: unknown, options: ResolveAvatarUrlOptions): string {
  const raw = readAvatarUrlField(data);
  if (raw === null) {
    return "";
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0 || trimmed.length > 512) {
    return "";
  }
  const parsed = tryParseUrl(trimmed);
  if (parsed === null) {
    return "";
  }
  if (!isTrustedAvatarDownloadUrl(parsed, options)) {
    return "";
  }
  return trimmed;
}

// Returns the decoded avatar object path a trusted-looking avatar download
// URL points at, or "" if the URL fails any structural check. Lets a caller
// cross-check a stored avatarUrl against a separately stored
// avatarObjectPath before trusting either one.
export function avatarObjectPathFromUrl(url: string, options: ResolveAvatarUrlOptions): string {
  if (typeof url !== "string") {
    return "";
  }
  const trimmed = url.trim();
  if (trimmed.length === 0 || trimmed.length > 512) {
    return "";
  }
  const parsed = tryParseUrl(trimmed);
  if (parsed === null) {
    return "";
  }
  if (!isTrustedAvatarDownloadUrl(parsed, options)) {
    return "";
  }
  return decodeAvatarObjectPath(parsed, options.bucket) ?? "";
}

function readAvatarUrlField(data: unknown): string | null {
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    return null;
  }
  const value = (data as Record<string, unknown>)["avatarUrl"];
  return typeof value === "string" ? value : null;
}

function tryParseUrl(value: string): URL | null {
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

function isTrustedAvatarDownloadUrl(url: URL, options: ResolveAvatarUrlOptions): boolean {
  const { bucket, emulatorHost } = options;

  if (url.username !== "" || url.password !== "") {
    return false;
  }
  if (url.hash !== "") {
    return false;
  }

  const emulatorHostConfigured = typeof emulatorHost === "string" && emulatorHost.length > 0;

  if (url.protocol === "https:") {
    if (url.host !== "firebasestorage.googleapis.com" || url.port !== "") {
      return false;
    }
  } else if (url.protocol === "http:") {
    if (!emulatorHostConfigured || url.host !== emulatorHost) {
      return false;
    }
  } else {
    return false;
  }

  if (decodeAvatarObjectPath(url, bucket) === null) {
    return false;
  }

  const paramNames = [...url.searchParams.keys()];
  if (paramNames.length !== 2 || !paramNames.includes("alt") || !paramNames.includes("token")) {
    return false;
  }
  if (url.searchParams.get("alt") !== "media") {
    return false;
  }
  if (!isDownloadToken(url.searchParams.get("token"))) {
    return false;
  }

  return true;
}

// Full-string, anchored match on "/v0/b/{bucket}/o/{encoded}" — never a
// prefix-only check — followed by a percent-decode of {encoded} and a
// structural re-check against isAvatarObjectPath.
function decodeAvatarObjectPath(url: URL, bucket: string): string | null {
  const pattern = new RegExp(`^/v0/b/${escapeRegExp(bucket)}/o/([^/]+)$`);
  const match = pattern.exec(url.pathname);
  if (match === null) {
    return null;
  }
  const encoded = match[1];
  if (encoded === undefined) {
    return null;
  }
  let decoded: string;
  try {
    decoded = decodeURIComponent(encoded);
  } catch {
    return null;
  }
  return isAvatarObjectPath(decoded) ? decoded : null;
}

function escapeRegExp(literal: string): string {
  return literal.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
