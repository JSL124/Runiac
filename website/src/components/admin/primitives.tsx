import type { ReactNode } from "react";
import type {
  ErrorStatus,
  ExceptionStatus,
  FeedbackStatus,
  Severity,
  SystemStatus,
} from "@/lib/admin/types";

// Shared, presentational building blocks for the admin console. These follow
// the Runiac design system: white cards, 1px borders, 8px radius, soft
// blue-tinted shadows, brand-blue headings, orange used sparingly.

const CARD_SHADOW = "shadow-[0_18px_48px_-40px_rgba(0,30,98,0.55)]";

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
}) {
  return (
    <header className="flex flex-col gap-4 border-b border-border pb-6 sm:flex-row sm:items-end sm:justify-between">
      <div className="max-w-2xl">
        <h1 className="text-2xl font-black leading-tight tracking-tight text-brand sm:text-3xl">
          {title}
        </h1>
        {description ? (
          <p className="mt-2 text-sm leading-relaxed text-muted">
            {description}
          </p>
        ) : null}
      </div>
      {actions ? <div className="flex flex-wrap gap-2">{actions}</div> : null}
    </header>
  );
}

export function Card({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`rounded-lg border border-border bg-white ${CARD_SHADOW} ${className}`}
    >
      {children}
    </div>
  );
}

export function AdminSection({
  title,
  description,
  actions,
  children,
  className = "",
}: {
  title?: string;
  description?: string;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <Card className={className}>
      {title || description || actions ? (
        <div className="flex flex-col gap-3 border-b border-border px-5 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6">
          <div>
            {title ? (
              <h2 className="text-base font-bold text-brand">{title}</h2>
            ) : null}
            {description ? (
              <p className="mt-1 text-sm leading-relaxed text-muted">
                {description}
              </p>
            ) : null}
          </div>
          {actions ? (
            <div className="flex flex-wrap gap-2">{actions}</div>
          ) : null}
        </div>
      ) : null}
      <div className="p-5 sm:p-6">{children}</div>
    </Card>
  );
}

export function CaptionLabel({ children }: { children: ReactNode }) {
  return (
    <span className="text-[0.7rem] font-bold uppercase tracking-[0.12em] text-muted">
      {children}
    </span>
  );
}

export function StatCard({
  label,
  value,
  hint,
  tone = "neutral",
}: {
  label: string;
  value: ReactNode;
  hint?: string;
  tone?: "neutral" | "accent" | "critical";
}) {
  const valueTone =
    tone === "critical"
      ? "text-[#b42318]"
      : tone === "accent"
        ? "text-accent"
        : "text-brand";

  return (
    <Card className="p-5">
      <CaptionLabel>{label}</CaptionLabel>
      <p className={`mt-3 text-3xl font-black tabular-nums ${valueTone}`}>
        {value}
      </p>
      {hint ? <p className="mt-1 text-xs text-muted">{hint}</p> : null}
    </Card>
  );
}

const SEVERITY_STYLES: Record<Severity, string> = {
  low: "border-border bg-brand-soft text-brand",
  medium: "border-accent/25 bg-accent-soft text-accent",
  high: "border-accent/40 bg-accent-soft text-accent",
  critical: "border-[#f0c2bc] bg-[#fdecea] text-[#b42318]",
};

export function SeverityBadge({ severity }: { severity: Severity }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[0.7rem] font-bold uppercase tracking-[0.08em] ${SEVERITY_STYLES[severity]}`}
    >
      {severity === "critical" ? (
        <span
          aria-hidden="true"
          className="h-1.5 w-1.5 rounded-full bg-[#b42318]"
        />
      ) : null}
      {severity}
    </span>
  );
}

const SYSTEM_STATUS_STYLES: Record<
  SystemStatus,
  { dot: string; text: string; wrap: string; label: string }
> = {
  operational: {
    dot: "bg-[#12805c]",
    text: "text-[#0f6b4e]",
    wrap: "border-[#bfe3d3] bg-[#eafaf3]",
    label: "Operational",
  },
  degraded: {
    dot: "bg-accent",
    text: "text-accent",
    wrap: "border-accent/25 bg-accent-soft",
    label: "Degraded",
  },
  down: {
    dot: "bg-[#b42318]",
    text: "text-[#b42318]",
    wrap: "border-[#f0c2bc] bg-[#fdecea]",
    label: "Down",
  },
};

export function StatusPill({ status }: { status: SystemStatus }) {
  const style = SYSTEM_STATUS_STYLES[status];

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-bold ${style.wrap} ${style.text}`}
    >
      <span aria-hidden="true" className={`h-2 w-2 rounded-full ${style.dot}`} />
      {style.label}
    </span>
  );
}

type WorkflowStatus = ExceptionStatus | FeedbackStatus | ErrorStatus;

const WORKFLOW_STATUS_STYLES: Record<WorkflowStatus, string> = {
  // Exception statuses
  pending: "border-accent/25 bg-accent-soft text-accent",
  reviewing: "border-border bg-brand-soft text-brand",
  resolved: "border-[#bfe3d3] bg-[#eafaf3] text-[#0f6b4e]",
  dismissed: "border-border bg-brand-soft text-muted",
  // Feedback statuses
  new: "border-accent/25 bg-accent-soft text-accent",
  responded: "border-border bg-brand-soft text-brand",
  escalated: "border-[#f0c2bc] bg-[#fdecea] text-[#b42318]",
  // Error statuses
  investigating: "border-border bg-brand-soft text-brand",
  ignored: "border-border bg-brand-soft text-muted",
};

export function WorkflowStatusBadge({ status }: { status: WorkflowStatus }) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-bold capitalize ${WORKFLOW_STATUS_STYLES[status]}`}
    >
      {status}
    </span>
  );
}

export function Chip({
  children,
  tone = "neutral",
}: {
  children: ReactNode;
  tone?: "neutral" | "accent" | "brand" | "muted";
}) {
  const styles: Record<string, string> = {
    neutral: "border-border bg-white text-foreground",
    accent: "border-accent/25 bg-accent-soft text-accent",
    brand: "border-brand/15 bg-brand-soft text-brand",
    muted: "border-border bg-brand-soft text-muted",
  };

  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-bold ${styles[tone]}`}
    >
      {children}
    </span>
  );
}

export function CheckPill({
  label,
  passed,
}: {
  label: string;
  passed: boolean;
}) {
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold ${
        passed
          ? "border-[#bfe3d3] bg-[#eafaf3] text-[#0f6b4e]"
          : "border-[#f0c2bc] bg-[#fdecea] text-[#b42318]"
      }`}
    >
      <svg
        viewBox="0 0 20 20"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="h-3 w-3"
        aria-hidden="true"
      >
        {passed ? (
          <path d="M4 10.5l4 4 8-9" />
        ) : (
          <path d="M5 5l10 10M15 5L5 15" />
        )}
      </svg>
      {label}
    </span>
  );
}

export function EmptyState({
  title,
  description,
}: {
  title: string;
  description?: string;
}) {
  return (
    <div className="rounded-lg border border-dashed border-border bg-brand-soft/40 px-6 py-12 text-center">
      <p className="text-sm font-bold text-brand">{title}</p>
      {description ? (
        <p className="mt-1 text-sm text-muted">{description}</p>
      ) : null}
    </div>
  );
}

export function InfoBanner({
  children,
  tone = "brand",
}: {
  children: ReactNode;
  tone?: "brand" | "accent" | "warn";
}) {
  const styles =
    tone === "accent"
      ? "border-accent/25 bg-accent-soft text-foreground"
      : tone === "warn"
        ? "border-[#f5d78e] bg-[#fdf6e3] text-[#8a5a00]"
        : "border-brand/15 bg-brand-soft text-brand";

  return (
    <div
      className={`flex gap-3 rounded-lg border px-4 py-3.5 text-sm leading-relaxed ${styles}`}
    >
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="mt-0.5 h-4 w-4 shrink-0"
        aria-hidden="true"
      >
        <circle cx="12" cy="12" r="9" />
        <path d="M12 8h.01M11 12h1v4h1" />
      </svg>
      <div>{children}</div>
    </div>
  );
}

// Horizontal-scroll container for wide tables. Insets its own content with
// px-5/px-6 (rather than bleeding outward with negative margins) so the table
// stays within its card at every width and never clips the outer rounded
// border — callers wrap it in a bare, unpadded card.
export function TableWrap({ children }: { children: ReactNode }) {
  return (
    <div className="overflow-x-auto">
      <div className="min-w-full px-5 sm:px-6">{children}</div>
    </div>
  );
}
