import { getSiteContent } from "@/lib/firebase/firestore";
import {
  DEFAULT_SITE_PRICING,
  mergeSitePricing,
  type SitePricing,
} from "@/lib/site-pricing";
import {
  DEFAULT_SITE_TESTIMONIALS,
  mergeSiteTestimonials,
  type SiteTestimonials,
} from "@/lib/site-testimonials";
import {
  DEFAULT_SITE_PROBLEM,
  mergeSiteProblem,
  type SiteProblem,
} from "@/lib/site-problem";
import {
  DEFAULT_SITE_SOLUTION,
  mergeSiteSolution,
  type SiteSolution,
} from "@/lib/site-solution";
import {
  DEFAULT_SITE_PERSONALIZED_PLAN,
  mergeSitePersonalizedPlan,
  type SitePersonalizedPlan,
} from "@/lib/site-personalized-plan";
import {
  DEFAULT_SITE_JOURNEY_MAP,
  DEFAULT_SITE_XP_PROGRESSION,
  DEFAULT_SITE_TERRITORIAL,
  DEFAULT_SITE_POST_RUN_SUMMARY,
  mergeSiteJourneyMap,
  mergeSiteXpProgression,
  mergeSiteTerritorial,
  mergeSitePostRunSummary,
  type SiteHighlight,
  type SitePostRunSummary,
} from "@/lib/site-highlight";
import {
  DEFAULT_SITE_FAQS,
  mergeSiteFaqs,
  type SiteFaq,
} from "@/lib/site-faqs";
import {
  DEFAULT_SECTION_ORDER,
  mergeSectionOrder,
  type SectionTitleKey,
} from "@/lib/site-section-titles";
import { DEFAULT_SITE_TEAM, mergeSiteTeam, type SiteTeam } from "@/lib/site-team";
import {
  DEFAULT_SITE_DOCUMENTS,
  mergeSiteDocuments,
  type SiteDocuments,
} from "@/lib/site-documents";
import {
  DEFAULT_SITE_DOWNLOAD,
  mergeSiteDownload,
  type SiteDownload,
} from "@/lib/site-download";

// Server-read+fallback wrapper for the marketing site's admin-editable copy
// (mirrors the guard/fallback shape of src/lib/meeting-minutes.ts). Callers
// always get a fully-populated SiteContent object: when config/siteContent
// is absent (not yet configured by an admin) or the Firestore read throws,
// this degrades to the literals that used to be hard-coded directly in the
// marketing components, so the rendered page is unchanged either way.

export type { SitePricing, SitePricingTier } from "@/lib/site-pricing";
export type {
  SiteTestimonial,
  SiteTestimonials,
} from "@/lib/site-testimonials";
export type { SiteProblem, ProblemChartPoint } from "@/lib/site-problem";
export type { SiteSolution } from "@/lib/site-solution";
export type { SitePersonalizedPlan } from "@/lib/site-personalized-plan";
export type { SiteHighlight, SitePostRunSummary } from "@/lib/site-highlight";
export type { SiteFaq } from "@/lib/site-faqs";
export type { SectionTitleKey } from "@/lib/site-section-titles";
export type {
  SiteTeam,
  SiteTeamMember,
  SiteTeamSupervisor,
} from "@/lib/site-team";
export type { SiteDocuments, SiteDocumentCard } from "@/lib/site-documents";
export type { SiteDownload, SiteDownloadStep } from "@/lib/site-download";

export type SiteContent = {
  hero: {
    headline: string;
    subtext: string;
  };
  problem: SiteProblem;
  solution: SiteSolution;
  personalizedPlan: SitePersonalizedPlan;
  journeyMap: SiteHighlight;
  xpProgression: SiteHighlight;
  territorial: SiteHighlight;
  postRunSummary: SitePostRunSummary;
  pricing: SitePricing;
  testimonials: SiteTestimonials;
  team: SiteTeam;
  faqs: SiteFaq[];
  documents: SiteDocuments;
  download: SiteDownload;
  // Admin-dragged top-to-bottom order of the home landing page's stacked
  // sections (config/siteContent.sectionOrder). The home page walks this to
  // decide render order; keys that live on their own routes (team, faq) or
  // are pinned (hero, announcement) are simply skipped by the render registry.
  sectionOrder: SectionTitleKey[];
  announcement: {
    enabled: boolean;
    text: string;
  };
};

// The hero currently renders its headline as two literal spans rather than a
// single sentence; \n splits the fallback (and any admin-edited value) into
// those lines.
const FALLBACK_HERO_HEADLINE = "Run consistent,\nRun together.";
const FALLBACK_HERO_SUBTEXT = "";

function getFallbackSiteContent(): SiteContent {
  return {
    hero: {
      headline: FALLBACK_HERO_HEADLINE,
      subtext: FALLBACK_HERO_SUBTEXT,
    },
    problem: DEFAULT_SITE_PROBLEM,
    solution: DEFAULT_SITE_SOLUTION,
    personalizedPlan: DEFAULT_SITE_PERSONALIZED_PLAN,
    journeyMap: DEFAULT_SITE_JOURNEY_MAP,
    xpProgression: DEFAULT_SITE_XP_PROGRESSION,
    territorial: DEFAULT_SITE_TERRITORIAL,
    postRunSummary: DEFAULT_SITE_POST_RUN_SUMMARY,
    pricing: DEFAULT_SITE_PRICING,
    testimonials: DEFAULT_SITE_TESTIMONIALS,
    team: DEFAULT_SITE_TEAM,
    faqs: DEFAULT_SITE_FAQS,
    documents: DEFAULT_SITE_DOCUMENTS,
    download: DEFAULT_SITE_DOWNLOAD,
    sectionOrder: DEFAULT_SECTION_ORDER,
    announcement: {
      enabled: false,
      text: "",
    },
  };
}

export async function getSiteContentWithFallback(): Promise<SiteContent> {
  const fallback = getFallbackSiteContent();

  try {
    const row = await getSiteContent();

    if (!row) {
      return fallback;
    }

    return {
      hero: {
        headline: row.heroHeadline ?? fallback.hero.headline,
        subtext: row.heroSubtext ?? fallback.hero.subtext,
      },
      // Problem section (heading/body/source + drop-off chart) deep-merged over
      // the Problem.tsx defaults, so a missing/partial/malformed document still
      // renders the same section.
      problem: mergeSiteProblem(row.problem),
      // Solution section (heading/body/benefits/CTA label) deep-merged over the
      // Solution.tsx defaults.
      solution: mergeSiteSolution(row.solution),
      // Personalized-plan marketing section (text + optional screenshot image);
      // empty imageSrc keeps the built-in illustration.
      personalizedPlan: mergeSitePersonalizedPlan(row.personalizedPlan),
      // Split-highlight marketing sections (text + optional screenshot); empty
      // imageSrc keeps each built-in illustration.
      journeyMap: mergeSiteJourneyMap(row.journeyMap),
      xpProgression: mergeSiteXpProgression(row.xpProgression),
      territorial: mergeSiteTerritorial(row.territorial),
      postRunSummary: mergeSitePostRunSummary(row.postRunSummary),
      // Structured pricing is deep-merged per field over the literal defaults:
      // any field the admin has not (validly) set falls back to what used to
      // be hard-coded in PricingSection, so a missing/partial/malformed
      // config/siteContent.pricing renders exactly the same page as before.
      pricing: mergeSitePricing(row.pricing),
      // Testimonials are deep-merged per field over the defaults (the community
      // quotes that used to live in Problem.tsx), so a missing/partial/malformed
      // config/siteContent.testimonials still renders meaningful content.
      testimonials: mergeSiteTestimonials(row.testimonials),
      // About-page team section (heading + member cards + supervisor), edited in
      // the admin console. Deep-merged over the defaults that used to live in
      // src/lib/team.ts, so a missing/partial/malformed doc renders the same
      // About page as before.
      team: mergeSiteTeam(row.team),
      // FAQ list (config/siteContent.faqs) edited in the admin console. Each
      // stored { question, answer } entry is validated; a missing/empty/
      // malformed list falls back to the built-in DEFAULT_SITE_FAQS so the FAQ
      // page always renders meaningful content.
      faqs: mergeSiteFaqs(row.faqs),
      // Documents-page content (heading + intro + document cards), edited in
      // the admin console. Deep-merged over the defaults that used to live in
      // src/app/documents/page.tsx, so a missing/partial/malformed doc renders
      // the same Documents page as before.
      documents: mergeSiteDocuments(row.documents),
      // Download-page content (Android/iOS cards, install steps, system
      // requirements), edited in the admin console. Deep-merged over the
      // defaults that used to live in src/app/download/page.tsx.
      download: mergeSiteDownload(row.download),
      // Section order dragged in the admin console. mergeSectionOrder always
      // returns a complete, valid permutation of the known keys, so the home
      // page can walk it safely even if the stored value is partial/malformed.
      sectionOrder: mergeSectionOrder(row.sectionOrder),
      announcement: {
        enabled: row.announcementEnabled ?? fallback.announcement.enabled,
        text: row.announcementText ?? fallback.announcement.text,
      },
    };
  } catch {
    return fallback;
  }
}
