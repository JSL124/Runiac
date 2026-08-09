"use client";

import { useRef, useState, type ReactNode } from "react";
import {
  btnBrand,
  btnDanger,
  btnSecondary,
  inputBase,
} from "@/components/admin/button-styles";
import { IphoneFrame } from "@/components/IphoneFrame";
import { saveSiteContent } from "@/lib/actions/admin";
import type {
  FaqEntry,
  ProblemChartPoint,
  SectionTitleKey,
  SiteDocumentCard,
  SiteDownloadStep,
  SiteHighlight,
  SitePricing,
  SiteTeamMember,
  SiteTeamSupervisor,
  SiteTestimonial,
  WebsiteContent,
} from "@/lib/admin/types";

const fieldLabel =
  "text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted";
const textarea = `${inputBase} h-auto py-2 leading-relaxed`;

type BillingCycle = "monthly" | "annual";

// Top-level page tabs: the editor is organized by the marketing site's nav
// destination (rather than one long flat list of sections) so an admin editing
// e.g. the Download page doesn't have to scroll past unrelated Home sections.
const PAGE_TABS: { id: string; label: string }[] = [
  { id: "home", label: "Home" },
  { id: "pricing", label: "Pricing" },
  { id: "faq", label: "FAQ" },
  { id: "documents", label: "Documents" },
  { id: "download", label: "Download" },
  { id: "about", label: "About" },
  { id: "sitewide", label: "Site-wide" },
];

export function ContentEditor({ content }: { content: WebsiteContent }) {
  const [draft, setDraft] = useState<WebsiteContent>(content);
  const [staged, setStaged] = useState(false);
  const [savedNote, setSavedNote] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [savedLive, setSavedLive] = useState(false);
  // Which nav-tab page's sections are currently shown.
  const [activePage, setActivePage] = useState<string>("home");
  // Single-open accordion: only one section is expanded at a time so the long
  // form collapses to a short list of headers. First section opens by default.
  const [openSection, setOpenSection] = useState<string | null>("announcement");
  // Monotonic source of unique ids for newly added FAQ entries (event-handler
  // only — never mutated during render).
  const faqCounterRef = useRef(0);

  function toggleSection(id: string) {
    setOpenSection((current) => (current === id ? null : id));
  }

  // --- drag-to-reorder (admin display order only) ---------------------------
  const [dragKey, setDragKey] = useState<SectionTitleKey | null>(null);
  const [dragOverKey, setDragOverKey] = useState<SectionTitleKey | null>(null);

  function moveSection(fromKey: SectionTitleKey, toKey: SectionTitleKey) {
    if (fromKey === toKey) return;
    const order = [...draft.sectionOrder];
    const from = order.indexOf(fromKey);
    const to = order.indexOf(toKey);
    if (from < 0 || to < 0) return;
    order.splice(from, 1);
    order.splice(to, 0, fromKey);
    update("sectionOrder", order);
  }

  // Feeds each AccordionSection its (renameable) label, a persisted rename
  // handler (writes config/siteContent.sectionTitles), its flex `order`, and
  // the drag handlers that reorder config/siteContent.sectionOrder.
  function sectionTitleProps(key: SectionTitleKey) {
    return {
      title: draft.sectionTitles[key],
      onTitleChange: (value: string) =>
        update("sectionTitles", { ...draft.sectionTitles, [key]: value }),
      order: draft.sectionOrder.indexOf(key),
      dragging: dragKey === key,
      dragOver: dragOverKey === key && dragKey !== null && dragKey !== key,
      onDragStart: () => setDragKey(key),
      onDragEnd: () => {
        setDragKey(null);
        setDragOverKey(null);
      },
      onDragOverItem: () => {
        if (dragKey && dragKey !== key) setDragOverKey(key);
      },
      onDropItem: () => {
        if (dragKey) moveSection(dragKey, key);
        setDragKey(null);
        setDragOverKey(null);
      },
    };
  }

  function update<K extends keyof WebsiteContent>(
    key: K,
    value: WebsiteContent[K],
  ) {
    setDraft((prev) => ({ ...prev, [key]: value }));
    setStaged(true);
    setSavedNote(false);
  }

  // --- structured pricing editors -------------------------------------------

  function updateFreeField(key: keyof SitePricing["free"], value: string) {
    update("pricing", {
      ...draft.pricing,
      free: { ...draft.pricing.free, [key]: value },
    });
  }

  function updatePremiumField(
    key: "badge" | "title" | "subtitle" | "ctaLabel",
    value: string,
  ) {
    update("pricing", {
      ...draft.pricing,
      premium: { ...draft.pricing.premium, [key]: value },
    });
  }

  function updatePremiumTier(
    cycle: BillingCycle,
    key: "price" | "period" | "note",
    value: string,
  ) {
    update("pricing", {
      ...draft.pricing,
      premium: {
        ...draft.pricing.premium,
        premiumPrice: {
          ...draft.pricing.premium.premiumPrice,
          [cycle]: {
            ...draft.pricing.premium.premiumPrice[cycle],
            [key]: value,
          },
        },
      },
    });
  }

  function updateTierFeature(
    tier: "free" | "premium",
    index: number,
    value: string,
  ) {
    const features = draft.pricing[tier].features.map((feature, i) =>
      i === index ? value : feature,
    );
    update("pricing", {
      ...draft.pricing,
      [tier]: { ...draft.pricing[tier], features },
    });
  }

  function addTierFeature(tier: "free" | "premium") {
    update("pricing", {
      ...draft.pricing,
      [tier]: {
        ...draft.pricing[tier],
        features: [...draft.pricing[tier].features, ""],
      },
    });
  }

  function removeTierFeature(tier: "free" | "premium", index: number) {
    update("pricing", {
      ...draft.pricing,
      [tier]: {
        ...draft.pricing[tier],
        features: draft.pricing[tier].features.filter((_, i) => i !== index),
      },
    });
  }

  // --- problem editors ------------------------------------------------------

  function updateProblemField(
    key: "eyebrow" | "heading" | "body" | "source" | "chartTitle",
    value: string,
  ) {
    update("problem", { ...draft.problem, [key]: value });
  }

  function updateChartPoint(
    index: number,
    key: keyof ProblemChartPoint,
    value: string,
  ) {
    update("problem", {
      ...draft.problem,
      chartPoints: draft.problem.chartPoints.map((point, i) =>
        i === index
          ? {
              ...point,
              [key]: key === "value" ? Number(value) : value,
            }
          : point,
      ),
    });
  }

  function addChartPoint() {
    update("problem", {
      ...draft.problem,
      chartPoints: [...draft.problem.chartPoints, { label: "", value: 0 }],
    });
  }

  function removeChartPoint(index: number) {
    update("problem", {
      ...draft.problem,
      chartPoints: draft.problem.chartPoints.filter((_, i) => i !== index),
    });
  }

  // --- solution editors -----------------------------------------------------

  function updateSolutionField(
    key: "eyebrow" | "heading" | "body" | "ctaLabel",
    value: string,
  ) {
    update("solution", { ...draft.solution, [key]: value });
  }

  function updateBenefit(index: number, value: string) {
    update("solution", {
      ...draft.solution,
      benefits: draft.solution.benefits.map((benefit, i) =>
        i === index ? value : benefit,
      ),
    });
  }

  function addBenefit() {
    update("solution", {
      ...draft.solution,
      benefits: [...draft.solution.benefits, ""],
    });
  }

  function removeBenefit(index: number) {
    update("solution", {
      ...draft.solution,
      benefits: draft.solution.benefits.filter((_, i) => i !== index),
    });
  }

  // --- personalized plan editors --------------------------------------------

  function updatePersonalizedPlanField(
    key: "eyebrow" | "heading" | "body" | "ctaLabel" | "imageSrc" | "imageAlt",
    value: string,
  ) {
    update("personalizedPlan", { ...draft.personalizedPlan, [key]: value });
  }

  // --- testimonials editors -------------------------------------------------

  function updateTestimonialsField(
    key: "title" | "subtitle",
    value: string,
  ) {
    update("testimonials", { ...draft.testimonials, [key]: value });
  }

  function updateTestimonial(
    index: number,
    key: keyof SiteTestimonial,
    value: string,
  ) {
    update("testimonials", {
      ...draft.testimonials,
      items: draft.testimonials.items.map((item, i) =>
        i === index ? { ...item, [key]: value } : item,
      ),
    });
  }

  function addTestimonial() {
    update("testimonials", {
      ...draft.testimonials,
      items: [
        ...draft.testimonials.items,
        { quote: "", authorName: "", authorTitle: "" },
      ],
    });
  }

  function removeTestimonial(index: number) {
    update("testimonials", {
      ...draft.testimonials,
      items: draft.testimonials.items.filter((_, i) => i !== index),
    });
  }

  function updateFaq(id: string, key: keyof FaqEntry, value: string) {
    update(
      "faqs",
      draft.faqs.map((faq) => (faq.id === id ? { ...faq, [key]: value } : faq)),
    );
  }

  function addFaq() {
    faqCounterRef.current += 1;
    update("faqs", [
      ...draft.faqs,
      { id: `faq-new-${faqCounterRef.current}`, question: "", answer: "" },
    ]);
  }

  function removeFaq(id: string) {
    update(
      "faqs",
      draft.faqs.filter((faq) => faq.id !== id),
    );
  }

  // --- About-page team section (config/siteContent.team) ---------------------
  function updateTeamField(
    key: "eyebrow" | "heading" | "body" | "supervisorLabel",
    value: string,
  ) {
    update("team", { ...draft.team, [key]: value });
  }

  function updateMember(
    index: number,
    key: keyof SiteTeamMember,
    value: string,
  ) {
    update("team", {
      ...draft.team,
      members: draft.team.members.map((member, i) =>
        i === index ? { ...member, [key]: value } : member,
      ),
    });
  }

  function addMember() {
    update("team", {
      ...draft.team,
      members: [
        ...draft.team.members,
        {
          name: "",
          role: "",
          bio: "",
          photo: "",
          github: "",
          linkedin: "",
          email: "",
        },
      ],
    });
  }

  function removeMember(index: number) {
    update("team", {
      ...draft.team,
      members: draft.team.members.filter((_, i) => i !== index),
    });
  }

  function updateSupervisor(key: keyof SiteTeamSupervisor, value: string) {
    update("team", {
      ...draft.team,
      supervisor: { ...draft.team.supervisor, [key]: value },
    });
  }

  // --- Documents page (config/siteContent.documents) ------------------------

  function updateDocumentCard(
    index: number,
    field: keyof SiteDocumentCard,
    value: string,
  ) {
    update("documents", {
      ...draft.documents,
      cards: draft.documents.cards.map((card, i) =>
        i === index ? { ...card, [field]: value } : card,
      ),
    });
  }

  function addDocumentCard() {
    update("documents", {
      ...draft.documents,
      cards: [...draft.documents.cards, { title: "", status: "", body: "" }],
    });
  }

  function removeDocumentCard(index: number) {
    update("documents", {
      ...draft.documents,
      cards: draft.documents.cards.filter((_, i) => i !== index),
    });
  }

  // --- Download page (config/siteContent.download) --------------------------

  function updateDownloadStep(
    index: number,
    field: keyof SiteDownloadStep,
    value: string,
  ) {
    update("download", {
      ...draft.download,
      steps: draft.download.steps.map((step, i) =>
        i === index ? { ...step, [field]: value } : step,
      ),
    });
  }

  function addDownloadStep() {
    update("download", {
      ...draft.download,
      steps: [...draft.download.steps, { title: "", body: "" }],
    });
  }

  function removeDownloadStep(index: number) {
    update("download", {
      ...draft.download,
      steps: draft.download.steps.filter((_, i) => i !== index),
    });
  }

  function updateDownloadRequirement(index: number, value: string) {
    update("download", {
      ...draft.download,
      requirements: draft.download.requirements.map((requirement, i) =>
        i === index ? value : requirement,
      ),
    });
  }

  function addDownloadRequirement() {
    update("download", {
      ...draft.download,
      requirements: [...draft.download.requirements, ""],
    });
  }

  function removeDownloadRequirement(index: number) {
    update("download", {
      ...draft.download,
      requirements: draft.download.requirements.filter((_, i) => i !== index),
    });
  }

  async function save() {
    setSaving(true);
    setSaveError(null);
    setSavedNote(false);

    const result = await saveSiteContent(draft);

    setSaving(false);

    if (!result.ok) {
      setSaveError(result.error);
      return;
    }

    setStaged(false);
    setSavedNote(true);
    setSavedLive(result.live);
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap gap-2">
        {PAGE_TABS.map((tab) => (
          <button
            key={tab.id}
            type="button"
            onClick={() => setActivePage(tab.id)}
            aria-current={activePage === tab.id ? "page" : undefined}
            className={`rounded-lg px-3 py-2 text-sm font-semibold transition-colors duration-150 ${
              activePage === tab.id
                ? "bg-brand text-white"
                : "text-foreground hover:bg-brand-soft/70"
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <div className="flex flex-col gap-6">
      {activePage === "sitewide" && (
      <AccordionSection
        {...sectionTitleProps("announcement")}
        badge={
          <StatusPill tone={draft.announcementEnabled ? "on" : "off"}>
            {draft.announcementEnabled ? "On" : "Off"}
          </StatusPill>
        }
        open={openSection === "announcement"}
        onToggle={() => toggleSection("announcement")}
      >
        <label className="flex items-center justify-between gap-3 rounded-lg border border-border p-3">
          <span className="text-sm font-semibold text-foreground">
            Show announcement banner
          </span>
          <input
            type="checkbox"
            checked={draft.announcementEnabled}
            onChange={() =>
              update("announcementEnabled", !draft.announcementEnabled)
            }
            className="h-4 w-4 accent-[#001e62]"
          />
        </label>
        <label className="mt-3 block">
          <span className={fieldLabel}>Banner text</span>
          <input
            type="text"
            value={draft.announcementText}
            onChange={(event) => update("announcementText", event.target.value)}
            className={`${inputBase} mt-1`}
          />
        </label>
      </AccordionSection>
      )}

      {activePage === "home" && (
      <AccordionSection
        {...sectionTitleProps("hero")}
        open={openSection === "hero"}
        onToggle={() => toggleSection("hero")}
      >
        <div className="space-y-3">
          <label className="block">
            <span className={fieldLabel}>Headline</span>
            <input
              type="text"
              value={draft.heroHeadline}
              onChange={(event) => update("heroHeadline", event.target.value)}
              className={`${inputBase} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>Subtext</span>
            <textarea
              rows={2}
              value={draft.heroSubtext}
              onChange={(event) => update("heroSubtext", event.target.value)}
              className={`${textarea} mt-1`}
            />
          </label>
        </div>
      </AccordionSection>
      )}

      {activePage === "home" && (
      <AccordionSection
        {...sectionTitleProps("problem")}
        open={openSection === "problem"}
        onToggle={() => toggleSection("problem")}
      >
        <p className="text-xs text-muted">
          The &ldquo;Most beginners stop&rdquo; block at the top of the home
          page, including the Early Drop-off chart. The two photographs are fixed.
        </p>
        <div className="mt-4 space-y-3">
          <label className="block">
            <span className={fieldLabel}>Eyebrow</span>
            <input
              type="text"
              value={draft.problem.eyebrow}
              onChange={(event) =>
                updateProblemField("eyebrow", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>Heading</span>
            <input
              type="text"
              value={draft.problem.heading}
              onChange={(event) =>
                updateProblemField("heading", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>Body</span>
            <textarea
              rows={3}
              value={draft.problem.body}
              onChange={(event) =>
                updateProblemField("body", event.target.value)
              }
              className={`${textarea} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>Source line</span>
            <input
              type="text"
              value={draft.problem.source}
              onChange={(event) =>
                updateProblemField("source", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
        </div>

        <div className="mt-5 rounded-lg border border-border p-4">
          <div className="flex items-center justify-between gap-3">
            <h3 className="text-sm font-bold text-foreground">
              Early Drop-off chart
            </h3>
            <button
              type="button"
              className={btnSecondary}
              onClick={addChartPoint}
            >
              Add point
            </button>
          </div>
          <label className="mt-3 block">
            <span className={fieldLabel}>Chart title</span>
            <input
              type="text"
              value={draft.problem.chartTitle}
              onChange={(event) =>
                updateProblemField("chartTitle", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <div className="mt-3 space-y-2">
            {draft.problem.chartPoints.map((point, index) => (
              <div key={index} className="flex items-end gap-2">
                <label className="min-w-0 flex-1">
                  <span className={fieldLabel}>Label</span>
                  <input
                    type="text"
                    value={point.label}
                    onChange={(event) =>
                      updateChartPoint(index, "label", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
                <label className="w-28 shrink-0">
                  <span className={fieldLabel}>Value %</span>
                  <input
                    type="number"
                    min={0}
                    max={100}
                    step="0.1"
                    value={point.value}
                    onChange={(event) =>
                      updateChartPoint(index, "value", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
                <button
                  type="button"
                  className={btnDanger}
                  onClick={() => removeChartPoint(index)}
                >
                  Remove
                </button>
              </div>
            ))}
          </div>
        </div>
      </AccordionSection>
      )}

      {activePage === "home" && (
      <AccordionSection
        {...sectionTitleProps("solution")}
        open={openSection === "solution"}
        onToggle={() => toggleSection("solution")}
      >
        <p className="text-xs text-muted">
          The &ldquo;Built to keep beginners consistent&rdquo; block. The
          photograph and the CTA link target are fixed; the CTA label is editable.
        </p>
        <div className="mt-4 space-y-3">
          <label className="block">
            <span className={fieldLabel}>Eyebrow</span>
            <input
              type="text"
              value={draft.solution.eyebrow}
              onChange={(event) =>
                updateSolutionField("eyebrow", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>Heading</span>
            <input
              type="text"
              value={draft.solution.heading}
              onChange={(event) =>
                updateSolutionField("heading", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>Body</span>
            <textarea
              rows={3}
              value={draft.solution.body}
              onChange={(event) =>
                updateSolutionField("body", event.target.value)
              }
              className={`${textarea} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>CTA button label</span>
            <input
              type="text"
              value={draft.solution.ctaLabel}
              onChange={(event) =>
                updateSolutionField("ctaLabel", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <FeatureListEditor
            label="Benefits"
            features={draft.solution.benefits}
            onChange={(index, value) => updateBenefit(index, value)}
            onAdd={addBenefit}
            onRemove={(index) => removeBenefit(index)}
          />
        </div>
      </AccordionSection>
      )}

      {activePage === "home" && (
      <AccordionSection
        {...sectionTitleProps("personalizedPlan")}
        open={openSection === "personalizedPlan"}
        onToggle={() => toggleSection("personalizedPlan")}
      >
        <p className="text-xs text-muted">
          Marketing section only &mdash; this is a picture of the app, not the
          real app screen, so editing it never changes the app. Set a screenshot
          to mirror the current app; leave it empty to show the built-in
          illustration.
        </p>
        <div className="mt-4 space-y-3">
          <label className="block">
            <span className={fieldLabel}>Eyebrow</span>
            <input
              type="text"
              value={draft.personalizedPlan.eyebrow}
              onChange={(event) =>
                updatePersonalizedPlanField("eyebrow", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>Heading</span>
            <input
              type="text"
              value={draft.personalizedPlan.heading}
              onChange={(event) =>
                updatePersonalizedPlanField("heading", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>Body</span>
            <textarea
              rows={3}
              value={draft.personalizedPlan.body}
              onChange={(event) =>
                updatePersonalizedPlanField("body", event.target.value)
              }
              className={`${textarea} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>CTA button label</span>
            <input
              type="text"
              value={draft.personalizedPlan.ctaLabel}
              onChange={(event) =>
                updatePersonalizedPlanField("ctaLabel", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
        </div>

        <div className="mt-5 rounded-lg border border-border p-4">
          <h3 className="text-sm font-bold text-foreground">
            App screenshot (shown inside an iPhone frame)
          </h3>
          <label className="mt-3 block">
            <span className={fieldLabel}>Image URL or /public path</span>
            <input
              type="text"
              value={draft.personalizedPlan.imageSrc}
              onChange={(event) =>
                updatePersonalizedPlanField("imageSrc", event.target.value)
              }
              placeholder="https://… or /plan-screenshot.png"
              className={`${inputBase} mt-1`}
            />
          </label>
          <p className="mt-1 text-xs text-muted">
            Leave empty to show the built-in illustration. A tall (9:19.5)
            screenshot fits the frame best.
          </p>
          <label className="mt-3 block">
            <span className={fieldLabel}>Image alt text</span>
            <input
              type="text"
              value={draft.personalizedPlan.imageAlt}
              onChange={(event) =>
                updatePersonalizedPlanField("imageAlt", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          {draft.personalizedPlan.imageSrc ? (
            <div className="mt-3">
              <span className={fieldLabel}>Preview</span>
              <div className="relative mt-2 aspect-[1000/2064] w-28">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={draft.personalizedPlan.imageSrc}
                  alt={draft.personalizedPlan.imageAlt}
                  className="absolute left-[2.88%] top-[0.96%] h-[98.06%] w-[94.72%] rounded-[10px] object-cover object-top"
                />
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src="/iphone-frame.png"
                  alt=""
                  aria-hidden="true"
                  className="pointer-events-none absolute inset-0 h-full w-full"
                />
              </div>
            </div>
          ) : null}
        </div>
      </AccordionSection>
      )}

      {activePage === "home" && (
      <AccordionSection
        {...sectionTitleProps("journeyMap")}
        badge={
          draft.journeyMap.imageSrc ? (
            <StatusPill tone="on">Screenshot</StatusPill>
          ) : undefined
        }
        open={openSection === "journeyMap"}
        onToggle={() => toggleSection("journeyMap")}
      >
        <HighlightPanelBody
          value={draft.journeyMap}
          note="The “Every run moves you along the map” adventure-map section (the gamified home screen). Marketing depiction only — this never changes the real app."
          onChange={(patch) =>
            update("journeyMap", { ...draft.journeyMap, ...patch })
          }
        />
      </AccordionSection>
      )}

      {activePage === "home" && (
      <AccordionSection
        {...sectionTitleProps("xpProgression")}
        badge={
          draft.xpProgression.imageSrc ? (
            <StatusPill tone="on">Screenshot</StatusPill>
          ) : undefined
        }
        open={openSection === "xpProgression"}
        onToggle={() => toggleSection("xpProgression")}
      >
        <HighlightPanelBody
          value={draft.xpProgression}
          note="The “Turn every run into XP” section. Marketing depiction only — this never changes the real app."
          onChange={(patch) =>
            update("xpProgression", { ...draft.xpProgression, ...patch })
          }
        />
      </AccordionSection>
      )}

      {activePage === "home" && (
      <AccordionSection
        {...sectionTitleProps("territorial")}
        badge={
          draft.territorial.imageSrc ? (
            <StatusPill tone="on">Screenshot</StatusPill>
          ) : undefined
        }
        open={openSection === "territorial"}
        onToggle={() => toggleSection("territorial")}
      >
        <HighlightPanelBody
          value={draft.territorial}
          note="The “Compete with runners around you” section. Marketing depiction only."
          onChange={(patch) =>
            update("territorial", { ...draft.territorial, ...patch })
          }
        />
      </AccordionSection>
      )}

      {activePage === "home" && (
      <AccordionSection
        {...sectionTitleProps("postRunSummary")}
        badge={
          draft.postRunSummary.imageSrc ? (
            <StatusPill tone="on">Screenshot</StatusPill>
          ) : undefined
        }
        open={openSection === "postRunSummary"}
        onToggle={() => toggleSection("postRunSummary")}
      >
        <HighlightPanelBody
          value={draft.postRunSummary}
          note="The “Understand your run like a story” section. Marketing depiction only."
          onChange={(patch) =>
            update("postRunSummary", { ...draft.postRunSummary, ...patch })
          }
        />
        <label className="mt-4 block">
          <span className={fieldLabel}>Secondary CTA label (pill)</span>
          <input
            type="text"
            value={draft.postRunSummary.ctaSecondaryLabel}
            onChange={(event) =>
              update("postRunSummary", {
                ...draft.postRunSummary,
                ctaSecondaryLabel: event.target.value,
              })
            }
            className={`${inputBase} mt-1`}
          />
        </label>
        <div className="mt-4">
          <FeatureListEditor
            label="Bullet points"
            features={draft.postRunSummary.bullets}
            onChange={(index, value) =>
              update("postRunSummary", {
                ...draft.postRunSummary,
                bullets: draft.postRunSummary.bullets.map((bullet, i) =>
                  i === index ? value : bullet,
                ),
              })
            }
            onAdd={() =>
              update("postRunSummary", {
                ...draft.postRunSummary,
                bullets: [...draft.postRunSummary.bullets, ""],
              })
            }
            onRemove={(index) =>
              update("postRunSummary", {
                ...draft.postRunSummary,
                bullets: draft.postRunSummary.bullets.filter(
                  (_, i) => i !== index,
                ),
              })
            }
          />
        </div>
      </AccordionSection>
      )}

      {activePage === "pricing" && (
      <AccordionSection
        {...sectionTitleProps("pricing")}
        open={openSection === "pricing"}
        onToggle={() => toggleSection("pricing")}
      >
        <p className="text-xs text-muted">
          These fields drive the Free and Premium cards on the live pricing
          page. The Monthly/Annual toggle and the section headers are fixed.
        </p>

        <div className="mt-4 grid gap-5 lg:grid-cols-2">
          {/* Free tier */}
          <div className="rounded-lg border border-border p-4">
            <h3 className="text-sm font-bold text-foreground">Free tier</h3>
            <div className="mt-3 space-y-3">
              <label className="block">
                <span className={fieldLabel}>Badge</span>
                <input
                  type="text"
                  value={draft.pricing.free.badge}
                  onChange={(event) =>
                    updateFreeField("badge", event.target.value)
                  }
                  className={`${inputBase} mt-1`}
                />
              </label>
              <label className="block">
                <span className={fieldLabel}>Title</span>
                <input
                  type="text"
                  value={draft.pricing.free.title}
                  onChange={(event) =>
                    updateFreeField("title", event.target.value)
                  }
                  className={`${inputBase} mt-1`}
                />
              </label>
              <label className="block">
                <span className={fieldLabel}>Subtitle</span>
                <textarea
                  rows={2}
                  value={draft.pricing.free.subtitle}
                  onChange={(event) =>
                    updateFreeField("subtitle", event.target.value)
                  }
                  className={`${textarea} mt-1`}
                />
              </label>
              <div className="grid grid-cols-2 gap-3">
                <label className="block">
                  <span className={fieldLabel}>Price</span>
                  <input
                    type="text"
                    value={draft.pricing.free.price}
                    onChange={(event) =>
                      updateFreeField("price", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
                <label className="block">
                  <span className={fieldLabel}>Price note</span>
                  <input
                    type="text"
                    value={draft.pricing.free.priceNote}
                    onChange={(event) =>
                      updateFreeField("priceNote", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
              </div>
              <FeatureListEditor
                label="Included in Free"
                features={draft.pricing.free.features}
                onChange={(index, value) =>
                  updateTierFeature("free", index, value)
                }
                onAdd={() => addTierFeature("free")}
                onRemove={(index) => removeTierFeature("free", index)}
              />
            </div>
          </div>

          {/* Premium tier */}
          <div className="rounded-lg border border-border p-4">
            <h3 className="text-sm font-bold text-foreground">Premium tier</h3>
            <div className="mt-3 space-y-3">
              <label className="block">
                <span className={fieldLabel}>Badge</span>
                <input
                  type="text"
                  value={draft.pricing.premium.badge}
                  onChange={(event) =>
                    updatePremiumField("badge", event.target.value)
                  }
                  className={`${inputBase} mt-1`}
                />
              </label>
              <label className="block">
                <span className={fieldLabel}>Title</span>
                <input
                  type="text"
                  value={draft.pricing.premium.title}
                  onChange={(event) =>
                    updatePremiumField("title", event.target.value)
                  }
                  className={`${inputBase} mt-1`}
                />
              </label>
              <label className="block">
                <span className={fieldLabel}>Subtitle</span>
                <textarea
                  rows={2}
                  value={draft.pricing.premium.subtitle}
                  onChange={(event) =>
                    updatePremiumField("subtitle", event.target.value)
                  }
                  className={`${textarea} mt-1`}
                />
              </label>

              <TierPriceEditor
                title="Monthly price"
                tier={draft.pricing.premium.premiumPrice.monthly}
                onChange={(key, value) =>
                  updatePremiumTier("monthly", key, value)
                }
              />
              <TierPriceEditor
                title="Annual price"
                tier={draft.pricing.premium.premiumPrice.annual}
                onChange={(key, value) =>
                  updatePremiumTier("annual", key, value)
                }
              />

              <label className="block">
                <span className={fieldLabel}>CTA button label</span>
                <input
                  type="text"
                  value={draft.pricing.premium.ctaLabel}
                  onChange={(event) =>
                    updatePremiumField("ctaLabel", event.target.value)
                  }
                  className={`${inputBase} mt-1`}
                />
              </label>
              <FeatureListEditor
                label="Premium adds"
                features={draft.pricing.premium.features}
                onChange={(index, value) =>
                  updateTierFeature("premium", index, value)
                }
                onAdd={() => addTierFeature("premium")}
                onRemove={(index) => removeTierFeature("premium", index)}
              />
            </div>
          </div>
        </div>
      </AccordionSection>
      )}

      {activePage === "home" && (
      <AccordionSection
        {...sectionTitleProps("testimonials")}
        badge={<CountPill count={draft.testimonials.items.length} />}
        open={openSection === "testimonials"}
        onToggle={() => toggleSection("testimonials")}
      >
        <p className="text-xs text-muted">
          These replace the &ldquo;real problem&rdquo; quote cards on the home
          page. They scroll horizontally in auto-arranged rows; the avatar shows
          the author&rsquo;s initials.
        </p>
        <div className="mt-3 flex justify-end">
          <button
            type="button"
            className={btnSecondary}
            onClick={addTestimonial}
          >
            Add testimonial
          </button>
        </div>
        <div className="mt-4 space-y-3">
          <label className="block">
            <span className={fieldLabel}>Title</span>
            <input
              type="text"
              value={draft.testimonials.title}
              onChange={(event) =>
                updateTestimonialsField("title", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>Subtitle</span>
            <textarea
              rows={2}
              value={draft.testimonials.subtitle}
              onChange={(event) =>
                updateTestimonialsField("subtitle", event.target.value)
              }
              className={`${textarea} mt-1`}
            />
          </label>
        </div>
        <div className="mt-4 space-y-4">
          {draft.testimonials.items.length === 0 ? (
            <p className="text-xs text-muted">No testimonials yet.</p>
          ) : (
            draft.testimonials.items.map((item, index) => (
              <div
                key={index}
                className="rounded-lg border border-border p-3"
              >
                <div className="flex items-center justify-between gap-3">
                  <span className={fieldLabel}>Testimonial {index + 1}</span>
                  <button
                    type="button"
                    className={btnDanger}
                    onClick={() => removeTestimonial(index)}
                  >
                    Remove
                  </button>
                </div>
                <label className="mt-2 block">
                  <span className={fieldLabel}>Quote</span>
                  <textarea
                    rows={2}
                    value={item.quote}
                    onChange={(event) =>
                      updateTestimonial(index, "quote", event.target.value)
                    }
                    className={`${textarea} mt-1`}
                  />
                </label>
                <div className="mt-2 grid gap-3 sm:grid-cols-2">
                  <label className="block">
                    <span className={fieldLabel}>Author name</span>
                    <input
                      type="text"
                      value={item.authorName}
                      onChange={(event) =>
                        updateTestimonial(
                          index,
                          "authorName",
                          event.target.value,
                        )
                      }
                      className={`${inputBase} mt-1`}
                    />
                  </label>
                  <label className="block">
                    <span className={fieldLabel}>Author title</span>
                    <input
                      type="text"
                      value={item.authorTitle}
                      onChange={(event) =>
                        updateTestimonial(
                          index,
                          "authorTitle",
                          event.target.value,
                        )
                      }
                      className={`${inputBase} mt-1`}
                    />
                  </label>
                </div>
              </div>
            ))
          )}
        </div>
      </AccordionSection>
      )}

      {activePage === "about" && (
      <AccordionSection
        {...sectionTitleProps("team")}
        badge={<CountPill count={draft.team.members.length} />}
        open={openSection === "team"}
        onToggle={() => toggleSection("team")}
      >
        <p className="text-xs text-muted">
          The “About us” page team section. Photos are /public paths (e.g.
          /images/team/name.jpg) or https URLs.
        </p>
        <label className="mt-3 block">
          <span className={fieldLabel}>Section eyebrow</span>
          <input
            type="text"
            value={draft.team.eyebrow}
            onChange={(event) => updateTeamField("eyebrow", event.target.value)}
            className={`${inputBase} mt-1`}
          />
        </label>
        <label className="mt-2 block">
          <span className={fieldLabel}>Heading</span>
          <input
            type="text"
            value={draft.team.heading}
            onChange={(event) => updateTeamField("heading", event.target.value)}
            className={`${inputBase} mt-1`}
          />
        </label>
        <label className="mt-2 block">
          <span className={fieldLabel}>Description</span>
          <textarea
            rows={3}
            value={draft.team.body}
            onChange={(event) => updateTeamField("body", event.target.value)}
            className={`${textarea} mt-1`}
          />
        </label>

        <div className="mt-5 flex items-center justify-between">
          <span className={fieldLabel}>Team members</span>
          <button type="button" className={btnSecondary} onClick={addMember}>
            Add member
          </button>
        </div>
        <div className="mt-3 space-y-4">
          {draft.team.members.map((member, index) => (
            <div
              key={index}
              className="rounded-lg border border-border p-3"
            >
              <div className="grid gap-2 sm:grid-cols-2">
                <label className="block">
                  <span className={fieldLabel}>Name</span>
                  <input
                    type="text"
                    value={member.name}
                    onChange={(event) =>
                      updateMember(index, "name", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
                <label className="block">
                  <span className={fieldLabel}>Role</span>
                  <input
                    type="text"
                    value={member.role}
                    onChange={(event) =>
                      updateMember(index, "role", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
              </div>
              <label className="mt-2 block">
                <span className={fieldLabel}>Bio</span>
                <textarea
                  rows={2}
                  value={member.bio}
                  onChange={(event) =>
                    updateMember(index, "bio", event.target.value)
                  }
                  className={`${textarea} mt-1`}
                />
              </label>
              <label className="mt-2 block">
                <span className={fieldLabel}>Photo (/public path or https URL)</span>
                <input
                  type="text"
                  value={member.photo}
                  onChange={(event) =>
                    updateMember(index, "photo", event.target.value)
                  }
                  placeholder="/images/team/name.jpg"
                  className={`${inputBase} mt-1`}
                />
              </label>
              <div className="mt-2 grid gap-2 sm:grid-cols-3">
                <label className="block">
                  <span className={fieldLabel}>GitHub URL</span>
                  <input
                    type="text"
                    value={member.github}
                    onChange={(event) =>
                      updateMember(index, "github", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
                <label className="block">
                  <span className={fieldLabel}>LinkedIn URL</span>
                  <input
                    type="text"
                    value={member.linkedin}
                    onChange={(event) =>
                      updateMember(index, "linkedin", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
                <label className="block">
                  <span className={fieldLabel}>Email</span>
                  <input
                    type="text"
                    value={member.email}
                    onChange={(event) =>
                      updateMember(index, "email", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
              </div>
              <div className="mt-2 flex justify-end">
                <button
                  type="button"
                  className={btnDanger}
                  onClick={() => removeMember(index)}
                >
                  Remove
                </button>
              </div>
            </div>
          ))}
        </div>

        <div className="mt-5 rounded-lg border border-border p-3">
          <span className={fieldLabel}>Supervisor</span>
          <label className="mt-2 block">
            <span className={fieldLabel}>Label</span>
            <input
              type="text"
              value={draft.team.supervisorLabel}
              onChange={(event) =>
                updateTeamField("supervisorLabel", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <div className="mt-2 grid gap-2 sm:grid-cols-2">
            <label className="block">
              <span className={fieldLabel}>Name</span>
              <input
                type="text"
                value={draft.team.supervisor.name}
                onChange={(event) =>
                  updateSupervisor("name", event.target.value)
                }
                className={`${inputBase} mt-1`}
              />
            </label>
            <label className="block">
              <span className={fieldLabel}>Role</span>
              <input
                type="text"
                value={draft.team.supervisor.role}
                onChange={(event) =>
                  updateSupervisor("role", event.target.value)
                }
                className={`${inputBase} mt-1`}
              />
            </label>
          </div>
          <label className="mt-2 block">
            <span className={fieldLabel}>Email</span>
            <input
              type="text"
              value={draft.team.supervisor.email}
              onChange={(event) =>
                updateSupervisor("email", event.target.value)
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <label className="mt-2 block">
            <span className={fieldLabel}>Bio</span>
            <textarea
              rows={2}
              value={draft.team.supervisor.bio}
              onChange={(event) => updateSupervisor("bio", event.target.value)}
              className={`${textarea} mt-1`}
            />
          </label>
        </div>
      </AccordionSection>
      )}

      {activePage === "faq" && (
      <AccordionSection
        {...sectionTitleProps("faq")}
        badge={<CountPill count={draft.faqs.length} />}
        open={openSection === "faq"}
        onToggle={() => toggleSection("faq")}
      >
        <div className="flex justify-end">
          <button type="button" className={btnSecondary} onClick={addFaq}>
            Add entry
          </button>
        </div>
        <div className="mt-3 space-y-4">
          {draft.faqs.map((faq) => (
            <div key={faq.id} className="rounded-lg border border-border p-3">
              <label className="block">
                <span className={fieldLabel}>Question</span>
                <input
                  type="text"
                  value={faq.question}
                  onChange={(event) =>
                    updateFaq(faq.id, "question", event.target.value)
                  }
                  className={`${inputBase} mt-1`}
                />
              </label>
              <label className="mt-2 block">
                <span className={fieldLabel}>Answer</span>
                <textarea
                  rows={2}
                  value={faq.answer}
                  onChange={(event) =>
                    updateFaq(faq.id, "answer", event.target.value)
                  }
                  className={`${textarea} mt-1`}
                />
              </label>
              <div className="mt-2 flex justify-end">
                <button
                  type="button"
                  className={btnDanger}
                  onClick={() => removeFaq(faq.id)}
                >
                  Remove
                </button>
              </div>
            </div>
          ))}
        </div>
      </AccordionSection>
      )}

      {activePage === "documents" && (
      <AccordionSection
        title="Documents page"
        badge={<CountPill count={draft.documents.cards.length} />}
        open={openSection === "documents"}
        onToggle={() => toggleSection("documents")}
      >
        <div className="space-y-3">
          <label className="block">
            <span className={fieldLabel}>Heading</span>
            <input
              type="text"
              value={draft.documents.heading}
              onChange={(event) =>
                update("documents", {
                  ...draft.documents,
                  heading: event.target.value,
                })
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <label className="block">
            <span className={fieldLabel}>Intro</span>
            <textarea
              rows={3}
              value={draft.documents.intro}
              onChange={(event) =>
                update("documents", {
                  ...draft.documents,
                  intro: event.target.value,
                })
              }
              className={`${textarea} mt-1`}
            />
          </label>
        </div>

        <div className="mt-5 flex items-center justify-between">
          <span className={fieldLabel}>Document cards</span>
          <button
            type="button"
            className={btnSecondary}
            onClick={addDocumentCard}
          >
            Add document
          </button>
        </div>
        <div className="mt-3 space-y-4">
          {draft.documents.cards.map((card, index) => (
            <div key={index} className="rounded-lg border border-border p-3">
              <div className="grid gap-2 sm:grid-cols-2">
                <label className="block">
                  <span className={fieldLabel}>Title</span>
                  <input
                    type="text"
                    value={card.title}
                    onChange={(event) =>
                      updateDocumentCard(index, "title", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
                <label className="block">
                  <span className={fieldLabel}>Status</span>
                  <input
                    type="text"
                    value={card.status}
                    onChange={(event) =>
                      updateDocumentCard(index, "status", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
              </div>
              <label className="mt-2 block">
                <span className={fieldLabel}>Body</span>
                <textarea
                  rows={2}
                  value={card.body}
                  onChange={(event) =>
                    updateDocumentCard(index, "body", event.target.value)
                  }
                  className={`${textarea} mt-1`}
                />
              </label>
              <div className="mt-2 flex justify-end">
                <button
                  type="button"
                  className={btnDanger}
                  onClick={() => removeDocumentCard(index)}
                >
                  Remove
                </button>
              </div>
            </div>
          ))}
        </div>
      </AccordionSection>
      )}

      {activePage === "download" && (
      <AccordionSection
        title="Download page"
        open={openSection === "download"}
        onToggle={() => toggleSection("download")}
      >
        <div className="rounded-lg border border-border p-4">
          <h3 className="text-sm font-bold text-foreground">Android</h3>
          <label className="mt-3 block">
            <span className={fieldLabel}>Android APK URL</span>
            <input
              type="text"
              value={draft.download.android.apkUrl}
              onChange={(event) =>
                update("download", {
                  ...draft.download,
                  android: {
                    ...draft.download.android,
                    apkUrl: event.target.value,
                  },
                })
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <p className="mt-1 text-xs text-muted">
            Defaults to <code>/api/download/android</code>, the same-origin
            endpoint that streams the latest GitHub release &mdash; leave it as
            is unless you need the button to point somewhere else. Swapping it
            here updates the download button without a redeploy.
          </p>
          <label className="mt-3 block">
            <span className={fieldLabel}>Android note</span>
            <textarea
              rows={2}
              value={draft.download.android.note}
              onChange={(event) =>
                update("download", {
                  ...draft.download,
                  android: {
                    ...draft.download.android,
                    note: event.target.value,
                  },
                })
              }
              className={`${textarea} mt-1`}
            />
          </label>
        </div>

        <div className="mt-4 rounded-lg border border-border p-4">
          <h3 className="text-sm font-bold text-foreground">iOS</h3>
          <label className="mt-3 flex items-center justify-between gap-3 rounded-lg border border-border p-3">
            <span className="text-sm font-semibold text-foreground">
              Coming soon
            </span>
            <input
              type="checkbox"
              checked={draft.download.ios.comingSoon}
              onChange={() =>
                update("download", {
                  ...draft.download,
                  ios: {
                    ...draft.download.ios,
                    comingSoon: !draft.download.ios.comingSoon,
                  },
                })
              }
              className="h-4 w-4 accent-brand"
            />
          </label>
          <label className="mt-3 block">
            <span className={fieldLabel}>Badge label</span>
            <input
              type="text"
              value={draft.download.ios.badgeLabel}
              onChange={(event) =>
                update("download", {
                  ...draft.download,
                  ios: {
                    ...draft.download.ios,
                    badgeLabel: event.target.value,
                  },
                })
              }
              className={`${inputBase} mt-1`}
            />
          </label>
          <label className="mt-3 block">
            <span className={fieldLabel}>Reason</span>
            <textarea
              rows={2}
              value={draft.download.ios.reason}
              onChange={(event) =>
                update("download", {
                  ...draft.download,
                  ios: {
                    ...draft.download.ios,
                    reason: event.target.value,
                  },
                })
              }
              className={`${textarea} mt-1`}
            />
          </label>
        </div>

        <div className="mt-4 rounded-lg border border-border p-4">
          <div className="flex items-center justify-between gap-3">
            <h3 className="text-sm font-bold text-foreground">
              Install steps
            </h3>
            <button
              type="button"
              className={btnSecondary}
              onClick={addDownloadStep}
            >
              Add step
            </button>
          </div>
          <div className="mt-3 space-y-3">
            {draft.download.steps.map((step, index) => (
              <div key={index} className="rounded-lg border border-border p-3">
                <label className="block">
                  <span className={fieldLabel}>Title</span>
                  <input
                    type="text"
                    value={step.title}
                    onChange={(event) =>
                      updateDownloadStep(index, "title", event.target.value)
                    }
                    className={`${inputBase} mt-1`}
                  />
                </label>
                <label className="mt-2 block">
                  <span className={fieldLabel}>Body</span>
                  <textarea
                    rows={2}
                    value={step.body}
                    onChange={(event) =>
                      updateDownloadStep(index, "body", event.target.value)
                    }
                    className={`${textarea} mt-1`}
                  />
                </label>
                <div className="mt-2 flex justify-end">
                  <button
                    type="button"
                    className={btnDanger}
                    onClick={() => removeDownloadStep(index)}
                  >
                    Remove
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="mt-4 rounded-lg border border-border p-4">
          <div className="flex items-center justify-between gap-3">
            <h3 className="text-sm font-bold text-foreground">
              System requirements
            </h3>
            <button
              type="button"
              className={btnSecondary}
              onClick={addDownloadRequirement}
            >
              Add requirement
            </button>
          </div>
          <div className="mt-3 space-y-2">
            {draft.download.requirements.length === 0 ? (
              <p className="text-xs text-muted">No requirements listed.</p>
            ) : (
              draft.download.requirements.map((requirement, index) => (
                <div key={index} className="flex items-center gap-2">
                  <input
                    type="text"
                    value={requirement}
                    onChange={(event) =>
                      updateDownloadRequirement(index, event.target.value)
                    }
                    className={inputBase}
                  />
                  <button
                    type="button"
                    className={btnDanger}
                    onClick={() => removeDownloadRequirement(index)}
                  >
                    Remove
                  </button>
                </div>
              ))
            )}
          </div>
        </div>
      </AccordionSection>
      )}
      </div>

      <div className="sticky bottom-0 z-10 flex flex-wrap items-center gap-3 rounded-lg border border-border bg-white/95 px-4 py-3 shadow-[0_-10px_28px_-20px_rgba(0,30,98,0.6)] backdrop-blur supports-[backdrop-filter]:bg-white/80">
        <button
          type="button"
          className={btnBrand}
          onClick={save}
          disabled={!staged || saving}
        >
          {saving ? "Saving..." : "Save changes"}
        </button>
        {saveError ? (
          <span className="text-sm font-semibold text-red-600">
            {saveError}
          </span>
        ) : staged ? (
          <span className="text-sm font-semibold text-accent">
            Changes staged &mdash; not yet live
          </span>
        ) : savedNote ? (
          <span className="text-sm font-semibold text-[#0f6b4e]">
            {savedLive
              ? "Saved and live on the marketing site."
              : "Saved. Changes staged for the marketing site."}
          </span>
        ) : null}
      </div>
    </div>
  );
}

// Collapsible section wrapper. Only the header row shows when collapsed, so the
// whole editor reduces to a short list; the body (children) mounts only when
// open. Clicking the header toggles this section (single-open is enforced by
// the parent's openSection state).
function AccordionSection({
  title,
  badge,
  open,
  onToggle,
  onTitleChange,
  order,
  dragging,
  dragOver,
  onDragStart,
  onDragEnd,
  onDragOverItem,
  onDropItem,
  children,
}: {
  title: string;
  badge?: ReactNode;
  open: boolean;
  onToggle: () => void;
  // When provided, a pencil button appears that lets the admin rename this
  // section's label inline.
  onTitleChange?: (value: string) => void;
  // Drag-to-reorder: `order` drives the flex position (DOM order stays fixed),
  // and a grip handle starts the drag; the section itself is the drop target.
  order?: number;
  dragging?: boolean;
  dragOver?: boolean;
  onDragStart?: () => void;
  onDragEnd?: () => void;
  onDragOverItem?: () => void;
  onDropItem?: () => void;
  children: ReactNode;
}) {
  const [editing, setEditing] = useState(false);

  return (
    <section
      style={order !== undefined ? { order } : undefined}
      onDragOver={
        onDragOverItem
          ? (event) => {
              event.preventDefault();
              onDragOverItem();
            }
          : undefined
      }
      onDrop={
        onDropItem
          ? (event) => {
              event.preventDefault();
              onDropItem();
            }
          : undefined
      }
      className={`overflow-hidden rounded-lg border bg-white shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)] transition-shadow ${
        dragOver
          ? "border-[#001e62] ring-2 ring-[#001e62]/30"
          : "border-border"
      } ${dragging ? "opacity-60" : ""}`}
    >
      <div className="flex w-full items-center justify-between gap-3 p-5 transition-colors hover:bg-brand-soft/40 sm:p-6">
        <div className="flex min-w-0 flex-1 items-center gap-2.5">
          {onDragStart ? (
            <button
              type="button"
              draggable
              onDragStart={onDragStart}
              onDragEnd={onDragEnd}
              aria-label="Drag to reorder section"
              title="Drag to reorder"
              className="shrink-0 cursor-grab rounded p-1 text-muted transition-colors hover:bg-brand-soft hover:text-foreground active:cursor-grabbing"
            >
              <GripIcon />
            </button>
          ) : null}
          {editing ? (
            <input
              autoFocus
              value={title}
              onChange={(event) => onTitleChange?.(event.target.value)}
              onBlur={() => setEditing(false)}
              onKeyDown={(event) => {
                if (event.key === "Enter" || event.key === "Escape") {
                  event.preventDefault();
                  setEditing(false);
                }
              }}
              className="w-full max-w-xs rounded-md border border-border bg-white px-2 py-1 text-base font-bold text-brand outline-none focus:ring-2 focus:ring-[#001e62]/25"
            />
          ) : (
            <button
              type="button"
              onClick={onToggle}
              aria-expanded={open}
              className="flex min-w-0 items-center gap-3 text-left"
            >
              <span className="truncate text-base font-bold text-brand">
                {title}
              </span>
              {badge}
            </button>
          )}
          {onTitleChange && !editing ? (
            <button
              type="button"
              onClick={() => setEditing(true)}
              aria-label="Rename section"
              title="Rename section"
              className="shrink-0 rounded p-1 text-foreground/60 transition-colors hover:bg-brand-soft hover:text-foreground"
            >
              <PencilIcon />
            </button>
          ) : null}
        </div>
        <button
          type="button"
          onClick={onToggle}
          aria-label={open ? "Collapse section" : "Expand section"}
          className="shrink-0 rounded p-1 transition-colors hover:bg-brand-soft/60"
        >
          <ChevronIcon open={open} />
        </button>
      </div>
      {open ? (
        <div className="px-5 pb-5 sm:px-6 sm:pb-6">{children}</div>
      ) : null}
    </section>
  );
}

// Drag handle (six-dot grip) shown at the left of each section header.
function GripIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <circle cx="9" cy="6" r="1.6" />
      <circle cx="15" cy="6" r="1.6" />
      <circle cx="9" cy="12" r="1.6" />
      <circle cx="15" cy="12" r="1.6" />
      <circle cx="9" cy="18" r="1.6" />
      <circle cx="15" cy="18" r="1.6" />
    </svg>
  );
}

// Black pencil / edit affordance shown next to each section label.
function PencilIcon() {
  return (
    <svg
      width="15"
      height="15"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M12 20h9" />
      <path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5Z" />
    </svg>
  );
}

function ChevronIcon({ open }: { open: boolean }) {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      aria-hidden="true"
      className={`shrink-0 text-muted transition-transform ${
        open ? "rotate-180" : ""
      }`}
    >
      <path
        d="m4 6 4 4 4-4"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function StatusPill({
  tone,
  children,
}: {
  tone: "on" | "off";
  children: ReactNode;
}) {
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-[11px] font-bold ${
        tone === "on"
          ? "bg-[#e6f4ee] text-[#0f6b4e]"
          : "bg-brand-soft text-muted"
      }`}
    >
      {children}
    </span>
  );
}

function CountPill({ count }: { count: number }) {
  return (
    <span className="rounded-full bg-brand-soft px-2 py-0.5 text-[11px] font-bold text-brand">
      {count}
    </span>
  );
}

// Shared editor body for the split-highlight sections (XP progression,
// territorial leaderboard, post-run summary): eyebrow / heading / body / CTA
// plus the optional app screenshot shown inside the iPhone frame.
function HighlightPanelBody({
  value,
  onChange,
  note,
}: {
  value: SiteHighlight;
  onChange: (patch: Partial<SiteHighlight>) => void;
  note: string;
}) {
  return (
    <>
      <p className="text-xs text-muted">{note}</p>
      <div className="mt-4 space-y-3">
        <label className="block">
          <span className={fieldLabel}>Eyebrow</span>
          <input
            type="text"
            value={value.eyebrow}
            onChange={(event) => onChange({ eyebrow: event.target.value })}
            className={`${inputBase} mt-1`}
          />
        </label>
        <label className="block">
          <span className={fieldLabel}>Heading</span>
          <input
            type="text"
            value={value.heading}
            onChange={(event) => onChange({ heading: event.target.value })}
            className={`${inputBase} mt-1`}
          />
        </label>
        <label className="block">
          <span className={fieldLabel}>Body</span>
          <textarea
            rows={3}
            value={value.body}
            onChange={(event) => onChange({ body: event.target.value })}
            className={`${textarea} mt-1`}
          />
        </label>
        <label className="block">
          <span className={fieldLabel}>CTA button label</span>
          <input
            type="text"
            value={value.ctaLabel}
            onChange={(event) => onChange({ ctaLabel: event.target.value })}
            className={`${inputBase} mt-1`}
          />
        </label>
      </div>

      <div className="mt-5 rounded-lg border border-border p-4">
        <h3 className="text-sm font-bold text-foreground">
          App screenshot (shown inside an iPhone frame)
        </h3>
        <label className="mt-3 block">
          <span className={fieldLabel}>Image URL or /public path</span>
          <input
            type="text"
            value={value.imageSrc}
            onChange={(event) => onChange({ imageSrc: event.target.value })}
            placeholder="https://… or /shot.png"
            className={`${inputBase} mt-1`}
          />
        </label>
        <p className="mt-1 text-xs text-muted">
          Leave empty to show the built-in illustration. A tall (9:19.5)
          screenshot fits the frame best.
        </p>
        <label className="mt-3 block">
          <span className={fieldLabel}>Image alt text</span>
          <input
            type="text"
            value={value.imageAlt}
            onChange={(event) => onChange({ imageAlt: event.target.value })}
            className={`${inputBase} mt-1`}
          />
        </label>
        {value.imageSrc ? (
          <div className="mt-3">
            <span className={fieldLabel}>Preview</span>
            <IphoneFrame
              src={value.imageSrc}
              alt={value.imageAlt}
              className="mt-2 w-28"
            />
          </div>
        ) : null}
      </div>
    </>
  );
}

// Editable, add/remove-able list of the check-marked feature strings shown
// under a pricing tier.
function FeatureListEditor({
  label,
  features,
  onChange,
  onAdd,
  onRemove,
}: {
  label: string;
  features: string[];
  onChange: (index: number, value: string) => void;
  onAdd: () => void;
  onRemove: (index: number) => void;
}) {
  return (
    <div>
      <div className="flex items-center justify-between gap-3">
        <span className={fieldLabel}>{label}</span>
        <button type="button" className={btnSecondary} onClick={onAdd}>
          Add feature
        </button>
      </div>
      <div className="mt-2 space-y-2">
        {features.length === 0 ? (
          <p className="text-xs text-muted">No features listed.</p>
        ) : (
          features.map((feature, index) => (
            <div key={index} className="flex items-center gap-2">
              <input
                type="text"
                value={feature}
                onChange={(event) => onChange(index, event.target.value)}
                className={inputBase}
              />
              <button
                type="button"
                className={btnDanger}
                onClick={() => onRemove(index)}
              >
                Remove
              </button>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

// Price / period / note triple for one premium billing cycle.
function TierPriceEditor({
  title,
  tier,
  onChange,
}: {
  title: string;
  tier: { price: string; period: string; note: string };
  onChange: (key: "price" | "period" | "note", value: string) => void;
}) {
  return (
    <div className="rounded-lg border border-border p-3">
      <span className={fieldLabel}>{title}</span>
      <div className="mt-2 grid grid-cols-2 gap-3">
        <label className="block">
          <span className={fieldLabel}>Price</span>
          <input
            type="text"
            value={tier.price}
            onChange={(event) => onChange("price", event.target.value)}
            className={`${inputBase} mt-1`}
          />
        </label>
        <label className="block">
          <span className={fieldLabel}>Period</span>
          <input
            type="text"
            value={tier.period}
            onChange={(event) => onChange("period", event.target.value)}
            className={`${inputBase} mt-1`}
          />
        </label>
      </div>
      <label className="mt-2 block">
        <span className={fieldLabel}>Note</span>
        <input
          type="text"
          value={tier.note}
          onChange={(event) => onChange("note", event.target.value)}
          className={`${inputBase} mt-1`}
        />
      </label>
    </div>
  );
}
