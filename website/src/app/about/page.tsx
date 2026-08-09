import { Footer } from "@/components/Footer";
import { Navbar } from "@/components/Navbar";
import { TeamMemberCard } from "@/components/TeamMemberCard";
import { getSiteContentWithFallback } from "@/lib/site-content";

const containerStyle = {
  width: "calc(100vw - 3rem)",
  maxWidth: "72rem",
};

export default async function AboutPage() {
  const { team } = await getSiteContentWithFallback();
  const { supervisor } = team;

  return (
    <>
      <Navbar />
      <main className="about-page flex w-[100vw] max-w-[100vw] min-w-0 flex-1 flex-col overflow-x-hidden">
        <section className="box-border w-full bg-background px-0 py-20 sm:py-24 lg:py-28">
          <div className="mx-auto" style={containerStyle}>
            <div className="max-w-3xl">
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand sm:text-sm">
                {team.eyebrow}
              </p>
              <h2 className="mt-4 text-3xl font-semibold italic leading-[1.15] tracking-normal text-brand sm:text-4xl lg:text-5xl">
                {team.heading}
              </h2>
              <p className="mt-5 text-base leading-relaxed text-muted sm:text-lg">
                {team.body}
              </p>
            </div>

            <div className="mt-10 grid gap-6 md:grid-cols-2 lg:grid-cols-3">
              {team.members.map((member) => (
                <TeamMemberCard key={member.name} member={member} />
              ))}
            </div>

            <div className="mt-12 rounded-lg border border-border bg-white p-6 shadow-[0_24px_70px_-50px_rgba(0,30,98,0.36)] sm:p-8">
              <div className="grid gap-6 sm:grid-cols-[auto_1fr] sm:items-center">
                <div className="flex h-16 w-16 items-center justify-center rounded-full border border-brand/15 bg-brand-soft text-xl font-bold text-brand">
                  {supervisor.name
                    .split(" ")
                    .map((part) => part[0])
                    .join("")
                    .slice(0, 2)}
                </div>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand">
                    {team.supervisorLabel}
                  </p>
                  <h3 className="mt-2 text-2xl font-semibold text-foreground">
                    {supervisor.name}
                  </h3>
                  <p className="mt-1 text-sm font-semibold text-brand">
                    {supervisor.role}
                  </p>
                  {supervisor.email ? (
                    <a
                      href={`mailto:${supervisor.email}`}
                      className="mt-3 inline-flex text-sm font-semibold text-muted transition-colors hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/35 focus-visible:ring-offset-4"
                    >
                      {supervisor.email}
                    </a>
                  ) : null}
                  <p className="mt-3 max-w-2xl text-sm leading-relaxed text-muted">
                    {supervisor.bio}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
