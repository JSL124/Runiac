import { ContentEditor } from "@/components/admin/ContentEditor";
import { PageHeader } from "@/components/admin/primitives";
import { getWebsiteContent } from "@/lib/admin/data";

export const dynamic = "force-dynamic";

export default async function ContentPage() {
  const content = await getWebsiteContent();

  return (
    <>
      <PageHeader title="Website Content" />
      <ContentEditor content={content} />
    </>
  );
}
