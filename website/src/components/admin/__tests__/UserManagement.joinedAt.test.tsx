import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";

import { UserManagement } from "../UserManagement";
import { ADMIN_USERS } from "@/lib/admin/mock-data";
import type { AdminUser } from "@/lib/admin/types";

vi.mock("@/lib/actions/admin", () => ({
  changeUserRole: vi.fn(),
  setUserAccountStatus: vi.fn(),
  clearUserAvatar: vi.fn(),
  adjustUserXp: vi.fn(),
  grantPremium: vi.fn(),
  revokePremium: vi.fn(),
  resetUserStreak: vi.fn(),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }),
}));

const base = ADMIN_USERS[0]!;

function renderTable(users: AdminUser[]) {
  render(
    <UserManagement
      users={users}
      history={[]}
      query=""
      pageSize={25}
      canLoadMore={false}
      searchWindowLimited={false}
    />,
  );
}

describe("UserManagement joined date", () => {
  it("renders a dash, not an epoch date, when the account has no resolvable creation time", () => {
    renderTable([{ ...base, id: "u-1", uid: "u-1", joinedAt: null }]);

    // The regression this guards: joinedAt used to be defaulted to
    // 1970-01-01T00:00:00.000Z in live-data.ts, so every account in the console
    // reported a January 1970 join date as though it were real.
    expect(screen.queryByText(/1970/)).not.toBeInTheDocument();
    expect(screen.getByText("—")).toBeInTheDocument();
  });

  it("still formats a real creation time", () => {
    renderTable([
      { ...base, id: "u-2", uid: "u-2", joinedAt: "2026-08-10T07:00:00.000Z" },
    ]);

    expect(screen.getByText(/10 Aug 2026/)).toBeInTheDocument();
  });
});
