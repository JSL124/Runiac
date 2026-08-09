import type { Metadata } from "next";
import type { ReactNode } from "react";
import { redirect } from "next/navigation";
import { AdminSidebar } from "@/components/admin/AdminSidebar";
import { getCurrentUser } from "@/lib/auth";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Runiac Platform Admin",
  description:
    "Control center for the automated Runiac platform. Handle the exceptions the backend cannot.",
};

export default async function AdminLayout({
  children,
}: {
  children: ReactNode;
}) {
  // Auth is checked ONLY through getCurrentUser().isAdmin so the Firebase
  // Auth check stays centralized in one place.
  const { configured, isAdmin, user } = await getCurrentUser();

  if (!configured || !isAdmin) {
    redirect("/login");
  }

  const adminEmail = user?.email ?? "admin";

  return (
    <div className="min-h-dvh bg-brand-soft/30">
      <AdminSidebar adminEmail={adminEmail} />
      <div className="lg:pl-64">
        <main className="mx-auto w-full max-w-6xl px-4 py-6 sm:px-6 sm:py-8 lg:px-8 lg:py-10">
          <div className="space-y-6 sm:space-y-8">{children}</div>
        </main>
      </div>
    </div>
  );
}
