import { NextResponse } from "next/server";
import { hasFirebaseEnv } from "@/lib/firebase/config";
import { getProjectDocumentById } from "@/lib/firebase/firestore";
import { downloadProjectDocumentFile } from "@/lib/firebase/storage";

type DownloadRouteContext = {
  params: Promise<{ id: string }>;
};

// Strips characters that could break out of the quoted filename parameter
// (or inject extra header lines) if a stored fileName ever contained a
// double quote, carriage return, or line feed. Header injection is the real
// risk here, not display fidelity.
function sanitizeFileName(fileName: string): string {
  return fileName.replace(/["\r\n]/g, "");
}

// Public route: published project documents have no admin gate.
export async function GET(_request: Request, context: DownloadRouteContext) {
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

  const fileName = sanitizeFileName(record.fileName || `${record.id}.pdf`);

  return new Response(new Uint8Array(buffer), {
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `attachment; filename="${fileName}"`,
    },
  });
}
