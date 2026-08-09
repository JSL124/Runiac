// The Privacy Policy.
//
// The text lives here as structured sections rather than in a CMS because the
// app links to this URL from Settings — it has to be a stable, always-present
// page, not one that depends on a backend read succeeding.
//
// Keep it truthful about what Runiac actually collects: GPS routes, health-ish
// onboarding answers and account data are the sensitive parts, and this page is
// what users are shown before consenting to them.

import type { Metadata } from "next";
import { Footer } from "@/components/Footer";
import { LegalDocument } from "@/components/LegalDocument";
import { Navbar } from "@/components/Navbar";

export const metadata: Metadata = {
  title: "Privacy Policy | Runiac",
  description:
    "How Runiac collects, uses, shares, and protects your personal data — including GPS route data, run metrics, and account information — under Singapore's PDPA.",
};

const sections = [
  {
    heading: "1. About this policy",
    body: (
      <>
        <p>
          This policy explains how Runiac collects, uses, discloses, and protects
          your personal data when you use the Runiac mobile app and this website.
          It is written with Singapore&rsquo;s Personal Data Protection Act 2012
          (PDPA) in mind.
        </p>
        <p>
          Runiac is a Final Year Project. The team behind it acts as the
          organisation responsible for the personal data described here, and can
          be reached at{" "}
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
  {
    heading: "2. Data we collect",
    body: (
      <>
        <p>
          <strong className="font-semibold text-foreground">
            Account and profile data.
          </strong>{" "}
          Your email address and password credentials (held by Firebase
          Authentication), or your Google account identity if you sign in with
          Google. Your display name, nickname, selected character, running
          experience answers, and any profile details you enter.
        </p>
        <p>
          <strong className="font-semibold text-foreground">
            Location and route data.
          </strong>{" "}
          When you start a run, the app records your device&rsquo;s GPS position
          over time to build the route line, distance, pace, and split figures.
          We treat GPS route geometry as sensitive. Location is collected during
          an active run — including while the app is in the background if you
          allow it — and stops when you end the run.
        </p>
        <p>
          <strong className="font-semibold text-foreground">
            Activity and fitness data.
          </strong>{" "}
          Distance, duration, pace, cadence measured from your phone&rsquo;s
          motion sensors, timestamps, run summaries, route map images, and your
          activity history. If you connect Apple Health, workouts you choose to
          import are also stored.
        </p>
        <p>
          <strong className="font-semibold text-foreground">
            Plan and progression data.
          </strong>{" "}
          Your generated or enrolled training plans, plan progress, XP, level,
          rank, streaks, leaderboard entries, challenge participation, and
          earned badges.
        </p>
        <p>
          <strong className="font-semibold text-foreground">
            Social data.
          </strong>{" "}
          Posts you publish to the feed, likes and comments, friends, friend
          requests, users you block, content you hide, and reports you submit.
        </p>
        <p>
          <strong className="font-semibold text-foreground">
            Notification data.
          </strong>{" "}
          Device push tokens, your notification preferences, and records of
          notifications we sent you.
        </p>
        <p>
          <strong className="font-semibold text-foreground">
            Consent records.
          </strong>{" "}
          When you turn a consent-gated feature on or off, we store which
          version of the disclosure you agreed to and when.
        </p>
        <p>
          <strong className="font-semibold text-foreground">
            Subscription status.
          </strong>{" "}
          Whether your account is Basic or Premium, and when Premium expires. We
          do not receive or store your card details — payments are handled by the
          App Store or Google Play.
        </p>
        <p>
          <strong className="font-semibold text-foreground">
            Diagnostic data.
          </strong>{" "}
          Error reports and technical logs that help us find and fix crashes and
          failed operations, together with basic device and app version
          information.
        </p>
      </>
    ),
  },
  {
    heading: "3. Why we use your data",
    body: (
      <ul className="list-disc space-y-2 pl-5">
        <li>To create and secure your account, and to sign you in.</li>
        <li>
          To record your runs, draw your routes, and show your activity history.
        </li>
        <li>
          To generate and adapt training plans, and to calculate progress
          feedback.
        </li>
        <li>
          To calculate XP, levels, ranks, streaks, and leaderboard standings on
          our servers, and to validate submitted activities so competition stays
          fair.
        </li>
        <li>
          To run social features you choose to use, such as the feed, friends,
          and challenges.
        </li>
        <li>To send notifications you have enabled.</li>
        <li>To provide and manage Premium features.</li>
        <li>
          To detect abuse, investigate reports, and keep the Service reliable and
          secure.
        </li>
        <li>To meet legal and record-keeping obligations.</li>
      </ul>
    ),
  },
  {
    heading: "4. Coaching feedback and automated processing",
    body: (
      <>
        <p>
          Some coaching and progress-analysis features send a small summary of
          your activity to an external AI provider (OpenAI) to generate written
          feedback. These features are consent-gated: you turn them on
          explicitly, and you can turn them off at any time in Privacy &amp;
          Safety.
        </p>
        <p>
          Only derived metrics are sent — figures such as distance, duration,
          pace, and cadence summaries. We do not send raw GPS coordinates, route
          geometry, route names, your name, or your email address. Generated
          feedback is shown to you and is not used to make decisions that
          materially affect your rights.
        </p>
        <p>
          Voice coaching during a run is generated on your device by your
          phone&rsquo;s built-in speech engine. No audio is recorded or uploaded.
        </p>
      </>
    ),
  },
  {
    heading: "5. Who we share data with",
    body: (
      <>
        <p>
          We do not sell your personal data and we do not use it for third-party
          advertising. We share it only with service providers that help us
          operate Runiac, and only for that purpose:
        </p>
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong className="font-semibold text-foreground">
              Google (Firebase)
            </strong>{" "}
            — authentication, database, file storage, server functions, push
            messaging, and app attestation.
          </li>
          <li>
            <strong className="font-semibold text-foreground">Mapbox</strong> —
            map rendering and route images. Map requests reveal the map area
            being displayed.
          </li>
          <li>
            <strong className="font-semibold text-foreground">OpenAI</strong> —
            generation of coaching and progress feedback from the derived metrics
            described in section 4, for consent-gated features only.
          </li>
          <li>
            <strong className="font-semibold text-foreground">
              Apple and Google
            </strong>{" "}
            — subscription payment and entitlement processing.
          </li>
          <li>
            <strong className="font-semibold text-foreground">
              Vercel
            </strong>{" "}
            — hosting for this website.
          </li>
        </ul>
        <p>
          We may also disclose data where required by law, to enforce our Terms,
          or to protect the safety of users.
        </p>
        <p>
          Other Runiac users can see what you choose to share: your public
          profile, leaderboard entries, feed posts, and challenge participation.
          Your detailed route data is not published to other users unless you
          share it yourself.
        </p>
      </>
    ),
  },
  {
    heading: "6. Transfers outside Singapore",
    body: (
      <p>
        Our service providers operate globally, so your data may be stored or
        processed outside Singapore. When that happens we rely on the providers&rsquo;
        contractual data-protection commitments to give your data a standard of
        protection comparable to the PDPA.
      </p>
    ),
  },
  {
    heading: "7. How long we keep data",
    body: (
      <ul className="list-disc space-y-2 pl-5">
        <li>
          Account, activity, route, plan, and progression data is kept while your
          account is open.
        </li>
        <li>
          When you delete your account, we delete the personal data associated
          with it. See our{" "}
          <a
            className="font-semibold text-brand hover:underline"
            href="/legal/account-deletion"
          >
            account deletion page
          </a>{" "}
          for what is removed and what is retained.
        </li>
        <li>
          Diagnostic logs are kept for a short period for troubleshooting, then
          deleted or aggregated.
        </li>
        <li>
          Anonymised or aggregated statistics that cannot identify you may be
          kept indefinitely.
        </li>
      </ul>
    ),
  },
  {
    heading: "8. How we protect your data",
    body: (
      <ul className="list-disc space-y-2 pl-5">
        <li>Data is encrypted in transit.</li>
        <li>
          Database access rules restrict each account to its own records, and
          values such as XP, rank, and leaderboard scores can only be written by
          our servers — not by the app.
        </li>
        <li>
          App attestation is used to reject requests that do not come from a
          genuine Runiac app.
        </li>
        <li>
          Administrative access is limited to the platform administrator role and
          is used for content review, safety, and support.
        </li>
      </ul>
    ),
  },
  {
    heading: "9. Your choices and your rights",
    body: (
      <>
        <p>Under the PDPA you may:</p>
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong className="font-semibold text-foreground">Access</strong> —
            ask for a copy of the personal data we hold about you and how it has
            been used.
          </li>
          <li>
            <strong className="font-semibold text-foreground">Correct</strong> —
            ask us to fix data that is inaccurate or incomplete.
          </li>
          <li>
            <strong className="font-semibold text-foreground">
              Withdraw consent
            </strong>{" "}
            — turn off consent-gated features, revoke location or notification
            permissions in your device settings, or ask us to stop a particular
            use. Some features will not work without the data they depend on.
          </li>
          <li>
            <strong className="font-semibold text-foreground">Delete</strong> —
            ask us to delete your account and associated data.
          </li>
        </ul>
        <p>
          Send requests to{" "}
          <a
            className="font-semibold text-brand hover:underline"
            href="mailto:admin@runiac.app"
          >
            admin@runiac.app
          </a>
          . We may need to verify your identity before acting, and we aim to
          respond within 30 days.
        </p>
      </>
    ),
  },
  {
    heading: "10. Children",
    body: (
      <p>
        Runiac is not intended for children under 13, and we do not knowingly
        collect their personal data. If you believe a child has given us personal
        data, contact us and we will delete it.
      </p>
    ),
  },
  {
    heading: "11. Changes to this policy",
    body: (
      <p>
        We may update this policy as Runiac develops. We will change the
        effective date above and, where the change is material, show a notice in
        the app.
      </p>
    ),
  },
];

export default function PrivacyPage() {
  return (
    <>
      <Navbar />
      <main className="legal-page flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden">
        <LegalDocument
          eyebrow="Legal"
          title="Privacy Policy"
          effectiveDate="26 July 2026"
          intro="Runiac records where you run and how you run. This policy sets out exactly what we collect, why we collect it, who we share it with, and how you can get it removed."
          sections={sections}
        />
      </main>
      <Footer />
    </>
  );
}
