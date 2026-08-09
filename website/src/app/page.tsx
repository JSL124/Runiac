import type { ReactNode } from "react";
import { Footer } from "@/components/Footer";
import { Hero } from "@/components/Hero";
import { JourneyMapHighlight } from "@/components/JourneyMapHighlight";
import { AnnouncementBanner, Navbar } from "@/components/Navbar";
import { PersonalizedPlanHighlight } from "@/components/PersonalizedPlanHighlight";
import { PostRunSummarySection } from "@/components/PostRunSummarySection";
import { PricingSection } from "@/components/PricingSection";
import { Problem } from "@/components/Problem";
import { Solution } from "@/components/Solution";
import { TerritorialLeaderboardSection } from "@/components/TerritorialLeaderboardSection";
import { TestimonialsSection } from "@/components/TestimonialsSection";
import { XpProgressionHighlight } from "@/components/XpProgressionHighlight";
import { getSiteContentWithFallback } from "@/lib/site-content";
import type { SectionTitleKey } from "@/lib/site-section-titles";

export default async function Home() {
  const content = await getSiteContentWithFallback();

  // Registry of the reorderable home-landing sections, keyed by the same
  // SectionTitleKey the admin console drags (config/siteContent.sectionOrder).
  // Only keys present here participate in drag-reordering:
  //   - Hero and the announcement banner are intentionally excluded so they
  //     stay pinned to the top regardless of the stored order.
  //   - Keys that live on their own routes (team -> /about, faq -> /faq) have
  //     no entry, so dragging them in the console has no effect on the home
  //     page.
  const homeSections: Partial<Record<SectionTitleKey, ReactNode>> = {
    problem: <Problem content={content.problem} />,
    testimonials: <TestimonialsSection content={content.testimonials} />,
    solution: <Solution content={content.solution} />,
    personalizedPlan: (
      <PersonalizedPlanHighlight content={content.personalizedPlan} />
    ),
    journeyMap: <JourneyMapHighlight content={content.journeyMap} />,
    xpProgression: <XpProgressionHighlight content={content.xpProgression} />,
    territorial: <TerritorialLeaderboardSection content={content.territorial} />,
    postRunSummary: <PostRunSummarySection content={content.postRunSummary} />,
    pricing: <PricingSection content={content.pricing} />,
  };

  return (
    <>
      <AnnouncementBanner
        enabled={content.announcement.enabled}
        text={content.announcement.text}
      />
      <Navbar />
      <main className="flex flex-1 flex-col">
        <Hero headline={content.hero.headline} subtext={content.hero.subtext} />
        {content.sectionOrder
          .filter((key) => key in homeSections)
          .map((key) => (
            <div key={key}>{homeSections[key]}</div>
          ))}
      </main>
      <Footer />
    </>
  );
}
