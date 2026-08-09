import { FeedbackInbox } from "@/components/admin/FeedbackInbox";
import { PageHeader } from "@/components/admin/primitives";
import { getFeedbackItems } from "@/lib/admin/data";

export const dynamic = "force-dynamic";

export default async function FeedbackPage() {
  const items = await getFeedbackItems();

  return (
    <>
      <PageHeader title="Feedback & Complaints" />
      <FeedbackInbox items={items} />
    </>
  );
}
