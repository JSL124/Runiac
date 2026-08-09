// The public project-documents library.
//
// A server component that reads the document list directly through the Admin
// SDK — the files are uploaded from the admin console, so this page renders
// whatever is currently published without a client-side fetch.
//
// [hasFirebaseEnv] is checked first: with no Firebase configured the page still
// renders its shell and says the library is unavailable, rather than failing
// the build or throwing at request time.

import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";
import { hasFirebaseEnv } from "@/lib/firebase/config";
import { listProjectDocuments } from "@/lib/firebase/firestore";
import {
  filterProjectDocuments,
  formatDisplayDate,
  PROJECT_DOCUMENT_CATEGORIES,
  type ProjectDocumentCategory,
  type ProjectDocumentRecord,
} from "@/lib/project-documents";
import { getSiteContentWithFallback } from "@/lib/site-content";

export const metadata: Metadata = {
  title: "Documents - Runiac",
  description:
    "Browse, filter, preview, and download every Runiac project document.",
};

type DocumentsPageProps = {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
};

const containerStyle = {
  width: "calc(100vw - 3rem)",
  maxWidth: "72rem",
};

function getStringParam(value: string | string[] | undefined) {
  if (Array.isArray(value)) {
    return value[0] ?? "";
  }

  return value ?? "";
}

function SetupNotice() {
  return (
    <div className="rounded-lg border border-accent/20 bg-accent-soft p-5 text-sm leading-relaxed text-muted">
      <p className="font-semibold uppercase tracking-[0.14em] text-accent">
        Firebase setup required
      </p>
      <p className="mt-3">
        Firebase is not configured in this environment. Add the Firebase
        environment variables before records can be loaded.
      </p>
    </div>
  );
}

function categoryLabel(category: ProjectDocumentCategory) {
  return (
    PROJECT_DOCUMENT_CATEGORIES.find((entry) => entry.value === category)
      ?.label ?? category
  );
}

type DocumentsResult = {
  configured: boolean;
  error: string | null;
  records: ProjectDocumentRecord[];
};

async function loadDocuments(filters: {
  category: string;
  q: string;
  from: string;
  to: string;
}): Promise<DocumentsResult> {
  if (!hasFirebaseEnv()) {
    return { configured: false, error: null, records: [] };
  }

  try {
    const all = await listProjectDocuments();
    const records = filterProjectDocuments(all, {
      category: filters.category as ProjectDocumentCategory | "",
      query: filters.q,
      from: filters.from,
      to: filters.to,
    });
    return { configured: true, error: null, records };
  } catch (error) {
    return {
      configured: true,
      error:
        error instanceof Error
          ? error.message
          : "Documents could not be loaded.",
      records: [],
    };
  }
}

export default async function DocumentsPage({
  searchParams,
}: DocumentsPageProps) {
  const content = await getSiteContentWithFallback();
  const { documents } = content;

  const params = await searchParams;
  const category = getStringParam(params?.category);
  const q = getStringParam(params?.q);
  const from = getStringParam(params?.from);
  const to = getStringParam(params?.to);

  const documentsResult = await loadDocuments({ category, q, from, to });

  return (
    <>
      <Navbar />
      <main className="flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden">
        <section className="relative isolate box-border flex min-h-[calc(100svh-5.75rem)] w-full items-center overflow-hidden bg-brand px-0 py-20 text-white sm:py-24 lg:py-28">
          <Image
            src="/documents-runners.jpeg"
            alt="Motion-blurred runners moving forward together"
            fill
            priority
            sizes="100vw"
            className="-z-30 object-cover object-center opacity-70"
          />
          <div
            aria-hidden="true"
            className="absolute inset-0 -z-20 bg-[linear-gradient(180deg,rgba(0,16,20,0.70)_0%,rgba(0,30,98,0.72)_48%,rgba(242,106,61,0.58)_100%)]"
          />
          <div
            aria-hidden="true"
            className="absolute inset-0 -z-10 bg-[radial-gradient(circle_at_70%_20%,rgba(255,255,255,0.22),transparent_28%),radial-gradient(circle_at_16%_84%,rgba(255,255,255,0.18),transparent_36%)] backdrop-blur-[1.5px]"
          />

          <div className="mx-auto" style={containerStyle}>
            <div className="max-w-3xl">
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-white/78 sm:text-sm">
                Documents
              </p>
              <h1 className="mt-4 break-words font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[2rem] font-normal uppercase leading-[1.04] tracking-normal text-white drop-shadow-[0_20px_48px_rgba(0,0,0,0.35)] sm:max-w-5xl sm:text-6xl lg:text-7xl">
                {documents.heading}
              </h1>
              <p className="mt-6 text-base leading-relaxed text-white/82 drop-shadow-[0_10px_28px_rgba(0,0,0,0.28)] sm:text-lg">
                {documents.intro}
              </p>
            </div>

            <div className="mt-12 grid gap-5 sm:grid-cols-2">
              {documents.cards.map((document) => (
                <article
                  key={document.title}
                  className="rounded-lg border border-white/34 bg-white/88 p-6 text-foreground shadow-[0_24px_70px_-44px_rgba(0,16,20,0.72)] backdrop-blur-md transition-all hover:-translate-y-0.5 hover:bg-white/94 hover:shadow-[0_28px_80px_-42px_rgba(0,16,20,0.8)]"
                >
                  <p className="text-xs font-semibold uppercase tracking-[0.16em] text-brand">
                    {document.status}
                  </p>
                  <h2 className="mt-3 text-2xl font-semibold text-foreground">
                    {document.title}
                  </h2>
                  <p className="mt-4 text-sm leading-relaxed text-muted">
                    {document.body}
                  </p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="box-border w-full bg-background px-0 py-16 sm:py-20 lg:py-24">
          <div className="mx-auto" style={containerStyle}>
            <div className="max-w-3xl">
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand sm:text-sm">
                Document library
              </p>
              <h2 className="mt-4 break-words font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[2rem] font-normal uppercase leading-[1.04] tracking-normal text-[#4058b0] sm:text-4xl">
                Browse all records.
              </h2>
              <p className="mt-5 text-base leading-relaxed text-muted sm:text-lg">
                Search, filter, preview, and download every published Runiac
                project document.
              </p>
            </div>

            <div className="mt-10">
              <div className="min-w-0">
                <section className="rounded-lg border border-border bg-white p-5 shadow-[0_24px_70px_-56px_rgba(0,30,98,0.4)] sm:p-6">
                  <form className="grid gap-4" method="get">
                    <div>
                      <span className={"text-sm font-semibold text-foreground"}>
                        Category
                      </span>
                      <div className="mt-2 flex flex-wrap gap-2">
                        <label className="cursor-pointer">
                          <input
                            type="radio"
                            name="category"
                            value=""
                            defaultChecked={category === ""}
                            className="peer sr-only"
                          />
                          <span className="inline-flex items-center rounded-full border border-border px-4 py-2 text-sm font-semibold text-muted transition peer-checked:border-brand peer-checked:bg-brand peer-checked:text-white">
                            All
                          </span>
                        </label>
                        {PROJECT_DOCUMENT_CATEGORIES.map((entry) => (
                          <label key={entry.value} className="cursor-pointer">
                            <input
                              type="radio"
                              name="category"
                              value={entry.value}
                              defaultChecked={category === entry.value}
                              className="peer sr-only"
                            />
                            <span className="inline-flex items-center rounded-full border border-border px-4 py-2 text-sm font-semibold text-muted transition peer-checked:border-brand peer-checked:bg-brand peer-checked:text-white">
                              {entry.label}
                            </span>
                          </label>
                        ))}
                      </div>
                    </div>
                    <div>
                      <label
                        htmlFor="q"
                        className="text-sm font-semibold text-foreground"
                      >
                        Search
                      </label>
                      <input
                        id="q"
                        name="q"
                        type="search"
                        defaultValue={q}
                        placeholder="Search title, document date, or created date"
                        className="mt-2 min-h-12 w-full rounded-lg border border-border bg-white px-4 text-sm text-foreground outline-none transition placeholder:text-muted/55 focus:border-brand focus:ring-4 focus:ring-brand/10"
                      />
                    </div>
                    <div className="grid gap-4 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
                      <div>
                        <label
                          htmlFor="from"
                          className="text-sm font-semibold text-foreground"
                        >
                          From
                        </label>
                        <input
                          id="from"
                          name="from"
                          type="date"
                          defaultValue={from}
                          className="mt-2 min-h-12 w-full rounded-lg border border-border bg-white px-4 text-sm text-foreground outline-none transition focus:border-brand focus:ring-4 focus:ring-brand/10"
                        />
                      </div>
                      <div>
                        <label
                          htmlFor="to"
                          className="text-sm font-semibold text-foreground"
                        >
                          To
                        </label>
                        <input
                          id="to"
                          name="to"
                          type="date"
                          defaultValue={to}
                          className="mt-2 min-h-12 w-full rounded-lg border border-border bg-white px-4 text-sm text-foreground outline-none transition focus:border-brand focus:ring-4 focus:ring-brand/10"
                        />
                      </div>
                      <button
                        type="submit"
                        className="min-h-12 rounded-full bg-brand px-6 text-sm font-semibold text-white transition hover:bg-brand/90"
                      >
                        Filter
                      </button>
                    </div>
                    {(category || q || from || to) && (
                      <Link
                        href="/documents"
                        className="justify-self-start text-sm font-semibold text-accent transition hover:text-accent/80"
                      >
                        Clear filters
                      </Link>
                    )}
                  </form>
                </section>

                <section className="mt-6 overflow-hidden rounded-lg border border-border bg-white shadow-[0_24px_70px_-56px_rgba(0,30,98,0.42)]">
                  <div className="border-b border-border px-5 py-4 sm:px-6">
                    <h2 className="text-xl font-semibold text-foreground">
                      Records
                    </h2>
                    <p className="mt-1 text-sm text-muted">
                      Title, document date, and created date are searchable.
                    </p>
                  </div>

                  {!documentsResult.configured ? (
                    <div className="p-5 sm:p-6">
                      <SetupNotice />
                    </div>
                  ) : documentsResult.error ? (
                    <div className="p-5 sm:p-6">
                      <p className="rounded-lg border border-accent/20 bg-accent-soft px-4 py-3 text-sm font-semibold text-accent">
                        {documentsResult.error}
                      </p>
                    </div>
                  ) : documentsResult.records.length === 0 ? (
                    <div className="p-8 text-center">
                      <p className="text-lg font-semibold text-foreground">
                        No documents found.
                      </p>
                      <p className="mt-2 text-sm leading-relaxed text-muted">
                        Try another search term, category, or date range.
                      </p>
                    </div>
                  ) : (
                    <div className="divide-y divide-border">
                      {documentsResult.records.map((record) => (
                        <Link
                          key={record.id}
                          href={`/documents/${record.id}`}
                          className="grid gap-3 px-5 py-5 transition hover:bg-brand-soft/45 sm:grid-cols-[minmax(0,1fr)_12rem] sm:px-6"
                        >
                          <div className="min-w-0">
                            <h3 className="break-words text-lg font-semibold text-foreground">
                              {record.title}
                            </h3>
                            <p className="mt-2 text-sm font-medium text-brand">
                              Document date:{" "}
                              {formatDisplayDate(record.documentDate)}
                            </p>
                            <p className="mt-1 break-words text-xs font-semibold uppercase tracking-[0.12em] text-muted">
                              {record.fileName}
                            </p>
                          </div>
                          <div className="sm:text-right">
                            <span className="inline-flex items-center rounded-full bg-brand-soft px-3 py-1 text-xs font-semibold uppercase tracking-[0.1em] text-brand">
                              {categoryLabel(record.category)}
                            </span>
                          </div>
                        </Link>
                      ))}
                    </div>
                  )}
                </section>
              </div>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
