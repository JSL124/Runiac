import { getCurrentUser } from "@/lib/auth";
import { NavbarView } from "@/components/NavbarView";

type AnnouncementBannerProps = {
  enabled: boolean;
  text: string;
};

// Slim site-wide announcement banner, sourced from the admin-editable
// config/siteContent doc (see src/lib/site-content.ts). Renders nothing when
// disabled or empty, matching today's default (no banner) when the doc is
// absent.
export function AnnouncementBanner({ enabled, text }: AnnouncementBannerProps) {
  if (!enabled || !text) {
    return null;
  }

  return (
    <div className="w-full bg-brand px-6 py-2 text-center text-xs font-semibold text-white sm:text-sm">
      {text}
    </div>
  );
}

// Resolves the caller's session server-side (see src/lib/auth.ts) so the
// account area renders the right state on first paint: signed-out keeps the
// existing "Sign in" pill, signed-in swaps it for a user chip, an admin-only
// link, and a sign-out button. All interactive markup lives in NavbarView.
export async function Navbar() {
  const { user, isAdmin } = await getCurrentUser();

  return (
    <NavbarView
      email={user?.email ?? null}
      isAdmin={isAdmin}
      signedIn={user !== null}
    />
  );
}
