import type { Metadata } from "next";
import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";
import { NewsletterStatusMessage } from "@/components/NewsletterStatusMessage";

// Redirect target for the one-click unsubscribe link the backend puts in
// every campaign email. Pure static markup: no Firestore read, so it renders
// correctly even with no Firebase credentials configured.

export const metadata: Metadata = {
  title: "Unsubscribed | Runiac",
  description: "You have been unsubscribed from the Runiac newsletter.",
};

export default function NewsletterUnsubscribedPage() {
  return (
    <>
      <Navbar />
      <main className="flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden">
        <NewsletterStatusMessage
          eyebrow="Newsletter"
          title="You're unsubscribed."
          description="You won't receive any more Runiac newsletter emails. You can sign up again at any time from the homepage."
          tone="neutral"
        />
      </main>
      <Footer />
    </>
  );
}
