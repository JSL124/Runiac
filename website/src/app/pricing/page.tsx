import type { Metadata } from "next";
import { Navbar } from "@/components/Navbar";
import { PricingSection } from "@/components/PricingSection";
import { getSiteContentWithFallback } from "@/lib/site-content";

export const metadata: Metadata = {
  title: "Runiac Pricing - Free and Premium plans.",
  description:
    "Compare Runiac Free and Premium plans for beginner running consistency, progress insights, milestone preparation, and fair competition.",
};

export default async function PricingPage() {
  const content = await getSiteContentWithFallback();

  return (
    <>
      <Navbar />
      <main className="flex flex-1 flex-col">
        <PricingSection showIntro={false} content={content.pricing} />
      </main>
    </>
  );
}
