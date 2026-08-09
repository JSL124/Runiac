import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";
import { getProjectDocumentById } from "@/lib/firebase/firestore";
import {
  formatDateTime,
  formatDisplayDate,
  formatFileSize,
  PROJECT_DOCUMENT_CATEGORIES,
  type ProjectDocumentCategory,
} from "@/lib/project-documents";

type ProjectDocumentDetailPageProps = {
  params: Promise<{ id: string }>;
};

function categoryLabel(category: ProjectDocumentCategory) {
  return (
    PROJECT_DOCUMENT_CATEGORIES.find((entry) => entry.value === category)
      ?.label ?? category
  );
}

export async function generateMetadata({
  params,
}: ProjectDocumentDetailPageProps): Promise<Metadata> {
  const { id } = await params;
  const record = await getProjectDocumentById(id);

  if (!record) {
    return {
      title: "Documents - Runiac",
    };
  }

  return {
    title: `${record.title} - Runiac Documents`,
    description: `Project document dated ${record.documentDate}.`,
  };
}

const containerStyle = {
  width: "calc(100vw - 3rem)",
  maxWidth: "72rem",
};

export default async function ProjectDocumentDetailPage({
  params,
}: ProjectDocumentDetailPageProps) {
  const { id } = await params;
  const record = await getProjectDocumentById(id);

  if (!record) {
    notFound();
  }

  return (
    <>
      <Navbar />
      <main className="flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden bg-background">
        <section className="box-border w-full px-0 py-16 sm:py-20 lg:py-24">
          <div className="mx-auto" style={containerStyle}>
            <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
              <div className="max-w-3xl">
                <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand sm:text-sm">
                  {categoryLabel(record.category)}
                </p>
                <h1 className="mt-4 break-words font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[2rem] font-normal uppercase leading-[1.04] tracking-normal text-[#4058b0] sm:text-5xl lg:text-6xl">
                  {record.title}
                </h1>
              </div>
              <div className="flex flex-wrap gap-3">
                <Link
                  href="/documents"
                  className="rounded-full border border-brand/20 px-5 py-3 text-sm font-semibold text-brand transition hover:bg-brand-soft"
                >
                  Back to records
                </Link>
                <a
                  href={`/api/documents/${record.id}/download`}
                  className="rounded-full bg-accent px-5 py-3 text-sm font-semibold text-white transition hover:bg-accent/90"
                >
                  Download PDF
                </a>
              </div>
            </div>

            <div className="mt-10 grid gap-8 lg:grid-cols-[18rem_minmax(0,1fr)] lg:items-start">
              <aside className="rounded-lg border border-border bg-white p-5 shadow-[0_24px_70px_-56px_rgba(0,30,98,0.42)]">
                <p className="text-xs font-semibold uppercase tracking-[0.16em] text-brand">
                  Record details
                </p>
                <dl className="mt-5 space-y-4 text-sm">
                  <div>
                    <dt className="font-semibold text-foreground">
                      Document date
                    </dt>
                    <dd className="mt-1 text-muted">
                      {formatDisplayDate(record.documentDate)}
                    </dd>
                  </div>
                  <div>
                    <dt className="font-semibold text-foreground">Created</dt>
                    <dd className="mt-1 text-muted">
                      {formatDateTime(record.createdAt)}
                    </dd>
                  </div>
                  <div>
                    <dt className="font-semibold text-foreground">File</dt>
                    <dd className="mt-1 break-words text-muted">
                      {record.fileName}
                    </dd>
                  </div>
                  <div>
                    <dt className="font-semibold text-foreground">Size</dt>
                    <dd className="mt-1 text-muted">
                      {formatFileSize(record.fileSize)}
                    </dd>
                  </div>
                </dl>
                {/* Admin-only delete lives in /admin/documents (owned by a
                    parallel worker); this public page never renders it. */}
              </aside>

              <section className="min-w-0 overflow-hidden rounded-lg border border-border bg-white shadow-[0_24px_70px_-56px_rgba(0,30,98,0.45)]">
                <div className="border-b border-border px-5 py-4 sm:px-6">
                  <h2 className="text-xl font-semibold text-foreground">
                    PDF preview
                  </h2>
                </div>
                <iframe
                  title={`${record.title} PDF preview`}
                  src={`/api/documents/${record.id}/preview`}
                  className="h-[72vh] min-h-[34rem] w-full bg-brand-soft"
                />
              </section>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
