import { UserManagement } from "@/components/admin/UserManagement";
import { PageHeader } from "@/components/admin/primitives";
import {
  DEFAULT_USER_PAGE_SIZE,
  MAX_USER_PAGE_SIZE,
  getUserActionHistory,
  getUsers,
} from "@/lib/admin/data";

export const dynamic = "force-dynamic";

function readPageSize(raw: string | string[] | undefined): number {
  const value = Number(Array.isArray(raw) ? raw[0] : raw);

  if (!Number.isFinite(value) || value <= 0) {
    return DEFAULT_USER_PAGE_SIZE;
  }

  return Math.min(Math.floor(value), MAX_USER_PAGE_SIZE);
}

// Search and page size come from the URL rather than component state, so a
// search re-reads from Firestore instead of filtering only the rows already on
// screen. That widens the net but does not remove it: an email or uid is looked
// up directly, while a partial name is matched over the scanned window, so the
// window state is passed down and surfaced rather than hidden.
export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const rawQuery = Array.isArray(params.q) ? params.q[0] : params.q;
  const query = rawQuery?.trim() ?? "";
  const pageSize = readPageSize(params.limit);

  const [usersPage, history] = await Promise.all([
    getUsers(query, pageSize),
    getUserActionHistory(),
  ]);

  // Deliberately derived from the scan, not from `usersPage.users.length`:
  // the result set is post-filter, so a search matching two accounts out of a
  // full window would otherwise hide the only control that widens the search.
  const canLoadMore = usersPage.windowFull && pageSize < MAX_USER_PAGE_SIZE;

  return (
    <>
      <PageHeader title="Users & Roles" />
      <UserManagement
        users={usersPage.users}
        history={history}
        query={query}
        pageSize={pageSize}
        canLoadMore={canLoadMore}
        searchWindowLimited={
          query.length > 0 && usersPage.windowFull && !usersPage.resolvedExactly
        }
      />
    </>
  );
}
