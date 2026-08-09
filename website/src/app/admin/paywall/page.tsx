import { PaywallConfigEditor } from "@/components/admin/PaywallConfigEditor";
import { PageHeader } from "@/components/admin/primitives";
import { getPaywallConfig, getPaywallHistory } from "@/lib/admin/data";

export const dynamic = "force-dynamic";

export default async function PaywallPage() {
  const [paywallConfig, history] = await Promise.all([
    getPaywallConfig(),
    getPaywallHistory(),
  ]);

  return (
    <>
      <PageHeader title="App Paywall" />
      <PaywallConfigEditor paywallConfig={paywallConfig} history={history} />
    </>
  );
}
