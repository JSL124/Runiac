import Image from "next/image";
import type { ReactNode } from "react";
import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";

// Shared frame for the three account pages (sign in, sign up, reset
// password): the photo panel on the left, the form column on the right. The
// pages differ only in their copy and their form, so the layout lives here
// rather than being pasted three times.

const authPhotos = [
  {
    src: "/login-random-run-01.jpeg",
    alt: "A runner moving through a city from a low motion-blur angle",
  },
  {
    src: "/login-random-run-02.jpeg",
    alt: "A group of runners moving through a sunny city street",
  },
  {
    src: "/login-random-run-03.jpeg",
    alt: "A running group seen from above on a paved city path",
  },
  {
    src: "/login-random-run-04.jpeg",
    alt: "Two runners moving through warm evening light",
  },
] as const;

// Pages that use this layout set `export const dynamic = "force-dynamic"` so a
// fresh photo is picked per visit rather than baked in at build time.
export function getRandomAuthPhoto() {
  const index = Math.floor(Math.random() * authPhotos.length);

  return authPhotos[index] ?? authPhotos[0];
}

export function AuthPageLayout({
  photo,
  panelEyebrow,
  panelHeading,
  title,
  subtitle,
  children,
}: {
  photo: { src: string; alt: string };
  panelEyebrow: string;
  panelHeading: string;
  title: string;
  subtitle: string;
  children: ReactNode;
}) {
  return (
    <>
      <Navbar />
      <main className="flex flex-1 bg-background">
        <section className="mx-auto grid box-border w-full max-w-[76rem] gap-8 px-6 py-10 sm:py-12 lg:min-h-[calc(100dvh-94px)] lg:grid-cols-[1.02fr_0.98fr] lg:items-center lg:gap-12 lg:px-8 lg:py-14">
          <div className="relative hidden min-w-0 overflow-hidden rounded-lg border border-border bg-brand shadow-[0_30px_80px_-48px_rgba(0,30,98,0.55)] lg:block lg:min-h-[42rem]">
            <Image
              src={photo.src}
              alt={photo.alt}
              fill
              priority
              sizes="38rem"
              className="object-cover object-center"
            />
            <div
              className="absolute inset-0 bg-[linear-gradient(180deg,rgba(0,30,98,0.04)_0%,rgba(0,30,98,0.26)_45%,rgba(0,16,20,0.82)_100%)]"
              aria-hidden="true"
            />
            <div className="absolute inset-x-0 bottom-0 z-10 p-6 text-white sm:p-8 lg:p-10">
              <p className="text-xs font-bold uppercase tracking-[0.14em] text-white/75">
                {panelEyebrow}
              </p>
              <h1 className="mt-3 max-w-md text-4xl font-black leading-[1.05] tracking-normal sm:text-5xl">
                {panelHeading}
              </h1>
            </div>
          </div>

          <div className="mx-auto box-border w-full min-w-0 max-w-[31rem] lg:mx-0 lg:-translate-y-12 lg:justify-self-end">
            <div className="mb-8">
              <h2 className="text-4xl font-black leading-[1.08] tracking-normal text-brand sm:text-5xl">
                {title}
              </h2>
              <p className="mt-3 text-base font-semibold leading-7 text-brand/82 sm:text-lg">
                {subtitle}
              </p>
            </div>

            {children}
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
