import { NextResponse } from "next/server";
import { hasFirebaseEnv } from "@/lib/firebase/config";
import { getProjectDocumentById } from "@/lib/firebase/firestore";
import { downloadProjectDocumentFile } from "@/lib/firebase/storage";

type PreviewRouteContext = {
  params: Promise<{ id: string }>;
};

// Public route: published project documents have no admin gate. Streams the
// PDF bytes inline so the detail page's <iframe> can render it directly,
// without ever minting a signed Cloud Storage URL (see the header comment in
// src/lib/firebase/storage.ts).
export async function GET(_request: Request, context: PreviewRouteContext) {
  if (!hasFirebaseEnv()) {
    return NextResponse.json(
      { error: "Firebase is not configured in this environment." },
      { status: 503 },
    );
  }

  const { id } = await context.params;
  const record = await getProjectDocumentById(id);

  if (!record) {
    return NextResponse.json({ error: "Document not found." }, { status: 404 });
  }

  const { buffer, error } = await downloadProjectDocumentFile(
    record.storagePath,
  );

  if (!buffer || error) {
    return NextResponse.json(
      { error: error ?? "Document file could not be loaded." },
      { status: 404 },
    );
  }

  return new Response(new Uint8Array(buffer), {
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": "inline",
    },
  });
}
