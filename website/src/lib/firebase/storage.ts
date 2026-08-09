// Cloud Storage for Firebase — Admin SDK bucket accessor and byte-level
// helpers for project documents (the PDFs referenced by the
// `projectDocuments` Firestore collection; see ./firestore.ts and
// @/lib/project-documents). The website has not used Firebase Storage before
// this module.
//
// Mirrors the lazy, never-throws-at-import style of ./admin and ./config:
// the bucket handle is resolved lazily from getAdminApp() (the shared
// "runiac-admin" named app), never from a fresh initializeApp() call.
//
// Deliberately does not mint signed URLs anywhere in this module — file
// bytes are streamed through this website's own route handlers (added in a
// later task), never served directly from a Cloud Storage URL.

import { getStorage } from "firebase-admin/storage";

import { getAdminApp } from "./admin";
import { getFirebaseStorageBucket } from "./config";
import { isAvatarObjectPath } from "@/lib/avatarPaths";

// The Cloud Storage bucket used for every project-document read/write below.
export function getAdminBucket() {
  return getStorage(getAdminApp()).bucket(getFirebaseStorageBucket());
}

function toErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "Unknown storage error.";
}

// Uploads (or overwrites) a PDF at `path`. Callers pass the storagePath that
// will also be stored on the Firestore projectDocuments record.
export async function uploadProjectDocumentFile(
  path: string,
  buffer: Buffer,
): Promise<{ ok: true } | { ok: false; error: string }> {
  try {
    await getAdminBucket()
      .file(path)
      .save(buffer, { contentType: "application/pdf" });
    return { ok: true };
  } catch (error) {
    return { ok: false, error: toErrorMessage(error) };
  }
}

// Downloads the full object at `path` into memory. Returns a typed error
// instead of throwing so a route handler can surface a clean 404/500 rather
// than an unhandled rejection.
export async function downloadProjectDocumentFile(
  path: string,
): Promise<{ buffer: Buffer | null; error: string | null }> {
  try {
    const [buffer] = await getAdminBucket().file(path).download();
    return { buffer, error: null };
  } catch (error) {
    return { buffer: null, error: toErrorMessage(error) };
  }
}

// Deletes the object at `path`. Tolerates the object already being missing
// (ignoreNotFound) so a Firestore-record delete that races a partially
// completed upload, or a retry of a prior delete, never fails the caller.
export async function deleteProjectDocumentFile(
  path: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
  try {
    await getAdminBucket().file(path).delete({ ignoreNotFound: true });
    return { ok: true };
  } catch (error) {
    return { ok: false, error: toErrorMessage(error) };
  }
}

// --- avatar takedown ---------------------------------------------------------
//
// The avatar object is served through a Firebase Storage download token,
// which bypasses Storage security rules entirely, so deleting the object is
// the ONLY real enforcement an admin takedown has — clearing a Firestore
// field alone leaves the photo fetchable by anyone still holding the URL.
// The Admin SDK used throughout this module also bypasses Storage rules and
// the same bucket holds feed-thumbnail-staging/, feed-thumbnails/,
// share-cards/, and project-documents/ objects, so a corrupted or
// attacker-influenced stored path handed to a delete could destroy an
// unrelated object (e.g. a feed thumbnail pinned by another user's post).
//
// This is therefore a DEDICATED delete path, never deleteProjectDocumentFile()
// above: every path is re-validated against isAvatarObjectPath() (the single
// source of truth for a legitimate avatar object path — see
// @/lib/avatarPaths) at the point of deletion, and a mismatch is reported
// back as a distinct outcome rather than silently dropped, so the admin
// console can audit exactly what it skipped and why.
export type DeleteAvatarObjectResult =
  | { ok: true; existed: boolean }
  | { ok: false; reason: "invalid-path" }
  | { ok: false; reason: "error"; error: string };

export async function deleteAvatarObject(
  path: string,
): Promise<DeleteAvatarObjectResult> {
  if (!isAvatarObjectPath(path)) {
    return { ok: false, reason: "invalid-path" };
  }

  try {
    const file = getAdminBucket().file(path);
    const [existed] = await file.exists();
    await file.delete({ ignoreNotFound: true });
    return { ok: true, existed };
  } catch (error) {
    return { ok: false, reason: "error", error: toErrorMessage(error) };
  }
}
