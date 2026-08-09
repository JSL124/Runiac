import { describe, expect, it } from "vitest";

import {
  filterProjectDocuments,
  formatDateTime,
  formatDisplayDate,
  formatFileSize,
  MAX_DOCUMENT_BYTES,
  validateProjectDocumentInput,
  type ProjectDocumentInput,
  type ProjectDocumentRecord,
} from "../project-documents";

// --- validateProjectDocumentInput -------------------------------------------

function validInput(
  overrides: Partial<ProjectDocumentInput> = {},
): ProjectDocumentInput {
  return {
    title: "Sprint 4 architecture review",
    category: "architecture",
    documentDate: "2026-07-01",
    file: { name: "doc.pdf", size: 1024, type: "application/pdf" },
    ...overrides,
  };
}

describe("validateProjectDocumentInput", () => {
  it("accepts a valid payload with zero errors", () => {
    expect(validateProjectDocumentInput(validInput()).errors).toEqual([]);
  });

  it("rejects an empty title", () => {
    const result = validateProjectDocumentInput(validInput({ title: "" }));
    expect(result.errors).toContain("Title must be between 1 and 160 characters.");
  });

  it("rejects a whitespace-only title", () => {
    const result = validateProjectDocumentInput(validInput({ title: "   " }));
    expect(result.errors).toContain("Title must be between 1 and 160 characters.");
  });

  it("rejects a 161-char title", () => {
    const result = validateProjectDocumentInput(
      validInput({ title: "a".repeat(161) }),
    );
    expect(result.errors).toContain("Title must be between 1 and 160 characters.");
  });

  it("accepts a 160-char title (boundary)", () => {
    const result = validateProjectDocumentInput(
      validInput({ title: "a".repeat(160) }),
    );
    expect(result.errors).toEqual([]);
  });

  it("rejects an unknown category", () => {
    const result = validateProjectDocumentInput(
      validInput({ category: "not-a-real-category" }),
    );
    expect(result.errors).toContain(
      "Category must be one of the supported document categories.",
    );
  });

  it("rejects a date that matches the pattern but is not a real calendar date", () => {
    const result = validateProjectDocumentInput(
      validInput({ documentDate: "2026-13-45" }),
    );
    expect(result.errors).toContain(
      "Document date must be a valid date in YYYY-MM-DD format.",
    );
  });

  it("rejects a 2-digit year (does not match the YYYY-MM-DD pattern)", () => {
    const result = validateProjectDocumentInput(
      validInput({ documentDate: "26-01-01" }),
    );
    expect(result.errors).toContain(
      "Document date must be a valid date in YYYY-MM-DD format.",
    );
  });

  it("rejects an empty date", () => {
    const result = validateProjectDocumentInput(
      validInput({ documentDate: "" }),
    );
    expect(result.errors).toContain(
      "Document date must be a valid date in YYYY-MM-DD format.",
    );
  });

  it("rejects a missing file", () => {
    const result = validateProjectDocumentInput(validInput({ file: null }));
    expect(result.errors).toContain("A PDF file is required.");
  });

  it("rejects a zero-byte file", () => {
    const result = validateProjectDocumentInput(
      validInput({ file: { name: "doc.pdf", size: 0, type: "application/pdf" } }),
    );
    expect(
      result.errors.some((error) => error.startsWith("File size must be")),
    ).toBe(true);
  });

  it("rejects a file one byte over MAX_DOCUMENT_BYTES", () => {
    const result = validateProjectDocumentInput(
      validInput({
        file: {
          name: "doc.pdf",
          size: MAX_DOCUMENT_BYTES + 1,
          type: "application/pdf",
        },
      }),
    );
    expect(
      result.errors.some((error) => error.startsWith("File size must be")),
    ).toBe(true);
  });

  it("accepts a file of exactly MAX_DOCUMENT_BYTES (boundary)", () => {
    const result = validateProjectDocumentInput(
      validInput({
        file: {
          name: "doc.pdf",
          size: MAX_DOCUMENT_BYTES,
          type: "application/pdf",
        },
      }),
    );
    expect(result.errors).toEqual([]);
  });

  it("rejects a non-PDF MIME type", () => {
    const result = validateProjectDocumentInput(
      validInput({
        file: { name: "doc.pdf", size: 1024, type: "application/msword" },
      }),
    );
    expect(result.errors).toContain("File must be a PDF (application/pdf).");
  });

  it("rejects a valid-MIME file whose name does not end .pdf", () => {
    const result = validateProjectDocumentInput(
      validInput({
        file: { name: "doc.docx", size: 1024, type: "application/pdf" },
      }),
    );
    expect(result.errors).toContain("File name must end with .pdf.");
  });
});

// --- filterProjectDocuments --------------------------------------------------

function record(overrides: Partial<ProjectDocumentRecord>): ProjectDocumentRecord {
  return {
    id: "id",
    title: "Untitled",
    category: "proposal",
    documentDate: "2026-01-01",
    fileName: "doc.pdf",
    fileSize: 1024,
    storagePath: "project-documents/id/doc.pdf",
    createdAt: "2026-01-01T00:00:00.000Z",
    createdBy: "admin@example.com",
    ...overrides,
  };
}

const architectureDoc = record({
  id: "arch-1",
  title: "Architecture Overview",
  category: "architecture",
  documentDate: "2026-01-10",
});
const meetingMinutesDoc = record({
  id: "mm-1",
  title: "Meeting Minutes Jan",
  category: "meeting-minutes",
  documentDate: "2026-01-15",
});
const proposalDraftDoc = record({
  id: "prop-1",
  title: "Proposal Draft",
  category: "proposal",
  documentDate: "2026-02-01",
});
const userManualDoc = record({
  id: "man-1",
  title: "User Manual",
  category: "manual",
  documentDate: "2026-02-10",
});

const allDocs = [architectureDoc, meetingMinutesDoc, proposalDraftDoc, userManualDoc];

describe("filterProjectDocuments", () => {
  it("filters by exact category match", () => {
    expect(filterProjectDocuments(allDocs, { category: "architecture" })).toEqual([
      architectureDoc,
    ]);
  });

  it("includes a record exactly on the inclusive `from`/`to` boundary", () => {
    const result = filterProjectDocuments(allDocs, {
      from: "2026-01-15",
      to: "2026-01-15",
    });
    expect(result).toEqual([meetingMinutesDoc]);
  });

  it("excludes records outside the from/to range", () => {
    const result = filterProjectDocuments(allDocs, {
      from: "2026-01-11",
      to: "2026-01-31",
    });
    expect(result).toEqual([meetingMinutesDoc]);
  });

  it("matches titles case-insensitively via substring", () => {
    expect(filterProjectDocuments(allDocs, { query: "DRAFT" })).toEqual([
      proposalDraftDoc,
    ]);
    expect(filterProjectDocuments(allDocs, { query: "manual" })).toEqual([
      userManualDoc,
    ]);
  });

  it("returns everything when filters are empty or absent", () => {
    expect(filterProjectDocuments(allDocs, {})).toEqual(allDocs);
    expect(
      filterProjectDocuments(allDocs, { category: "", query: "", from: "", to: "" }),
    ).toEqual(allDocs);
  });

  it("intersects combined filters", () => {
    expect(
      filterProjectDocuments(allDocs, { category: "proposal", query: "draft" }),
    ).toEqual([proposalDraftDoc]);

    expect(
      filterProjectDocuments(allDocs, { category: "proposal", query: "manual" }),
    ).toEqual([]);
  });
});

// --- formatters ---------------------------------------------------------------

describe("formatDisplayDate", () => {
  it("formats a YYYY-MM-DD date using the en-SG day/month/year style", () => {
    expect(formatDisplayDate("2026-07-01")).toBe("01 Jul 2026");
  });

  it("returns the input unchanged when it cannot be parsed", () => {
    expect(formatDisplayDate("not-a-date")).toBe("not-a-date");
  });
});

describe("formatDateTime", () => {
  it("formats an ISO timestamp into a date + time string", () => {
    const result = formatDateTime("2026-07-15T08:30:00.000Z");
    expect(result).not.toBe("2026-07-15T08:30:00.000Z");
    expect(result).toMatch(/^\d{2} \w{3} \d{4}, \d{1,2}:\d{2}/);
  });

  it("returns the input unchanged when it cannot be parsed", () => {
    expect(formatDateTime("not-a-date")).toBe("not-a-date");
  });
});

describe("formatFileSize", () => {
  it("formats bytes under 1024 with no decimal", () => {
    expect(formatFileSize(500)).toBe("500 B");
  });

  it("formats kilobytes with one decimal place under 10 units", () => {
    expect(formatFileSize(1536)).toBe("1.5 KB");
  });

  it("formats MAX_DOCUMENT_BYTES as 25 MB", () => {
    expect(formatFileSize(MAX_DOCUMENT_BYTES)).toBe("25 MB");
  });

  it('returns "Unknown size" for zero bytes', () => {
    expect(formatFileSize(0)).toBe("Unknown size");
  });

  it('returns "Unknown size" for null', () => {
    expect(formatFileSize(null)).toBe("Unknown size");
  });
});
