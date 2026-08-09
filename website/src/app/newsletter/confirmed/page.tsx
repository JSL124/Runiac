import type { Metadata } from "next";
import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";
import { NewsletterStatusMessage } from "@/components/NewsletterStatusMessage";

// Redirect target for the confirmation link the backend email pipeline
// sends after a subscriber double-opt-in. Pure static markup: no Firestore
// read, so it renders correctly even with no Firebase credentials configured.

export const metadata: Metadata = {
  title: "Subscription confirmed | Runiac",
  description: "Your Runiac newsletter subscription is confirmed.",
};

export default function NewsletterConfirmedPage() {
  return (
    <>
      <Navbar />
      <main className="flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden">
        <NewsletterStatusMessage
          eyebrow="Newsletter"
          title="You're subscribed."
          description="Your email is confirmed. We'll only send occasional updates about Runiac's launch and progress — nothing else."
          tone="success"
        />
      </main>
      <Footer />
    </>
  );
}
