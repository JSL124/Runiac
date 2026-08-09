// Canonical schema, validation, and filtering for the admin console's
// "Project Documents" library (PDF-only): proposal, architecture, manual, and
// meeting-minutes records, each backed by one Cloud Storage object.
//
// Pure module (no Firebase / server imports), matching the contract of
// src/lib/site-documents.ts, so it can be shared by the server-side
// Firestore/Storage layer (src/lib/firebase/firestore.ts,
// src/lib/firebase/storage.ts), a later upload/list/download route-handler
// layer, and the admin console UI — the same rules run on both the server
// (source of truth) and the client (fast feedback before a round trip).
//
// formatDisplayDate / formatDateTime / formatFileSize are moved verbatim from
// src/lib/meeting-minutes.ts (same en-SG locale) so the two document
// libraries render dates and sizes identically.

export type ProjectDocumentCategory =
  | "proposal"
  | "architecture"
  | "manual"
  | "meeting-minutes";

export type ProjectDocumentCategoryOption = {
  value: ProjectDocumentCategory;
  label: string;
};

// Display labels shown in the admin console's category filter/select.
export const PROJECT_DOCUMENT_CATEGORIES: ProjectDocumentCategoryOption[] = [
  { value: "proposal", label: "Core document" },
  { value: "architecture", label: "Architecture" },
  { value: "manual", label: "Product guide" },
  { value: "meeting-minutes", label: "Project records" },
];

const PROJECT_DOCUMENT_CATEGORY_VALUES: ProjectDocumentCategory[] =
  PROJECT_DOCUMENT_CATEGORIES.map((entry) => entry.value);

export const MAX_DOCUMENT_BYTES = 25 * 1024 * 1024;

// A single row in the `projectDocuments` Firestore collection. The PDF bytes
// themselves live in Cloud Storage at `storagePath` (see
// src/lib/firebase/storage.ts); this record only carries metadata.
export type ProjectDocumentRecord = {
  id: string;
  title: string;
  category: ProjectDocumentCategory;
  documentDate: string;
  fileName: string;
  fileSize: number;
  storagePath: string;
  createdAt: string;
  createdBy: string;
};

export type ProjectDocumentFileInput = {
  name: string;
  size: number;
  type: string;
};

export type ProjectDocumentInput = {
  title: string;
  category: string;
  documentDate: string;
  file: ProjectDocumentFileInput | null;
};

export type ProjectDocumentValidationResult = {
  errors: string[];
};

const TITLE_MAX_LENGTH = 160;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function isKnownCategory(value: string): value is ProjectDocumentCategory {
  return (PROJECT_DOCUMENT_CATEGORY_VALUES as string[]).includes(value);
}

// Accepts only well-formed calendar dates: the regex rejects malformed
// strings, and the round trip through Date rejects strings that match the
// pattern but do not exist on the calendar (e.g. "2026-13-45").
function isValidCalendarDate(value: string): boolean {
  if (!DATE_PATTERN.test(value)) {
    return false;
  }

  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));

  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

// Validates a project-document upload before it reaches Firestore/Storage.
// Rules:
//   * title      - 1 to 160 characters after trimming.
//   * category   - must be one of PROJECT_DOCUMENT_CATEGORIES.
//   * documentDate - YYYY-MM-DD and a real calendar date.
//   * file       - present, non-empty, at most MAX_DOCUMENT_BYTES, PDF
//     content type, and a ".pdf" file name (case-insensitive).
export function validateProjectDocumentInput(
  input: ProjectDocumentInput,
): ProjectDocumentValidationResult {
  const errors: string[] = [];

  const title = input.title.trim();
  if (title.length === 0 || title.length > TITLE_MAX_LENGTH) {
    errors.push("Title must be between 1 and 160 characters.");
  }

  if (!isKnownCategory(input.category)) {
    errors.push("Category must be one of the supported document categories.");
  }

  if (!isValidCalendarDate(input.documentDate)) {
    errors.push("Document date must be a valid date in YYYY-MM-DD format.");
  }

  const file = input.file;
  if (!file) {
    errors.push("A PDF file is required.");
  } else {
    if (!(file.size > 0 && file.size <= MAX_DOCUMENT_BYTES)) {
      errors.push(
        `File size must be greater than 0 and at most ${formatFileSize(
          MAX_DOCUMENT_BYTES,
        )}.`,
      );
    }
    if (file.type !== "application/pdf") {
      errors.push("File must be a PDF (application/pdf).");
    }
    if (!/\.pdf$/i.test(file.name)) {
      errors.push("File name must end with .pdf.");
    }
  }

  return { errors };
}

export type ProjectDocumentFilters = {
  category?: ProjectDocumentCategory | "";
  query?: string;
  from?: string;
  to?: string;
};

// In-memory filtering over an already-fetched page of records (see the
// 200-doc ceiling noted on listProjectDocuments() in
// src/lib/firebase/firestore.ts). Applies:
//   * category - exact match, skipped when empty/absent.
//   * from/to  - inclusive documentDate range, each side optional.
//   * query    - case-insensitive substring match over
//     `title + documentDate + createdAt`.
export function filterProjectDocuments(
  records: ProjectDocumentRecord[],
  filters: ProjectDocumentFilters,
): ProjectDocumentRecord[] {
  const category = filters.category?.trim();
  const from = filters.from?.trim();
  const to = filters.to?.trim();
  const searchText = filters.query?.trim().toLowerCase();

  return records.filter((record) => {
    if (category && record.category !== category) {
      return false;
    }

    if (from && record.documentDate < from) {
      return false;
    }

    if (to && record.documentDate > to) {
      return false;
    }

    if (searchText) {
      const haystack = `${record.title} ${record.documentDate} ${record.createdAt}`
        .toLowerCase();
      if (!haystack.includes(searchText)) {
        return false;
      }
    }

    return true;
  });
}

// --- formatting helpers (moved verbatim from src/lib/meeting-minutes.ts) ----

export function formatDisplayDate(dateValue: string) {
  const date = new Date(`${dateValue}T00:00:00`);

  if (Number.isNaN(date.getTime())) {
    return dateValue;
  }

  return new Intl.DateTimeFormat("en-SG", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  }).format(date);
}

export function formatDateTime(dateValue: string) {
  const date = new Date(dateValue);

  if (Number.isNaN(date.getTime())) {
    return dateValue;
  }

  return new Intl.DateTimeFormat("en-SG", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

export function formatFileSize(bytes: number | null | undefined) {
  if (!bytes || bytes <= 0) {
    return "Unknown size";
  }

  const units = ["B", "KB", "MB", "GB"];
  let size = bytes;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }

  return `${size.toFixed(size >= 10 || unitIndex === 0 ? 0 : 1)} ${
    units[unitIndex]
  }`;
}
