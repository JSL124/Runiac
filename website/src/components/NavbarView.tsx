"use client";

import Image from "next/image";
import Link from "next/link";
import { signOut } from "@/lib/actions/auth";

type NavItem = {
  readonly label: string;
  readonly href: string;
};

const navItems: readonly NavItem[] = [
  { label: "Runiac", href: "/#top" },
  { label: "Features", href: "/#journey-map" },
  { label: "Pricing", href: "/pricing" },
  { label: "FAQ", href: "/faq" },
  { label: "Documents", href: "/documents" },
  { label: "Download", href: "/download" },
  { label: "About us", href: "/about" },
];

const accountPillClasses =
  "group relative inline-flex shrink-0 items-center text-[11px] font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/35 focus-visible:ring-offset-4 sm:text-xs lg:text-sm rounded-full border border-brand/15 bg-brand px-4 py-2 text-white shadow-sm shadow-brand/10 hover:bg-brand/90";

type NavbarViewProps = {
  email: string | null;
  isAdmin: boolean;
  signedIn: boolean;
};

export function NavbarView({ email, isAdmin, signedIn }: NavbarViewProps) {
  const handleHomeTopClick = (event: React.MouseEvent<HTMLAnchorElement>) => {
    if (window.location.pathname !== "/") {
      return;
    }

    event.preventDefault();
    window.history.replaceState(null, "", "/");
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  // Email local-part (before "@") is a lightweight, non-sensitive display
  // label the client already has via the session cookie; no backend-owned
  // value is computed here.
  const displayLabel = email?.split("@")[0] || "Account";

  return (
    <header className="sticky top-0 z-50 w-full overflow-hidden border-b border-border/60 bg-white">
      <nav className="mx-auto flex box-border w-full max-w-[92rem] flex-wrap items-center gap-4 px-6 py-4 lg:flex-nowrap lg:px-0">
        <Link
          href="/#top"
          className="flex items-center"
          onClick={handleHomeTopClick}
          aria-label="Go to top"
        >
          <Image
            src="/runiac-wordmark-balanced.png"
            alt="Runiac"
            width={180}
            height={61}
            priority
            className="h-auto w-[150px] object-contain sm:w-[180px]"
          />
        </Link>
        <div className="ml-auto hidden min-w-0 flex-wrap items-center justify-end gap-x-3 gap-y-2 text-right md:flex lg:flex-nowrap">
          {navItems.map((item) => (
            <a
              key={item.label}
              href={item.href}
              onClick={item.label === "Runiac" ? handleHomeTopClick : undefined}
              className="group relative inline-flex shrink-0 items-center pb-1 text-[11px] font-bold text-foreground transition-colors hover:text-brand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/35 focus-visible:ring-offset-4 sm:text-xs lg:text-sm"
            >
              <span>{item.label}</span>
              <span
                className="absolute bottom-0 left-0 h-0.5 w-[calc(100%-1.25rem)] origin-left scale-x-0 rounded-full bg-accent transition-transform duration-200 group-hover:scale-x-100 sm:w-[calc(100%-1.5rem)]"
                aria-hidden="true"
              />
              <span
                className="ml-2 text-border transition-colors group-hover:text-brand/35 sm:ml-3"
                aria-hidden="true"
              >
                |
              </span>
            </a>
          ))}
          {signedIn ? (
            <div className="flex shrink-0 items-center gap-2">
              <span className="inline-flex shrink-0 items-center rounded-full border border-brand/15 bg-brand-soft px-4 py-2 text-[11px] font-bold text-brand sm:text-xs lg:text-sm">
                {displayLabel}
              </span>
              {isAdmin && (
                <Link href="/admin" className={accountPillClasses}>
                  <span>Admin</span>
                </Link>
              )}
              <form action={signOut}>
                <button
                  type="submit"
                  className="inline-flex shrink-0 items-center rounded-full border border-border bg-white px-4 py-2 text-[11px] font-bold text-foreground transition-colors hover:bg-brand-soft/35 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/35 focus-visible:ring-offset-4 sm:text-xs lg:text-sm"
                >
                  Sign out
                </button>
              </form>
            </div>
          ) : (
            <a href="/login" className={accountPillClasses}>
              <span>Sign in</span>
            </a>
          )}
        </div>
      </nav>
    </header>
  );
}
