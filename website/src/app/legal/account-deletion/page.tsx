import type { Metadata } from "next";
import { Footer } from "@/components/Footer";
import { LegalDocument } from "@/components/LegalDocument";
import { Navbar } from "@/components/Navbar";

export const metadata: Metadata = {
  title: "Account Deletion | Runiac",
  description:
    "How to delete your Runiac account and associated data from inside the app, what gets deleted, what is retained, and when it takes effect.",
};

const sections = [
  {
    heading: "Deleting from inside the app",
    body: (
      <>
        <p>
          This is the way to delete your account. Open the menu on the Home
          screen, tap <strong className="font-semibold text-foreground">Account</strong>,
          scroll to the bottom, and tap{" "}
          <strong className="font-semibold text-foreground">Delete account</strong>.
        </p>
        <p>
          The screen that opens lists exactly what will be erased and what is
          kept. To go ahead you have to type the word{" "}
          <strong className="font-semibold text-foreground">DELETE</strong> and
          then confirm once more. Both steps exist because there is no undo.
        </p>
        <p>
          You do not need to contact us, and there is no charge.
        </p>
      </>
    ),
  },
  {
    heading: "If you cannot sign in",
    body: (
      <>
        <p>
          Deleting from inside the app requires being signed in. If you have lost
          access to your account, email{" "}
          <a
            className="font-semibold text-brand hover:underline"
            href="mailto:admin@runiac.app?subject=Runiac%20account%20deletion%20request"
          >
            admin@runiac.app
          </a>{" "}
          from the email address registered to your Runiac account, with the
          subject line <em>Runiac account deletion request</em>.
        </p>
        <p>Please include:</p>
        <ul className="list-disc space-y-2 pl-5">
          <li>The email address on the account.</li>
          <li>
            Your Runiac display name or nickname, so we can confirm we are
            deleting the right account.
          </li>
        </ul>
        <p>
          If you signed up with Google, send the request from that same Google
          address. We may ask one follow-up question to verify ownership before
          we delete anything, because deletion cannot be undone. We handle these
          requests by hand, so allow up to 30 days.
        </p>
      </>
    ),
  },
  {
    heading: "What gets deleted",
    body: (
      <>
        <p>
          Deleting your account removes the personal data tied to it, including:
        </p>
        <ul className="list-disc space-y-2 pl-5">
          <li>Your login credentials and authentication record.</li>
          <li>
            Your profile, nickname, selected character, and onboarding answers.
          </li>
          <li>
            Your recorded runs, GPS route data, route images, and activity
            history.
          </li>
          <li>
            Your training plans, plan progress, and adaptive plan estimates.
          </li>
          <li>
            Your XP, level, rank, streaks, leaderboard entries, challenge
            participation, and badges.
          </li>
          <li>
            Your feed posts, likes, comments, friends, friend requests, and block
            list.
          </li>
          <li>
            Your push notification tokens, notification preferences, and
            notification history.
          </li>
          <li>Your stored consent records.</li>
        </ul>
      </>
    ),
  },
  {
    heading: "What we keep, and why",
    body: (
      <ul className="list-disc space-y-2 pl-5">
        <li>
          <strong className="font-semibold text-foreground">
            Anonymised statistics.
          </strong>{" "}
          Aggregated figures that can no longer identify you may remain in
          reporting totals.
        </li>
        <li>
          <strong className="font-semibold text-foreground">
            Safety and moderation records.
          </strong>{" "}
          Reports you filed, reports filed about you, and feedback you sent us
          are kept, with your account identifier replaced by{" "}
          <em>deleted-user</em> so the record no longer points at you. We keep
          them because deleting an account must not become a way to erase a
          report and start over.
        </li>
        <li>
          <strong className="font-semibold text-foreground">
            Records we are required to keep.
          </strong>{" "}
          Where law obliges us to retain something, we keep only what is
          required, for only as long as required.
        </li>
        <li>
          <strong className="font-semibold text-foreground">Backups.</strong>{" "}
          Copies may persist in routine encrypted backups for a short period
          before those backups expire.
        </li>
      </ul>
    ),
  },
  {
    heading: "When it takes effect",
    body: (
      <>
        <p>
          Immediately. There is no waiting period and no cooling-off window. The
          moment you confirm, your session ends, you can no longer sign in, and
          the erase begins. We do not email you to confirm, and there is nothing
          to cancel afterwards, so please be sure before you tap.
        </p>
        <p>
          Signing up again later creates a completely new account. It does not
          recover anything.
        </p>
        <p>
          One thing lags slightly behind: a public leaderboard board may still
          show your old display name and score until it is rebuilt, which happens
          hourly. That board row carries no account identifier.
        </p>
      </>
    ),
  },
  {
    heading: "Your Premium subscription",
    body: (
      <p>
        Deleting your Runiac account does not cancel an active subscription.
        Subscriptions are billed by the App Store or Google Play, so cancel yours
        in your store account settings before you delete, otherwise it may
        continue to renew.
      </p>
    ),
  },
];

export default function AccountDeletionPage() {
  return (
    <>
      <Navbar />
      <main className="legal-page flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden">
        <LegalDocument
          eyebrow="Legal"
          title="Account Deletion"
          effectiveDate="4 August 2026"
          intro="You can delete your Runiac account and the data attached to it at any time, from inside the app. Here is how to do it, what is erased, and what happens next. Deletion is immediate and cannot be undone."
          sections={sections}
        />
      </main>
      <Footer />
    </>
  );
}
