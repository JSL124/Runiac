"use client";

// Upload form for the admin console's "Project Documents" PDF library. Uses
// a real <form> (not controlled inputs feeding a hand-built payload) because
// a <input type="file"> value can only be read out through FormData — see
// uploadProjectDocument() in @/lib/actions/documents, which this posts to.
//
// Client-side validation here is fast feedback only, reusing the same
// validateProjectDocumentInput() the server action re-runs unconditionally;
// it is never the source of truth.

import { useRef, useState } from "react";
import { btnPrimary, inputBase } from "@/components/admin/button-styles";
import { uploadProjectDocument } from "@/lib/actions/documents";
import {
  PROJECT_DOCUMENT_CATEGORIES,
  validateProjectDocumentInput,
} from "@/lib/project-documents";

const fieldLabel =
  "text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted";

export function DocumentUploader() {
  const formRef = useRef<HTMLFormElement>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  async function save() {
    const form = formRef.current;
    if (!form) {
      return;
    }

    const data = new FormData(form);
    const file = data.get("file");

    const validation = validateProjectDocumentInput({
      title: String(data.get("title") ?? ""),
      category: String(data.get("category") ?? ""),
      documentDate: String(data.get("documentDate") ?? ""),
      file:
        file instanceof File
          ? { name: file.name, size: file.size, type: file.type }
          : null,
    });

    if (validation.errors.length > 0) {
      setError(validation.errors.join(" "));
      setSuccess(false);
      return;
    }

    setSaving(true);
    setError(null);
    setSuccess(false);

    // The action can reject outright rather than returning { ok: false } —
    // a dropped connection, a request body over the configured limit, or a
    // stale Server Action id after a redeploy ("Failed to find Server
    // Action ..."). Without the catch/finally the button would sit on
    // "Uploading..." forever with nothing explaining why.
    try {
      const result = await uploadProjectDocument(data);

      if (!result.ok) {
        setError(result.error);
        return;
      }

      form.reset();
      setSuccess(true);
    } catch {
      setError(
        "The upload could not be completed. Reload the page and try again.",
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <form
      ref={formRef}
      onSubmit={(event) => {
        event.preventDefault();
        void save();
      }}
      className="space-y-4"
    >
      {error ? (
        <p
          role="alert"
          className="rounded-lg border border-[#f0c2bc] bg-[#fdecea] px-4 py-3 text-sm font-semibold text-[#b42318]"
        >
          {error}
        </p>
      ) : null}
      {success ? (
        <p className="rounded-lg border border-[#bfe3d3] bg-[#eafaf3] px-4 py-3 text-sm font-semibold text-[#0f6b4e]">
          Document uploaded.
        </p>
      ) : null}

      <div className="grid gap-4 sm:grid-cols-2">
        <label className="flex flex-col gap-1">
          <span className={fieldLabel}>Title</span>
          <input
            type="text"
            name="title"
            required
            maxLength={160}
            disabled={saving}
            className={inputBase}
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className={fieldLabel}>Category</span>
          <select
            name="category"
            required
            disabled={saving}
            defaultValue={PROJECT_DOCUMENT_CATEGORIES[0]?.value ?? ""}
            className={`${inputBase} cursor-pointer pr-8`}
          >
            {PROJECT_DOCUMENT_CATEGORIES.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1">
          <span className={fieldLabel}>Document date</span>
          <input
            type="date"
            name="documentDate"
            required
            disabled={saving}
            className={inputBase}
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className={fieldLabel}>PDF file</span>
          <input
            type="file"
            name="file"
            accept="application/pdf"
            required
            disabled={saving}
            className={`${inputBase} h-auto py-1.5`}
          />
        </label>
      </div>

      <button type="submit" disabled={saving} className={btnPrimary}>
        {saving ? "Uploading..." : "Upload document"}
      </button>
    </form>
  );
}
