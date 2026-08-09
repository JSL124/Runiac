// Shared Tailwind class strings for admin buttons and inputs. Stable heights,
// focus-visible rings (ring-brand/25 idiom), color/transform/shadow transitions
// only (respecting prefers-reduced-motion via Tailwind's motion-reduce).

const base =
  "inline-flex h-9 items-center justify-center gap-1.5 rounded-lg px-3.5 text-sm font-bold transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/25 disabled:cursor-not-allowed disabled:opacity-60";

export const btnPrimary = `${base} bg-accent text-white hover:bg-accent/90 focus-visible:ring-accent/30`;

export const btnBrand = `${base} bg-brand text-white hover:bg-brand/90`;

export const btnSecondary = `${base} border border-border bg-white text-brand hover:border-brand/25 hover:bg-brand-soft/60`;

export const btnDanger = `${base} border border-[#f0c2bc] bg-white text-[#b42318] hover:bg-[#fdecea]`;

export const btnGhost = `${base} text-brand hover:bg-brand-soft/70`;

export const inputBase =
  "h-9 w-full rounded-lg border border-border bg-white px-3 text-sm font-semibold text-foreground outline-none transition-colors duration-150 placeholder:text-muted/60 hover:border-brand/30 focus:border-brand focus:ring-2 focus:ring-brand/15 disabled:cursor-not-allowed disabled:opacity-60";
