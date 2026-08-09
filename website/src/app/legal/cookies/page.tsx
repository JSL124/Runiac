import type { Metadata } from "next";
import { Footer } from "@/components/Footer";
import { LegalDocument } from "@/components/LegalDocument";
import { Navbar } from "@/components/Navbar";

export const metadata: Metadata = {
  title: "Cookie Notice | Runiac",
  description:
    "Which cookies the Runiac website uses, what they are for, and how to control them. Runiac uses essential session cookies only.",
};

const sections = [
  {
    heading: "What we use",
    body: (
      <>
        <p>
          This website uses <strong className="font-semibold text-foreground">
            essential cookies only
          </strong>
          . They exist to keep the site working, not to profile you.
        </p>
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong className="font-semibold text-foreground">
              Session cookies.
            </strong>{" "}
            Set when you sign in, so the site knows you are logged in as you move
            between pages, and so administrator pages can check your permissions.
            These are cleared when you sign out or when the session expires.
          </li>
          <li>
            <strong className="font-semibold text-foreground">
              Security cookies.
            </strong>{" "}
            Short-lived values used to protect sign-in against request forgery
            and to refresh your session safely.
          </li>
        </ul>
      </>
    ),
  },
  {
    heading: "What we do not use",
    body: (
      <p>
        We do not use advertising cookies, cross-site tracking pixels, or
        third-party analytics that follow you around the web. We do not sell data
        collected through this site.
      </p>
    ),
  },
  {
    heading: "The Runiac mobile app",
    body: (
      <p>
        The Runiac mobile app is not a website and does not use cookies. It
        stores your session and a small amount of preference data on your device
        so you stay signed in. How the app handles your personal data is
        described in our{" "}
        <a
          className="font-semibold text-brand hover:underline"
          href="/legal/privacy"
        >
          Privacy Policy
        </a>
        .
      </p>
    ),
  },
  {
    heading: "Managing cookies",
    body: (
      <p>
        You can clear or block cookies in your browser settings. Because the
        cookies we use are essential, blocking them will stop you from signing in
        and using account features, but the public pages of this site will still
        work.
      </p>
    ),
  },
];

export default function CookiesPage() {
  return (
    <>
      <Navbar />
      <main className="legal-page flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden">
        <LegalDocument
          eyebrow="Legal"
          title="Cookie Notice"
          effectiveDate="26 July 2026"
          intro="A short explanation of the cookies this website sets and how to control them."
          sections={sections}
        />
      </main>
      <Footer />
    </>
  );
}
