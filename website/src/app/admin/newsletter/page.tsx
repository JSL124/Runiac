import { NewsletterConsole } from "@/components/admin/NewsletterConsole";
import { PageHeader } from "@/components/admin/primitives";
import { getNewsletterCampaigns, getNewsletterSubscribers } from "@/lib/admin/data";

export const dynamic = "force-dynamic";

export default async function AdminNewsletterPage() {
  const [subscribers, campaigns] = await Promise.all([
    getNewsletterSubscribers(),
    getNewsletterCampaigns(),
  ]);

  return (
    <>
      <PageHeader title="Newsletter" />
      <NewsletterConsole subscribers={subscribers} campaigns={campaigns} />
    </>
  );
}
