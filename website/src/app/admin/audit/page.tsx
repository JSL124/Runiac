import { AuditLog } from "@/components/admin/AuditLog";
import { PageHeader } from "@/components/admin/primitives";
import { getAuditLog } from "@/lib/admin/data";

export const dynamic = "force-dynamic";

export default async function AuditPage() {
  const entries = await getAuditLog();

  return (
    <>
      <PageHeader title="Governance & Audit Log" />
      <AuditLog entries={entries} />
    </>
  );
}
