import { DocumentDeleteButton } from "@/components/admin/DocumentDeleteButton";
import { DocumentUploader } from "@/components/admin/DocumentUploader";
import {
  AdminSection,
  Chip,
  EmptyState,
  InfoBanner,
  PageHeader,
  TableWrap,
} from "@/components/admin/primitives";
import { hasFirebaseEnv } from "@/lib/firebase/config";
import { listProjectDocuments } from "@/lib/firebase/firestore";
import {
  PROJECT_DOCUMENT_CATEGORIES,
  formatDisplayDate,
  formatFileSize,
} from "@/lib/project-documents";

export const dynamic = "force-dynamic";

function categoryLabel(value: string): string {
  return (
    PROJECT_DOCUMENT_CATEGORIES.find((option) => option.value === value)
      ?.label ?? value
  );
}

export default async function AdminDocumentsPage() {
  if (!hasFirebaseEnv()) {
    return (
      <>
        <PageHeader title="Project Documents" />
        <InfoBanner tone="warn">
          Firebase is not configured in this environment, so the document
          library cannot be read or written here.
        </InfoBanner>
      </>
    );
  }

  const documents = await listProjectDocuments();

  return (
    <>
      <PageHeader title="Project Documents" />

      <AdminSection title="Upload a document">
        <DocumentUploader />
      </AdminSection>

      <div className="space-y-3">
        <div className="flex items-center gap-2">
          <h2 className="text-lg font-bold text-brand">Library</h2>
          <Chip tone="muted">{documents.length}</Chip>
        </div>

        {documents.length === 0 ? (
          <EmptyState
            title="No documents yet"
            description="Uploaded PDFs will appear here."
          />
        ) : (
          <div className="rounded-lg border border-border bg-white shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)]">
            <TableWrap>
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-[0.7rem] uppercase tracking-[0.12em] text-muted">
                    <th className="py-3 pr-4 font-bold">Title</th>
                    <th className="py-3 pr-4 font-bold">Category</th>
                    <th className="py-3 pr-4 font-bold">Date</th>
                    <th className="py-3 pr-4 font-bold">Size</th>
                    <th className="py-3 pr-2 font-bold text-right">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {documents.map((document) => (
                    <tr
                      key={document.id}
                      className="border-b border-border align-top last:border-0"
                    >
                      <td className="py-3 pr-4 font-semibold text-brand">
                        {document.title}
                      </td>
                      <td className="py-3 pr-4 text-foreground">
                        {categoryLabel(document.category)}
                      </td>
                      <td className="py-3 pr-4 text-muted">
                        {formatDisplayDate(document.documentDate)}
                      </td>
                      <td className="py-3 pr-4 text-muted">
                        {formatFileSize(document.fileSize)}
                      </td>
                      <td className="py-3 pr-2 text-right">
                        <DocumentDeleteButton
                          documentId={document.id}
                          title={document.title}
                        />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TableWrap>
          </div>
        )}
      </div>
    </>
  );
}
