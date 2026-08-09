// The Terms of Service.
//
// Same shape as the privacy page and rendered through the same
// [LegalDocument] component, so both stay typographically identical. Also
// linked from the app, so it must remain reachable without any backend.

import type { Metadata } from "next";
import { Footer } from "@/components/Footer";
import { LegalDocument } from "@/components/LegalDocument";
import { Navbar } from "@/components/Navbar";

export const metadata: Metadata = {
  title: "Terms of Service | Runiac",
  description:
    "The terms that apply when you use the Runiac beginner running app and website, including account rules, safety limits, and Premium subscription terms.",
};

const sections = [
  {
    heading: "1. Who we are and what these terms cover",
    body: (
      <>
        <p>
          Runiac is a beginner-focused running app built as a Final Year
          Project. These Terms of Service (the &ldquo;Terms&rdquo;) apply to the
          Runiac mobile app, this website, and any related services we provide
          (together, the &ldquo;Service&rdquo;).
        </p>
        <p>
          By creating an account or continuing to use the Service, you agree to
          these Terms. If you do not agree, please stop using the Service.
        </p>
      </>
    ),
  },
  {
    heading: "2. Eligibility",
    body: (
      <>
        <p>
          You must be at least 13 years old to create a Runiac account. If you
          are under the age of majority where you live, you may only use the
          Service with the involvement of a parent or guardian who accepts these
          Terms on your behalf.
        </p>
        <p>
          The Service is not designed for, or directed at, children under 13.
        </p>
      </>
    ),
  },
  {
    heading: "3. Health and safety — this is not medical advice",
    body: (
      <>
        <p>
          Runiac provides general fitness guidance for new runners. It is not a
          medical service, and nothing in the Service is medical advice,
          diagnosis, or treatment.
        </p>
        <ul className="list-disc space-y-2 pl-5">
          <li>
            Talk to a qualified healthcare professional before starting a
            running plan, especially if you have an existing condition, are
            pregnant, are recovering from an injury, or have been inactive for a
            long time.
          </li>
          <li>
            Stop exercising and seek medical help if you feel pain, dizziness,
            chest discomfort, or shortness of breath.
          </li>
          <li>
            You are responsible for your surroundings. Runiac tracks runs using
            your phone; it does not watch traffic, weather, or terrain for you.
          </li>
          <li>
            Training plans, coaching messages, and progress feedback are
            automated suggestions based on the data you record. They are
            estimates, not instructions from a clinician or coach.
          </li>
        </ul>
        <p>
          You take part in physical activity at your own risk, and you are
          responsible for deciding whether any suggested run is appropriate for
          you on a given day.
        </p>
      </>
    ),
  },
  {
    heading: "4. Your account",
    body: (
      <>
        <p>
          You need an account to use most of the Service. You agree to give
          accurate information, keep your login credentials secure, and take
          responsibility for activity that happens under your account.
        </p>
        <p>
          Tell us at{" "}
          <a
            className="font-semibold text-brand hover:underline"
            href="mailto:admin@runiac.app"
          >
            admin@runiac.app
          </a>{" "}
          if you believe your account has been accessed without your permission.
        </p>
        <p>
          You can ask us to delete your account and its data at any time. See
          our{" "}
          <a
            className="font-semibold text-brand hover:underline"
            href="/legal/account-deletion"
          >
            account deletion page
          </a>
          .
        </p>
      </>
    ),
  },
  {
    heading: "5. Acceptable use",
    body: (
      <>
        <p>You agree not to:</p>
        <ul className="list-disc space-y-2 pl-5">
          <li>
            Submit fake, edited, or automated activity data, or use a vehicle,
            emulator, or location spoofing tool to record a run.
          </li>
          <li>
            Interfere with XP, levels, ranks, streaks, or leaderboard results, or
            attempt to write values that our servers are responsible for
            calculating.
          </li>
          <li>
            Upload content that is unlawful, harassing, hateful, deceptive, or
            that infringes someone else&rsquo;s rights.
          </li>
          <li>
            Attempt to access other users&rsquo; accounts, routes, or personal
            data, or probe, scan, or overload our systems.
          </li>
          <li>
            Reverse engineer, resell, or commercially redistribute the Service
            without our written permission.
          </li>
        </ul>
        <p>
          We may remove content, reset affected results, or suspend accounts
          that break these rules. Where results were affected, we may recalculate
          or void them.
        </p>
      </>
    ),
  },
  {
    heading: "6. Fair competition",
    body: (
      <>
        <p>
          XP, levels, ranks, streaks, and leaderboard scores are calculated and
          stored by our servers from validated activity data. The app displays
          those values; it does not decide them.
        </p>
        <p>
          Premium does not change how any of those values are calculated.
          Premium subscribers earn progression under exactly the same rules as
          everyone else. Paying for Runiac gives you coaching, analysis, expert
          plans, route convenience, and presentation features — never a
          competitive advantage.
        </p>
      </>
    ),
  },
  {
    heading: "7. Premium subscriptions",
    body: (
      <>
        <ul className="list-disc space-y-2 pl-5">
          <li>
            Premium is an auto-renewing subscription. Prices, billing periods,
            and any trial terms are shown in the app before you confirm a
            purchase.
          </li>
          <li>
            Payment is taken by the App Store or Google Play, not by Runiac
            directly. Your subscription renews automatically at the end of each
            billing period unless you cancel at least 24 hours beforehand.
          </li>
          <li>
            Manage or cancel your subscription in your App Store or Google Play
            account settings. Deleting the app does not cancel a subscription.
          </li>
          <li>
            Refunds are handled by the App Store or Google Play under their
            policies. We cannot issue store refunds on your behalf.
          </li>
          <li>
            If Premium ends, your account stays active with Basic features. Data
            you have already recorded remains yours.
          </li>
        </ul>
        <p>
          Expert training plans available to Premium subscribers are reviewed and
          published by the Runiac platform administrator before they appear in
          the app.
        </p>
      </>
    ),
  },
  {
    heading: "8. Your content",
    body: (
      <p>
        You keep ownership of the runs, routes, photos, and other content you
        create. You give us permission to store, process, and display that
        content so we can operate the Service for you — for example, to draw your
        route on a map, calculate your progress, or show a post you chose to
        share. If you share content publicly in the app, you are allowing other
        users to see it.
      </p>
    ),
  },
  {
    heading: "9. Availability and changes",
    body: (
      <p>
        The Service is provided on an &ldquo;as is&rdquo; and &ldquo;as
        available&rdquo; basis. As an academic project, features may change,
        pause, or be withdrawn, and we do not guarantee uninterrupted or
        error-free operation. We will give reasonable notice in the app before
        making a material change that reduces functionality you have paid for.
      </p>
    ),
  },
  {
    heading: "10. Limitation of liability",
    body: (
      <p>
        To the fullest extent permitted by law, Runiac is not liable for
        indirect, incidental, or consequential loss, for loss of data, or for
        injury arising from physical activity you chose to undertake. Nothing in
        these Terms limits liability that cannot lawfully be limited.
      </p>
    ),
  },
  {
    heading: "11. Suspension and termination",
    body: (
      <p>
        You may stop using the Service at any time. We may suspend or terminate
        access if you breach these Terms, if required by law, or if we
        discontinue the Service. On termination, the sections that by their
        nature should survive — including fair competition, acceptable use, and
        limitation of liability — continue to apply.
      </p>
    ),
  },
  {
    heading: "12. Changes to these Terms",
    body: (
      <p>
        We may update these Terms as the Service develops. When we do, we will
        change the effective date above and, for material changes, show a notice
        in the app. Continuing to use the Service after an update means you
        accept the revised Terms.
      </p>
    ),
  },
  {
    heading: "13. Governing law and contact",
    body: (
      <>
        <p>
          These Terms are governed by the laws of Singapore, and the courts of
          Singapore have exclusive jurisdiction over any dispute arising from
          them.
        </p>
        <p>
          Contact us at{" "}
          <a
            className="font-semibold text-brand hover:underline"
            href="mailto:admin@runiac.app"
          >
            admin@runiac.app
          </a>
          .
        </p>
      </>
    ),
  },
];

export default function TermsPage() {
  return (
    <>
      <Navbar />
      <main className="legal-page flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden">
        <LegalDocument
          eyebrow="Legal"
          title="Terms of Service"
          effectiveDate="26 July 2026"
          intro="These terms explain what you can expect from Runiac, what we expect from you, and how Premium subscriptions work."
          sections={sections}
        />
      </main>
      <Footer />
    </>
  );
}
