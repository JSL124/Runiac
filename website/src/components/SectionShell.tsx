import type { ReactNode } from "react";

export function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <p className="mb-4 text-xs sm:text-sm font-semibold uppercase tracking-[0.18em] text-brand">
      {children}
    </p>
  );
}

type SectionShellProps = {
  id?: string;
  eyebrow?: string;
  title?: ReactNode;
  lead?: ReactNode;
  align?: "center" | "left";
  containerClassName?: string;
  className?: string;
  children: ReactNode;
};

export function SectionShell({
  id,
  eyebrow,
  title,
  lead,
  align = "center",
  containerClassName = "",
  className = "",
  children,
}: SectionShellProps) {
  const alignClass = align === "center" ? "text-center mx-auto" : "text-left";
  return (
    <section
      id={id}
      className={`w-full px-6 py-24 sm:py-28 lg:py-32 ${className}`}
    >
      <div className={`mx-auto max-w-6xl ${containerClassName}`}>
        {(eyebrow || title || lead) && (
          <header className={`max-w-3xl ${alignClass} mb-14 sm:mb-20`}>
            {eyebrow && <Eyebrow>{eyebrow}</Eyebrow>}
            {title && (
              <h2 className="text-3xl sm:text-4xl lg:text-5xl font-semibold leading-[1.15] tracking-tight">
                {title}
              </h2>
            )}
            {lead && (
              <p className="mt-5 text-base sm:text-lg leading-relaxed text-muted">
                {lead}
              </p>
            )}
          </header>
        )}
        {children}
      </div>
    </section>
  );
}
