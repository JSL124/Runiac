// Presentation helpers: turn schema-aligned enum values into human labels and
// format dates. Keeping these here means the UI never hard-codes label strings
// and the Firestore swap only changes data.ts, not display logic.

import type {
  ExceptionSource,
  ExceptionType,
  FeedbackCategory,
  SubscriptionStatus,
  UserRole,
} from "./types";

const ROLE_LABELS: Record<UserRole, string> = {
  runner: "Runner",
  platformAdmin: "Platform Admin",
};

export function roleLabel(role: UserRole): string {
  return ROLE_LABELS[role];
}

export const ROLE_OPTIONS: { value: UserRole; label: string }[] = (
  Object.keys(ROLE_LABELS) as UserRole[]
).map((value) => ({ value, label: ROLE_LABELS[value] }));

const SUBSCRIPTION_LABELS: Record<SubscriptionStatus, string> = {
  basic: "Basic",
  premium: "Premium",
};

export function subscriptionLabel(status: SubscriptionStatus): string {
  return SUBSCRIPTION_LABELS[status];
}

// "Unclassified" is not a legacy bucket: it is the live signal that a report
// arrived with a targetType this console does not recognize, which the
// security rules permit (they do not allowlist the value). Labelled plainly
// so an admin reads it as "unexpected write worth a look", not "old data".
const EXCEPTION_TYPE_LABELS: Record<ExceptionType, string> = {
  "reported-feed-post": "Reported feed post",
  "reported-user": "Reported user",
  "suspicious-xp": "Suspicious XP activity",
  unclassified: "Unclassified",
};

export function exceptionTypeLabel(type: ExceptionType): string {
  return EXCEPTION_TYPE_LABELS[type];
}

export const EXCEPTION_TYPE_OPTIONS: { value: ExceptionType; label: string }[] =
  (Object.keys(EXCEPTION_TYPE_LABELS) as ExceptionType[]).map((value) => ({
    value,
    label: EXCEPTION_TYPE_LABELS[value],
  }));

const EXCEPTION_SOURCE_LABELS: Record<ExceptionSource, string> = {
  "user-report": "User report",
  "anomaly-detection": "Anomaly detection",
};

export function exceptionSourceLabel(source: ExceptionSource): string {
  return EXCEPTION_SOURCE_LABELS[source];
}

const FEEDBACK_CATEGORY_LABELS: Record<FeedbackCategory, string> = {
  bug: "Bug",
  "plan issue": "Plan issue",
  billing: "Billing",
  abuse: "Abuse",
  other: "Other",
};

export function feedbackCategoryLabel(category: FeedbackCategory): string {
  return FEEDBACK_CATEGORY_LABELS[category];
}

const DATE_FMT = new Intl.DateTimeFormat("en-GB", {
  day: "2-digit",
  month: "short",
  year: "numeric",
});

const DATE_TIME_FMT = new Intl.DateTimeFormat("en-GB", {
  day: "2-digit",
  month: "short",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
  hour12: false,
  timeZone: "UTC",
});

export function formatDate(iso: string): string {
  return DATE_FMT.format(new Date(iso));
}

export function formatDateTime(iso: string): string {
  return `${DATE_TIME_FMT.format(new Date(iso))} UTC`;
}

export function formatNumber(value: number): string {
  return value.toLocaleString("en-GB");
}
