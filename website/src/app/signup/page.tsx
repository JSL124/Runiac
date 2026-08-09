import type { Metadata } from "next";
import {
  AuthPageLayout,
  getRandomAuthPhoto,
} from "@/components/AuthPageLayout";
import { SignUpForm } from "@/components/SignUpForm";
import { hasFirebaseEnv, hasGoogleSignInEnv } from "@/lib/firebase/config";

export const metadata: Metadata = {
  title: "Create your Runiac account - From first run to consistent runner.",
  description:
    "Create a Runiac account for beginner runners, then finish onboarding in the app to get your first safe running plan.",
};

export const dynamic = "force-dynamic";

export default function SignUpPage() {
  return (
    <AuthPageLayout
      photo={getRandomAuthPhoto()}
      panelEyebrow="New here"
      panelHeading="From first run to consistent runner."
      title="Create your account"
      subtitle="No pressure. Start at your own pace - the app sets up your plan once you sign in."
    >
      <SignUpForm
        configured={hasFirebaseEnv()}
        googleConfigured={hasGoogleSignInEnv()}
      />
    </AuthPageLayout>
  );
}
