import type { Metadata } from "next";
import {
  AuthPageLayout,
  getRandomAuthPhoto,
} from "@/components/AuthPageLayout";
import { LoginForm } from "@/components/LoginForm";
import { hasFirebaseEnv, hasGoogleSignInEnv } from "@/lib/firebase/config";

export const metadata: Metadata = {
  title: "Sign in to Runiac - Keep your running habit going.",
  description:
    "A Runiac sign-in UI for beginner runners returning to their running plan, streaks, XP progress, and supportive feedback.",
};

export const dynamic = "force-dynamic";

export default function LoginPage() {
  return (
    <AuthPageLayout
      photo={getRandomAuthPhoto()}
      panelEyebrow="Welcome back"
      panelHeading="Keep your running habit going."
      title="Sign in"
      subtitle="Let us keep your running habit going."
    >
      <LoginForm
        configured={hasFirebaseEnv()}
        googleConfigured={hasGoogleSignInEnv()}
      />
    </AuthPageLayout>
  );
}
