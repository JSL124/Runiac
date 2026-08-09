import type { Metadata } from "next";
import { ForgotPasswordForm } from "@/components/ForgotPasswordForm";
import {
  AuthPageLayout,
  getRandomAuthPhoto,
} from "@/components/AuthPageLayout";
import { hasFirebaseEnv } from "@/lib/firebase/config";

export const metadata: Metadata = {
  title: "Reset your Runiac password",
  description:
    "Send yourself a Runiac password reset link and get back to your running plan, streaks, and XP progress.",
};

export const dynamic = "force-dynamic";

export default function ForgotPasswordPage() {
  return (
    <AuthPageLayout
      photo={getRandomAuthPhoto()}
      panelEyebrow="Account help"
      panelHeading="Back to your running habit in a minute."
      title="Reset your password"
      subtitle="Enter your email and we will send you a link to set a new password."
    >
      <ForgotPasswordForm configured={hasFirebaseEnv()} />
    </AuthPageLayout>
  );
}
