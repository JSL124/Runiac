"use client";

import { useCallback, useMemo, useState, type ReactNode } from "react";

// Rows shown per page; anything beyond this is reached with the chevrons.
export const ROWS_PER_PAGE = 10;

// Sentinel for an elided run of page numbers. -1 can never be a real page
// index, so it needs no separate discriminator.
const ELLIPSIS = -1;

export type Pagination<T> = {
  items: T[];
  visible: T[];
  currentPage: number;
  pageCount: number;
  pageStart: number;
  pageNumbers: number[];
  goToPage: (next: number) => void;
};

/**
 * Pages over a list already held in memory, so moving between pages is instant
 * and never refetches. Widening the server window (where that is possible at
 * all) stays the caller's job.
 */
export function usePagination<T>(
  items: T[],
  options?: { rowsPerPage?: number; onPageChange?: () => void; resetKey?: unknown },
): Pagination<T> {
  const rowsPerPage = options?.rowsPerPage ?? ROWS_PER_PAGE;
  const onPageChange = options?.onPageChange;
  const [pageIndex, setPageIndex] = useState(0);

  // A new list means a different result set — a server refresh, or a filter the
  // caller re-derived. Keeping the old page index would land the admin
  // somewhere arbitrary in it, or past its end.
  //
  // Array identity is the right signal only when the list changes solely
  // because the result set changed. A caller that also rebuilds the array for
  // in-place row edits (an optimistic update after a mutation) must pass an
  // explicit `resetKey` instead, or every such edit would snap the admin back
  // to page 1 mid-workflow.
  const resetSignal =
    options !== undefined && "resetKey" in options ? options.resetKey : items;
  const [prevResetSignal, setPrevResetSignal] = useState(resetSignal);
  if (prevResetSignal !== resetSignal) {
    setPrevResetSignal(resetSignal);
    setPageIndex(0);
  }

  const pageCount = Math.max(1, Math.ceil(items.length / rowsPerPage));
  // Clamped rather than stored blind: a shrinking result set can leave the
  // stored index past the end, which would render an empty page with no way
  // back.
  const currentPage = Math.min(pageIndex, pageCount - 1);
  const pageStart = currentPage * rowsPerPage;
  const visible = items.slice(pageStart, pageStart + rowsPerPage);

  // Compact page list: always the first and last page, the current page and its
  // neighbours, with gaps elided. Keeps the control a fixed width no matter how
  // many pages exist.
  const pageNumbers = useMemo(() => {
    if (pageCount <= 7) {
      return Array.from({ length: pageCount }, (_, index) => index);
    }

    const shown = new Set<number>([
      0,
      pageCount - 1,
      currentPage - 1,
      currentPage,
      currentPage + 1,
    ]);
    const ordered = [...shown]
      .filter((page) => page >= 0 && page < pageCount)
      .sort((a, b) => a - b);

    const withGaps: number[] = [];
    let previous: number | null = null;
    for (const page of ordered) {
      if (previous !== null && page - previous > 1) {
        withGaps.push(ELLIPSIS);
      }
      withGaps.push(page);
      previous = page;
    }
    return withGaps;
  }, [pageCount, currentPage]);

  const goToPage = useCallback(
    (next: number) => {
      setPageIndex(Math.min(Math.max(next, 0), pageCount - 1));
      onPageChange?.();
    },
    [pageCount, onPageChange],
  );

  return {
    items,
    visible,
    currentPage,
    pageCount,
    pageStart,
    pageNumbers,
    goToPage,
  };
}

function PagerButton({
  label,
  direction,
  disabled,
  onClick,
}: {
  label: string;
  direction: "prev" | "next";
  disabled: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-white text-foreground transition hover:bg-brand-soft/40 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-white"
    >
      <svg
        viewBox="0 0 20 20"
        className="h-4 w-4"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <path d={direction === "prev" ? "M12.5 4.5 7 10l5.5 5.5" : "M7.5 4.5 13 10l-5.5 5.5"} />
      </svg>
    </button>
  );
}

/**
 * Chevron pager for a `usePagination` list. Renders nothing when the list is
 * empty; the page numbers appear only once there is more than one page, so a
 * short list is not dressed up with dead controls. `children` (e.g. a "load
 * more" control) still renders whenever there are rows.
 */
export function Pager<T>({
  pagination,
  label,
  children,
}: {
  pagination: Pagination<T>;
  label: string;
  children?: ReactNode;
}) {
  const { items, visible, currentPage, pageCount, pageStart, pageNumbers, goToPage } =
    pagination;

  if (items.length === 0) {
    return null;
  }

  return (
    <div className="flex flex-col items-center gap-3 sm:flex-row sm:justify-between">
      <p className="text-sm text-muted">
        Showing {pageStart + 1}&ndash;{pageStart + visible.length} of {items.length}
      </p>

      {pageCount > 1 ? (
        <nav className="flex items-center gap-1" aria-label={label}>
          <PagerButton
            label="Previous page"
            direction="prev"
            disabled={currentPage === 0}
            onClick={() => goToPage(currentPage - 1)}
          />

          {pageNumbers.map((page, index) =>
            page === ELLIPSIS ? (
              <span
                key={`gap-${index}`}
                aria-hidden="true"
                className="px-1 text-sm text-muted"
              >
                &hellip;
              </span>
            ) : (
              <button
                key={page}
                type="button"
                aria-label={`Page ${page + 1}`}
                aria-current={page === currentPage ? "page" : undefined}
                onClick={() => goToPage(page)}
                className={
                  page === currentPage
                    ? "min-w-8 rounded-lg border border-brand bg-brand px-2 py-1 text-sm font-bold text-white"
                    : "min-w-8 rounded-lg border border-border bg-white px-2 py-1 text-sm font-semibold text-foreground hover:bg-brand-soft/40"
                }
              >
                {page + 1}
              </button>
            ),
          )}

          <PagerButton
            label="Next page"
            direction="next"
            disabled={currentPage >= pageCount - 1}
            onClick={() => goToPage(currentPage + 1)}
          />
        </nav>
      ) : null}

      {children ?? null}
    </div>
  );
}
