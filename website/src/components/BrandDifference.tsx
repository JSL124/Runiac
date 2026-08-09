import Image from "next/image";
import { Eyebrow } from "./SectionShell";

const weeklyPlanItems = ["Easy run", "Rest day", "XP reflection"];

const beliefCards = [
  {
    title: "Beginner-first",
    body: "We design for people who are still building confidence with running.",
  },
  {
    title: "Consistency over perfection",
    body: "Runiac rewards regular effort, plan adherence, and small improvements, not only speed or distance.",
  },
  {
    title: "Fair motivation",
    body: "Users compete with runners at a similar level, making progress feel achievable instead of intimidating.",
  },
  {
    title: "Safe progression",
    body: "Running plans and reminders support gradual improvement and reduce the risk of doing too much too soon.",
  },
];

function WeeklyPlanCard() {
  return (
    <div className="w-full rounded-lg bg-white p-6 shadow-[0_28px_80px_-34px_rgba(0,30,98,0.5)] sm:p-8">
      <p className="text-[0.68rem] font-bold uppercase tracking-[0.26em] text-brand">
        Weekly plan
      </p>
      <h3 className="mt-4 text-2xl font-bold tracking-tight text-foreground sm:text-3xl">
        Tiny Wins
      </h3>
      <div className="mt-6 space-y-3">
        {weeklyPlanItems.map((item) => (
          <div
            key={item}
            className="flex min-h-14 items-center justify-between rounded-lg border border-border bg-white px-4 text-sm font-bold text-foreground sm:min-h-16 sm:px-5 sm:text-base"
          >
            <span>{item}</span>
            <span
              aria-hidden="true"
              className="h-3 w-3 rounded-full bg-accent"
            />
          </div>
        ))}
      </div>
    </div>
  );
}

export function BrandDifference() {
  return (
    <section
      id="brand-difference"
      className="w-full bg-background px-6 py-24 sm:py-28 lg:py-32"
    >
      <div className="mx-auto max-w-[92rem] min-w-0 space-y-28 lg:space-y-36">
        <div className="grid items-center gap-12 lg:grid-cols-[0.92fr_1.08fr] lg:gap-20">
          <div className="min-w-0 max-w-2xl">
            <Eyebrow>What makes Runiac different</Eyebrow>
            <h2 className="max-w-full break-words text-[2.25rem] font-bold italic leading-[1.12] tracking-normal text-brand sm:text-6xl sm:leading-[1.1] lg:text-7xl">
              A behavior-change running app, not just a tracker.
            </h2>
            <p className="mt-8 max-w-[42rem] break-words text-lg leading-relaxed text-muted sm:text-xl">
              Instead of only showing raw metrics, Runiac helps users understand
              progress, follow personalized running plans, receive reminders,
              maintain streaks, earn XP, review post-run summaries, and stay
              motivated through fair level-based territorial leaderboards.
            </p>
          </div>

          <div className="relative min-h-[520px] min-w-0 sm:min-h-[600px] lg:min-h-[620px]">
            <div className="absolute right-0 top-0 h-[430px] w-full max-w-[640px] overflow-hidden rounded-lg shadow-[0_32px_90px_-44px_rgba(0,30,98,0.55)] sm:h-[520px] lg:h-[560px]">
              <Image
                src="/about-running-shoe.jpeg"
                alt="Runner in bright shoes captured from a low angle"
                fill
                sizes="(min-width: 1024px) 42vw, 90vw"
                className="object-cover object-[center_44%]"
              />
            </div>
            <div className="absolute bottom-0 left-0 w-full max-w-[560px] lg:left-[-7%] xl:left-[-10%]">
              <WeeklyPlanCard />
            </div>
          </div>
        </div>

        <div className="space-y-12">
          <div className="grid items-end gap-10 lg:grid-cols-[0.82fr_1.18fr] lg:gap-16">
            <div className="min-w-0">
              <Eyebrow>What we believe</Eyebrow>
              <h2 className="break-words text-[2.35rem] font-bold italic leading-[1.1] tracking-normal text-brand sm:text-6xl sm:leading-[1.08] lg:text-7xl">
                Running should feel achievable before it feels competitive.
              </h2>
            </div>
            <div className="relative h-[260px] min-w-0 overflow-hidden rounded-lg shadow-[0_30px_84px_-42px_rgba(0,30,98,0.5)] sm:h-[340px] lg:h-[350px]">
              <Image
                src="/about-community-race.jpeg"
                alt="Group of runners smiling during a community race"
                fill
                sizes="(min-width: 1024px) 56vw, 90vw"
                className="object-cover object-[center_44%]"
              />
            </div>
          </div>

          <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
            {beliefCards.map((card) => (
              <article
                key={card.title}
                className="min-h-[230px] min-w-0 rounded-lg border border-border bg-white p-6 sm:p-8"
              >
                <h3 className="break-words text-xl font-bold leading-snug tracking-tight text-foreground">
                  {card.title}
                </h3>
                <p className="mt-5 break-words text-base leading-relaxed text-muted">
                  {card.body}
                </p>
              </article>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
