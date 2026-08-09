"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { signOut } from "@/lib/actions/auth";

export type AdminNavItem = {
  href: string;
  label: string;
};

export const ADMIN_NAV: AdminNavItem[] = [
  { href: "/admin", label: "Overview" },
  { href: "/admin/exceptions", label: "Exception Queue" },
  { href: "/admin/users", label: "Users & Roles" },
  { href: "/admin/gamification", label: "XP & Gamification" },
  { href: "/admin/leaderboard", label: "Leaderboard" },
  { href: "/admin/paywall", label: "App Paywall" },
  { href: "/admin/content", label: "Website Content" },
  { href: "/admin/documents", label: "Project Documents" },
  { href: "/admin/feedback", label: "Feedback" },
  { href: "/admin/newsletter", label: "Newsletter" },
  { href: "/admin/errors", label: "App Errors" },
  { href: "/admin/policies", label: "Automation & Policy" },
  { href: "/admin/audit", label: "Governance & Audit" },
];

function isActive(pathname: string, href: string) {
  if (href === "/admin") {
    return pathname === "/admin";
  }

  return pathname === href || pathname.startsWith(`${href}/`);
}

function Wordmark() {
  return (
    <div className="flex items-center gap-2.5">
      <Link
        href="/"
        aria-label="Runiac home"
        className="flex items-center rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/25"
      >
        <Image
          src="/runiac-wordmark-balanced.png"
          alt="Runiac"
          width={180}
          height={61}
          priority
          className="h-auto w-[112px] object-contain"
        />
      </Link>
      <span className="rounded-full bg-accent-soft px-2 py-0.5 text-[0.65rem] font-bold uppercase tracking-[0.12em] text-accent">
        Admin
      </span>
    </div>
  );
}

function NavLinks({
  pathname,
  onNavigate,
}: {
  pathname: string;
  onNavigate?: () => void;
}) {
  return (
    <nav aria-label="Admin sections" className="flex flex-col gap-0.5">
      {ADMIN_NAV.map((item) => {
        const active = isActive(pathname, item.href);

        return (
          <Link
            key={item.href}
            href={item.href}
            onClick={onNavigate}
            aria-current={active ? "page" : undefined}
            className={`rounded-lg px-3 py-2 text-sm font-semibold transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/25 ${
              active
                ? "bg-brand text-white"
                : "text-foreground hover:bg-brand-soft/70 hover:text-brand"
            }`}
          >
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}

function SignOutBlock({ adminEmail }: { adminEmail: string }) {
  return (
    <div className="border-t border-border px-4 py-4">
      <p className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
        Signed in as
      </p>
      <p className="mt-1 truncate text-sm font-semibold text-brand" title={adminEmail}>
        {adminEmail}
      </p>
      <form action={signOut} className="mt-3">
        <button
          type="submit"
          className="inline-flex h-9 w-full items-center justify-center rounded-lg border border-border bg-white text-sm font-bold text-brand transition-colors duration-150 hover:border-brand/25 hover:bg-brand-soft/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/25"
        >
          Sign out
        </button>
      </form>
    </div>
  );
}

export function AdminSidebar({ adminEmail }: { adminEmail: string }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const current =
    ADMIN_NAV.find((item) => isActive(pathname, item.href))?.label ?? "Admin";

  return (
    <>
      {/* Desktop fixed sidebar */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-64 flex-col border-r border-border bg-white lg:flex">
        <div className="border-b border-border px-4 py-5">
          <Wordmark />
        </div>
        <div className="flex-1 overflow-y-auto px-3 py-4">
          <NavLinks pathname={pathname} />
        </div>
        <SignOutBlock adminEmail={adminEmail} />
      </aside>

      {/* Mobile top bar + drawer */}
      <div className="sticky top-0 z-40 flex items-center justify-between border-b border-border bg-white px-4 py-3 lg:hidden">
        <Wordmark />
        <button
          type="button"
          onClick={() => setOpen((value) => !value)}
          aria-expanded={open}
          aria-label={open ? "Close navigation" : "Open navigation"}
          className="inline-flex h-9 items-center gap-2 rounded-lg border border-border bg-white px-3 text-sm font-bold text-brand transition-colors hover:bg-brand-soft/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/25"
        >
          <span className="max-w-[9rem] truncate">{current}</span>
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            className={`h-4 w-4 transition-transform duration-150 ${open ? "rotate-180" : ""}`}
            aria-hidden="true"
          >
            <path d="M6 9l6 6 6-6" />
          </svg>
        </button>
      </div>

      {open ? (
        <div className="sticky top-[57px] z-30 border-b border-border bg-white px-3 py-3 lg:hidden">
          <NavLinks pathname={pathname} onNavigate={() => setOpen(false)} />
          <div className="mt-3">
            <SignOutBlock adminEmail={adminEmail} />
          </div>
        </div>
      ) : null}
    </>
  );
}
