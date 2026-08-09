import { BeginnerJourney } from "@/components/BeginnerJourney";
import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";

export default function HowItWorksPage() {
  return (
    <>
      <Navbar />
      <main className="flex flex-1 flex-col">
        <BeginnerJourney />
      </main>
      <Footer />
    </>
  );
}
