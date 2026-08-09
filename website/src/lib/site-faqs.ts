// Canonical schema, defaults, and deep-merge for the marketing site's
// admin-editable FAQ section (config/siteContent.faqs).
//
// Pure module (no Firebase / server imports) so it is shared by the marketing
// render layer (src/lib/site-content.ts, src/app/faq/page.tsx) and the admin
// console model — mirrors the shape of src/lib/site-testimonials.ts.
//
// The admin console stores FAQs as a flat { id, question, answer } list
// (see ContentEditor.tsx / SiteContentFaqRow), so the public render model is a
// matching flat SiteFaq[] list. DEFAULT_SITE_FAQS renders meaningful content
// when config/siteContent is unseeded, partial, or malformed;
// mergeSiteFaqs() falls back to these defaults whenever no valid entry exists.

export type SiteFaq = {
  question: string;
  answer: string;
};

export const DEFAULT_SITE_FAQS: SiteFaq[] = [
  {
    question: "What is Runiac?",
    answer:
      "Runiac is a behavior-change running app built for beginners. Instead of only tracking distance and pace, it helps you stay consistent through personalized plans, streaks, XP, post-run summaries, and fair level-based competition.",
  },
  {
    question: "Is Runiac good for people who have never run before?",
    answer:
      "Yes. Runiac is designed beginner-first. Plans start from your current fitness level and progress gradually, so running feels achievable before it feels competitive.",
  },
  {
    question: "Do I need any special equipment?",
    answer:
      "No. You just need your phone and a pair of running shoes. Runiac uses your phone's GPS to track your runs during a session.",
  },
  {
    question: "How does Runiac build my plan?",
    answer:
      "Runiac uses your goal, fitness level, running experience, and recent activity to create a weekly plan that balances running days, rest days, and realistic progression.",
  },
  {
    question: "How do XP and levels work?",
    answer:
      "You earn XP for completing runs and following your plan. XP is calculated on Runiac's servers so progression is consistent and trustworthy — the app only ever displays values it reads back.",
  },
  {
    question: "What are streaks?",
    answer:
      "Streaks reward regular effort. Keeping your streak alive with even one relaxed run helps build the habit that makes running stick.",
  },
  {
    question: "How are the leaderboards fair?",
    answer:
      "Runiac uses level-based territorial leaderboards, so you compete with runners at a similar level. Progress feels achievable instead of intimidating.",
  },
  {
    question: "Does paying give me a competitive advantage?",
    answer:
      "No. Premium unlocks additional features, but never a competitive edge. Premium users get no extra XP, rank, or leaderboard benefit — competition stays fair for everyone.",
  },
  {
    question: "How much does Runiac cost?",
    answer:
      "Runiac has a Basic tier and a Premium tier. See the Pricing page for the current plans and what each tier includes.",
  },
  {
    question: "How do I create an account?",
    answer:
      "Sign in from the top of any page to create your account. Once you're in, Runiac walks you through a short onboarding to build your first plan.",
  },
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// A stored FAQ list is used only when it is an array with at least one
// well-formed { question, answer } entry; otherwise it falls back to the
// default list. Malformed or blank entries within an otherwise valid array are
// dropped rather than rendered empty.
export function mergeSiteFaqs(raw: unknown): SiteFaq[] {
  if (!Array.isArray(raw)) {
    return DEFAULT_SITE_FAQS;
  }

  const cleaned = raw
    .filter(isRecord)
    .map((entry) => ({
      question: typeof entry.question === "string" ? entry.question : "",
      answer: typeof entry.answer === "string" ? entry.answer : "",
    }))
    .filter(
      (entry) =>
        entry.question.trim().length > 0 && entry.answer.trim().length > 0,
    );

  return cleaned.length > 0 ? cleaned : DEFAULT_SITE_FAQS;
}
