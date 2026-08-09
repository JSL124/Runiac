import type { ComponentPropsWithoutRef } from "react";

type Variant = "primary" | "secondary" | "ghost";

type CtaButtonProps = ComponentPropsWithoutRef<"a"> & {
  variant?: Variant;
};

const base =
  "inline-flex items-center justify-center rounded-full px-6 py-3 text-sm sm:text-base font-medium transition-all duration-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-background";

const variants: Record<Variant, string> = {
  primary:
    "bg-accent text-white hover:bg-accent/90 hover:-translate-y-px shadow-sm focus-visible:ring-accent",
  secondary:
    "bg-brand text-white hover:bg-brand/90 hover:-translate-y-px shadow-sm focus-visible:ring-brand",
  ghost:
    "bg-transparent text-brand hover:bg-brand-soft border border-brand/20 focus-visible:ring-brand",
};

export function CtaButton({
  variant = "primary",
  className = "",
  children,
  ...props
}: CtaButtonProps) {
  return (
    <a className={`${base} ${variants[variant]} ${className}`} {...props}>
      {children}
    </a>
  );
}
