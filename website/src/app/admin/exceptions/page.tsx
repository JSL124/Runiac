import { ExceptionQueue } from "@/components/admin/ExceptionQueue";
import { PageHeader } from "@/components/admin/primitives";
import { getExceptionCases } from "@/lib/admin/data";

export const dynamic = "force-dynamic";

export default async function ExceptionsPage() {
  const cases = await getExceptionCases();

  return (
    <>
      <PageHeader title="Exception Queue" />
      <ExceptionQueue cases={cases} />
    </>
  );
}
