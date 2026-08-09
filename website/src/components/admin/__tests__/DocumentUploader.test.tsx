import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

import { DocumentUploader } from "../DocumentUploader";

const uploadProjectDocumentMock = vi.fn();

// The server actions module is "use server" and pulls in firebase-admin /
// server-only deps that must never load under jsdom. Mock the whole module,
// matching the pattern in PolicySettings.character.test.tsx.
vi.mock("@/lib/actions/documents", () => ({
  uploadProjectDocument: (...args: [FormData]) => uploadProjectDocumentMock(...args),
}));

// jsdom's `new FormData(form)` constructor always synthesizes an empty
// placeholder File entry for every `<input type="file">` — verified by
// direct inspection: it returns the exact same `File { name: "", size: 0,
// type: "application/octet-stream" }` whether the input has a real selected
// file (set via userEvent.upload) or none at all. This is a jsdom platform
// gap (form-associated File-API submission isn't implemented; jsdom also
// has no DataTransfer constructor), not a bug in DocumentUploader, which
// builds its payload via the same `new FormData(form)` a real browser
// supports correctly. Every other field (text/select inputs) IS read
// correctly by jsdom's FormData(form) — only file entries are broken.
//
// Patch the global FormData for this file's tests so its constructor
// replaces that placeholder with the input's real File(s), matching what a
// real browser would produce, so the assertions below exercise the actual
// client-side validation and payload-building logic instead of always
// failing on an unfillable file field.
const NativeFormData = globalThis.FormData;

class BrowserLikeFormData extends NativeFormData {
  constructor(form?: HTMLFormElement) {
    super(form);
    if (!form) {
      return;
    }
    for (const element of Array.from(form.elements)) {
      if (element instanceof HTMLInputElement && element.type === "file" && element.name) {
        this.delete(element.name);
        if (element.files) {
          for (const file of Array.from(element.files)) {
            this.append(element.name, file);
          }
        }
      }
    }
  }
}

function pdfFile(name = "architecture.pdf") {
  return new File(["%PDF-1.4 fake content"], name, { type: "application/pdf" });
}

function textFile(name = "notes.txt") {
  return new File(["plain text"], name, { type: "text/plain" });
}

async function fillValidFields(user: ReturnType<typeof userEvent.setup>) {
  await user.type(
    screen.getByLabelText("Title"),
    "Sprint 4 architecture review",
  );
  await user.selectOptions(screen.getByLabelText("Category"), "architecture");
  fireEvent.change(screen.getByLabelText("Document date"), {
    target: { value: "2026-07-01" },
  });
}

// Queried without a `name` filter because the button's accessible name
// changes from "Upload document" to "Uploading..." while saving=true — a
// name-filtered query would stop matching mid-flight. There is only ever
// one button in this form.
function submitButton() {
  return screen.getByRole("button");
}

// jsdom's native form-submission algorithm runs HTML5 constraint validation
// (the `required` type="date"/type="file" inputs here) before it ever
// dispatches a "submit" event, and jsdom's constraint-validation support for
// those input types is unreliable enough that a real user.click() on the
// submit button never reaches React's onSubmit handler in this environment.
// Dispatching "submit" on the <form> directly (as the DocumentUploader's own
// onSubmit handler expects) exercises the same save() code path without
// depending on jsdom's native validation gate.
function submitForm(container: HTMLElement) {
  const form = container.querySelector("form");
  if (!form) {
    throw new Error("form not found");
  }
  fireEvent.submit(form);
}

describe("DocumentUploader", () => {
  beforeEach(() => {
    uploadProjectDocumentMock.mockReset();
    globalThis.FormData = BrowserLikeFormData as unknown as typeof FormData;
  });

  afterEach(() => {
    globalThis.FormData = NativeFormData;
  });

  it("shows a client-side validation error and does not call the server action when a non-PDF file is selected", async () => {
    // applyAccept: false — the input has accept="application/pdf", and
    // userEvent.upload() faithfully mimics a real OS file picker by
    // silently dropping files that don't match `accept` (verified: with the
    // default config, input.files stays empty after uploading a .txt here).
    // Disabling that filter is what lets this test simulate the exact
    // scenario validateProjectDocumentInput() exists to catch — a
    // non-PDF file actually reaching the input's `.files` (a real user can
    // still do this: drag-and-drop, or an OS file dialog with "All Files").
    const user = userEvent.setup({ applyAccept: false });
    const { container } = render(<DocumentUploader />);

    await fillValidFields(user);
    await user.upload(screen.getByLabelText("PDF file"), textFile());
    submitForm(container);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      /File must be a PDF/i,
    );
    expect(uploadProjectDocumentMock).not.toHaveBeenCalled();
  });

  it("calls the server action exactly once with a FormData carrying title, category, documentDate and file on a valid submission", async () => {
    uploadProjectDocumentMock.mockResolvedValue({ ok: true });
    const user = userEvent.setup();
    const { container } = render(<DocumentUploader />);

    await fillValidFields(user);
    const file = pdfFile();
    await user.upload(screen.getByLabelText("PDF file"), file);
    submitForm(container);

    await waitFor(() => {
      expect(uploadProjectDocumentMock).toHaveBeenCalledTimes(1);
    });

    const formData = uploadProjectDocumentMock.mock.calls[0][0] as FormData;
    expect(formData.get("title")).toBe("Sprint 4 architecture review");
    expect(formData.get("category")).toBe("architecture");
    expect(formData.get("documentDate")).toBe("2026-07-01");

    const submittedFile = formData.get("file");
    expect(submittedFile).toBeInstanceOf(File);
    expect((submittedFile as File).name).toBe("architecture.pdf");
    expect((submittedFile as File).type).toBe("application/pdf");
  });

  it("disables the submit control while the action is in flight", async () => {
    let resolveUpload!: (value: { ok: true }) => void;
    uploadProjectDocumentMock.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveUpload = resolve;
        }),
    );
    const user = userEvent.setup();
    const { container } = render(<DocumentUploader />);

    await fillValidFields(user);
    await user.upload(screen.getByLabelText("PDF file"), pdfFile());
    submitForm(container);

    await waitFor(() => {
      expect(submitButton()).toBeDisabled();
    });
    expect(submitButton()).toHaveTextContent(/uploading/i);

    resolveUpload({ ok: true });

    await waitFor(() => {
      expect(submitButton()).not.toBeDisabled();
    });
  });

  it("surfaces the server-side error and re-enables the form when the action returns ok: false", async () => {
    uploadProjectDocumentMock.mockResolvedValue({
      ok: false,
      error: "The specified bucket does not exist.",
    });
    const user = userEvent.setup();
    const { container } = render(<DocumentUploader />);

    await fillValidFields(user);
    await user.upload(screen.getByLabelText("PDF file"), pdfFile());
    submitForm(container);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      /The specified bucket does not exist/i,
    );
    expect(submitButton()).not.toBeDisabled();
  });

  // Regression: the handler used to call setSaving(false) only on the happy
  // path, so a rejection (dropped connection, oversized body, or a stale
  // Server Action id after a redeploy) left the button pinned to
  // "Uploading..." forever with nothing shown to explain it.
  it("recovers with a readable error when the action rejects instead of returning a result", async () => {
    uploadProjectDocumentMock.mockRejectedValue(
      new Error('Failed to find Server Action "40af5f8f"'),
    );
    const user = userEvent.setup();
    const { container } = render(<DocumentUploader />);

    await fillValidFields(user);
    await user.upload(screen.getByLabelText("PDF file"), pdfFile());
    submitForm(container);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      /could not be completed/i,
    );

    await waitFor(() => {
      expect(submitButton()).not.toBeDisabled();
    });
    expect(submitButton()).not.toHaveTextContent(/uploading/i);
  });
});
