"use server";

// Server actions for the admin console's "Project Documents" PDF library
// (upload + delete). Every action re-verifies the caller with requireAdmin()
// before touching Firestore/Storage — never trust the client, matching the
// pattern in ./admin.
//
// Unlike saveAdminConfig() in ./admin (which no-ops into { ok: true, live:
// false } when Firebase is absent, because a config edit has a local mock
// fallback), an upload has no such fallback: there is nothing to stage
// against, so a missing Firebase environment is a hard failure here.

import { revalidatePath } from "next/cache";

import { requireAdmin } from "@/lib/actions/require-admin";
import { hasFirebaseEnv } from "@/lib/firebase/config";
import {
  createProjectDocument,
  getProjectDocumentById,
  newProjectDocumentId,
  removeProjectDocument,
} from "@/lib/firebase/firestore";
import {
  deleteProjectDocumentFile,
  uploadProjectDocumentFile,
} from "@/lib/firebase/storage";
import {
  validateProjectDocumentInput,
  type ProjectDocumentCategory,
} from "@/lib/project-documents";

export type DocumentActionResult = { ok: true } | { ok: false; error: string };

const FILE_NAME_MAX_LENGTH = 120;

function readField(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value : "";
}

// `formData.get('file')` is `null` when the field is absent and is always
// either a string or a File for a real <input type="file">; treat every
// non-File shape (null, string, or anything else) the same way so this can
// never crash on a malformed submission.
function readFile(formData: FormData): File | null {
  const value = formData.get("file");
  return value instanceof File ? value : null;
}

// Storage object names must not contain path separators or characters Cloud
// Storage/HTTP headers would need to escape; cap the length so a very long
// original file name can't produce an unwieldy object path.
function sanitizeFileName(name: string): string {
  const safe = name.replace(/[^A-Za-z0-9._-]/g, "_").slice(0, FILE_NAME_MAX_LENGTH);
  return safe.length > 0 ? safe : "document.pdf";
}

function revalidateDocumentPaths(): void {
  revalidatePath("/documents");
  revalidatePath("/admin/documents");
}

// Uploads a new PDF and its metadata record. Order matters: the Storage
// object is written before the Firestore record (so storagePath is always
// valid once the record exists), and a metadata-write failure triggers a
// best-effort delete of the just-uploaded blob so a failed save never leaves
// an orphaned file behind.
export async function uploadProjectDocument(
  formData: FormData,
): Promise<DocumentActionResult> {
  const auth = await requireAdmin();
  if (!auth.ok) {
    return auth;
  }

  const title = readField(formData, "title");
  const category = readField(formData, "category");
  const documentDate = readField(formData, "documentDate");
  const file = readFile(formData);

  const validation = validateProjectDocumentInput({
    title,
    category,
    documentDate,
    file: file ? { name: file.name, size: file.size, type: file.type } : null,
  });

  if (validation.errors.length > 0) {
    return { ok: false, error: validation.errors.join(" ") };
  }

  if (!hasFirebaseEnv()) {
    return { ok: false, error: "Firebase is not configured in this environment." };
  }

  // Validated above: validateProjectDocumentInput() requires a non-null file.
  const uploadFile = file as File;

  const id = newProjectDocumentId();
  const safeName = sanitizeFileName(uploadFile.name);
  const storagePath = `project-documents/${id}/${safeName}`;

  const buffer = Buffer.from(await uploadFile.arrayBuffer());
  const uploadResult = await uploadProjectDocumentFile(storagePath, buffer);

  if (!uploadResult.ok) {
    return { ok: false, error: uploadResult.error };
  }

  try {
    await createProjectDocument(
      id,
      storagePath,
      {
        title: title.trim(),
        category: category as ProjectDocumentCategory,
        documentDate,
        fileName: uploadFile.name,
        fileSize: uploadFile.size,
      },
      auth.admin.email,
    );
  } catch (error) {
    try {
      await deleteProjectDocumentFile(storagePath);
    } catch {
      // Best-effort cleanup only; the metadata-write error below is what the
      // admin needs to see and act on.
    }

    return {
      ok: false,
      error:
        error instanceof Error
          ? error.message
          : "Failed to save the document record.",
    };
  }

  revalidateDocumentPaths();

  return { ok: true };
}

// Deletes a document's Firestore record, then its Storage object. Mirrors
// removeProjectDocument()'s own contract: the Firestore delete (and its
// audit log entry) is the record of intent, so it runs first; the Storage
// delete tolerates an already-missing object.
export async function deleteProjectDocument(
  id: string,
): Promise<DocumentActionResult> {
  const auth = await requireAdmin();
  if (!auth.ok) {
    return auth;
  }

  const record = await getProjectDocumentById(id);
  if (!record) {
    return { ok: false, error: "This document no longer exists." };
  }

  await removeProjectDocument(id, auth.admin.email);
  await deleteProjectDocumentFile(record.storagePath);

  revalidateDocumentPaths();

  return { ok: true };
}
