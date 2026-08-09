import { PolicySettings } from "@/components/admin/PolicySettings";
import { PageHeader } from "@/components/admin/primitives";
import {
  getAutomationConfig,
  getChallengeAccessConfig,
  getCharacterAccessConfig,
  getFeatureAccessConfig,
} from "@/lib/admin/data";

export const dynamic = "force-dynamic";

export default async function PoliciesPage() {
  const [
    featureAccessConfig,
    automationConfig,
    challengeAccessConfig,
    characterAccessConfig,
  ] = await Promise.all([
    getFeatureAccessConfig(),
    getAutomationConfig(),
    getChallengeAccessConfig(),
    getCharacterAccessConfig(),
  ]);

  return (
    <>
      <PageHeader title="Automation & Policy Settings" />
      <PolicySettings
        featureAccessConfig={featureAccessConfig}
        automationConfig={automationConfig}
        challengeAccessConfig={challengeAccessConfig}
        characterAccessConfig={characterAccessConfig}
      />
    </>
  );
}
