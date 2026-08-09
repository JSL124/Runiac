import type { Metadata } from "next";
import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";
import { NewsletterStatusMessage } from "@/components/NewsletterStatusMessage";

// Redirect target when a confirmation/unsubscribe link is expired, malformed,
// or already used. Pure static markup: no Firestore read, so it renders
// correctly even with no Firebase credentials configured.

export const metadata: Metadata = {
  title: "Link no longer valid | Runiac",
  description: "This Runiac newsletter link is invalid or has expired.",
};

export default function NewsletterInvalidLinkPage() {
  return (
    <>
      <Navbar />
      <main className="flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden">
        <NewsletterStatusMessage
          eyebrow="Newsletter"
          title="This link is no longer valid."
          description="It may have expired or already been used. If you're trying to confirm a subscription, sign up again from the homepage — if you're trying to unsubscribe, email us and we'll take care of it."
          tone="warn"
        />
      </main>
      <Footer />
    </>
  );
}
