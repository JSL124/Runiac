import Image from "next/image";
import { HeroEmailSignup } from "./HeroEmailSignup";

const DEFAULT_HEADLINE = "Run consistent,\nRun together.";
const DEFAULT_SUBTEXT = "";

type HeroProps = {
  headline?: string;
  subtext?: string;
};

export function Hero({
  headline = DEFAULT_HEADLINE,
  subtext = DEFAULT_SUBTEXT,
}: HeroProps) {
  const headlineLines = headline.split("\n");

  return (
    <section
      id="top"
      className="relative w-full overflow-hidden px-0 pt-0 pb-16 lg:min-h-[640px] lg:pb-24 xl:min-h-[720px]"
    >
      <div
        className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[560px] bg-background lg:h-full"
        aria-hidden="true"
      />
      <div className="mx-auto flex max-w-[92rem] flex-col items-stretch gap-10 lg:min-h-[640px] lg:justify-center xl:min-h-[720px]">
        <div className="relative order-1 lg:absolute lg:inset-y-0 lg:right-0 lg:order-none lg:w-[78vw]">
          <Image
            src="/runiac-singapore-runners.png"
            alt="Two runners jogging by Marina Bay in Singapore at sunrise"
            width={1448}
            height={1086}
            priority
            sizes="(min-width: 1024px) 78vw, 100vw"
            className="aspect-[4/3] w-full object-cover object-[58%_center] md:aspect-[3/2] lg:h-full lg:aspect-auto lg:object-[62%_center]"
          />
          <div
            aria-hidden="true"
            className="pointer-events-none absolute inset-y-0 left-0 hidden w-[60%] bg-gradient-to-r from-background from-10% via-background/90 via-48% to-transparent lg:block"
          />
        </div>

        <div className="relative z-10 order-2 mx-auto w-full max-w-none px-6 text-center lg:order-none lg:mx-0 lg:w-[34rem] lg:px-0 lg:pr-4 lg:text-left">
          <h1 className="font-['Sprintura_Demo',var(--font-inter),sans-serif] text-[1.35rem] font-normal leading-[1.05] tracking-normal text-[#4058b0] sm:text-4xl lg:text-5xl">
            {headlineLines.map((line, index) => (
              <span key={`${line}-${index}`} className="block">
                {line}
                {index < headlineLines.length - 1 ? " " : null}
              </span>
            ))}
          </h1>
          {subtext ? (
            <p className="mt-4 max-w-xl text-sm font-semibold leading-relaxed text-muted sm:text-base">
              {subtext}
            </p>
          ) : null}
          <HeroEmailSignup />
        </div>
      </div>
    </section>
  );
}
