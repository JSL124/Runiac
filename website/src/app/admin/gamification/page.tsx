import { GamificationRules } from "@/components/admin/GamificationRules";
import { PageHeader } from "@/components/admin/primitives";
import { getProgressionConfig, getProgressionHistory } from "@/lib/admin/data";

export const dynamic = "force-dynamic";

export default async function GamificationPage() {
  const [progressionConfig, history] = await Promise.all([
    getProgressionConfig(),
    getProgressionHistory(),
  ]);

  return (
    <>
      <PageHeader title="XP & Gamification Rules" />
      <GamificationRules
        progressionConfig={progressionConfig}
        history={history}
      />
    </>
  );
}
