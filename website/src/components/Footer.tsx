import Image from "next/image";

const columns = [
  {
    title: "Product",
    links: [
      { label: "Beginner journey", href: "/how-it-works#journey" },
      { label: "Features", href: "/features" },
      { label: "Prototype", href: "/#cta" },
    ],
  },
  {
    title: "Resources",
    links: [
      { label: "Why beginners stop", href: "/#problem" },
      { label: "How it works", href: "/how-it-works" },
      { label: "FAQ", href: "/faq" },
      { label: "Contact", href: "#" },
    ],
  },
  {
    title: "Legal",
    links: [
      { label: "Privacy", href: "/legal/privacy" },
      { label: "Terms", href: "/legal/terms" },
      { label: "Cookies", href: "/legal/cookies" },
    ],
  },
];

export function Footer() {
  return (
    <footer className="w-full border-t border-border bg-background px-6 py-16">
      <div className="mx-auto grid max-w-6xl gap-12 lg:grid-cols-[1.4fr_3fr]">
        <div>
          <div className="flex items-center">
            <Image
              src="/runiac-wordmark-balanced.png"
              alt="Runiac"
              width={170}
              height={58}
              className="h-auto w-[170px] object-contain"
            />
          </div>
          <p className="mt-4 max-w-sm text-sm leading-relaxed text-muted">
            A calm, beginner-friendly running companion that turns the first
            twelve weeks into a habit that lasts.
          </p>
        </div>

        <div className="grid grid-cols-2 gap-8 sm:grid-cols-3">
          {columns.map((col) => (
            <div key={col.title}>
              <h3 className="text-xs font-semibold uppercase tracking-widest text-foreground">
                {col.title}
              </h3>
              <ul className="mt-4 space-y-2.5">
                {col.links.map((link) => (
                  <li key={link.label}>
                    <a
                      href={link.href}
                      className="text-sm text-muted transition-colors hover:text-brand"
                    >
                      {link.label}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>
      <div className="mx-auto mt-12 flex max-w-6xl flex-col items-start justify-between gap-3 border-t border-border pt-6 text-xs text-muted sm:flex-row sm:items-center">
        <p>© {new Date().getFullYear()} Runiac. All rights reserved.</p>
        <p>Built for beginner runners.</p>
      </div>
    </footer>
  );
}
