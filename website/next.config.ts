import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  devIndicators: false,
  // Dev-only: Next 16 treats 127.0.0.1 and localhost as different origins and
  // blocks HMR + Server Actions (config saves) when the browser host isn't an
  // allowed dev origin. Accessing the admin console at http://127.0.0.1:3000
  // otherwise makes every "Save …" button silently no-op. No effect in prod.
  allowedDevOrigins: ["127.0.0.1", "localhost"],
  turbopack: {
    root: process.cwd(),
  },
  // Project-document uploads (see src/lib/project-documents.ts) post a PDF
  // through a Server Action. Next's default Server Action body limit is 1mb,
  // well under MAX_DOCUMENT_BYTES (25mb) in that module — keep this in sync
  // with MAX_DOCUMENT_BYTES if that constant ever changes.
  experimental: {
    serverActions: {
      bodySizeLimit: "25mb",
    },
  },
};

export default nextConfig;
