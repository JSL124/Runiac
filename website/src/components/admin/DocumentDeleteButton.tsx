"use client";

// Delete control for a single row in the admin "Project Documents" library.
// Modeled on src/components/MeetingMinutesDeleteButton.tsx (window.confirm
// guard before the destructive action), but calls the deleteProjectDocument
// server action directly rather than posting to a route handler, since the
// admin console's other mutations are server actions (see FeedbackInbox,
// UserManagement) rather than form-post routes.

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { btnDanger } from "@/components/admin/button-styles";
import { deleteProjectDocument } from "@/lib/actions/documents";

export function DocumentDeleteButton({
  documentId,
  title,
}: {
  documentId: string;
  title: string;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function handleDelete() {
    const confirmed = window.confirm(
      `Delete "${title}"? This removes the record and its file.`,
    );

    if (!confirmed) {
      return;
    }

    setError(null);
    startTransition(async () => {
      const result = await deleteProjectDocument(documentId);

      if (!result.ok) {
        setError(result.error);
        return;
      }

      router.refresh();
    });
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <button
        type="button"
        onClick={handleDelete}
        disabled={isPending}
        className={btnDanger}
      >
        {isPending ? "Deleting..." : "Delete"}
      </button>
      {error ? (
        <span className="text-xs font-semibold text-[#b42318]">{error}</span>
      ) : null}
    </div>
  );
}
