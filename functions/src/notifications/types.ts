export type NotificationDispatchKind =
  | "today_plan_midnight"
  | "plan_start_minus_120"
  | "plan_start_minus_60"
  | "plan_start_minus_10"
  | "missed_run_plus_60"
  | "missed_run_plus_120"
  | "streak_risk_22"
  | "streak_risk_23";

// Challenge distance-system notification kinds (Todo 7). Registered here so the
// notification kind registry stays a single source of truth, but kept as a
// separate union from `NotificationDispatchKind` because challenge events are
// server-event-driven inbox notifications, not scheduled-push dispatches, and
// must not enter the dispatch planner's kind space. Additive only.
export type ChallengeNotificationKind =
  | "challenge_invitation_received"
  | "challenge_started"
  | "challenge_participant_left"
  | "challenge_owner_cancelled"
  | "challenge_result_ready"
  | "challenge_badge_issued";

// Feed engagement notification kinds (WP1: like/comment inbox pings). Kept as
// a THIRD separate union from both `NotificationDispatchKind` (the scheduled-
// push planner's own kind space) and `ChallengeNotificationKind` (challenge
// state-machine events): feed engagement notifications are per-interaction,
// Firestore-trigger-driven inbox pings raised directly off a single like/
// comment document write, with their own allowlisted payload and suppression
// rules, and must not enter either existing planner's kind space. Additive
// only.
export type FeedEngagementNotificationKind = "feed_post_liked" | "feed_post_commented";

export type PlannedWorkoutReminder = {
  readonly scheduledWorkoutId: string;
  readonly title: string;
  readonly scheduledDate: string;
  readonly startTime: string;
};

export type NotificationPreferences = {
  readonly planRemindersEnabled: boolean;
  readonly streakRiskEnabled: boolean;
};

export type NotificationStreakState = {
  readonly streakCount: number;
  readonly lastStreakRunDate: string | null;
};

export type NotificationPlanningContext = {
  readonly now: string;
  readonly uid: string;
  readonly notificationPreferences: NotificationPreferences;
  readonly plannedWorkouts: readonly PlannedWorkoutReminder[];
  readonly completedWorkoutIds: readonly string[];
  readonly streakState: NotificationStreakState;
};

export type NotificationDispatch = {
  readonly uid: string;
  readonly kind: NotificationDispatchKind;
  readonly deliveryKey: string;
  readonly scheduledWorkoutId: string | null;
  readonly scheduledDate: string;
  readonly title: string;
  readonly body: string;
};

export type NotificationInboxPayload = {
  readonly ownerUid: string;
  readonly deliveryKey: string;
  readonly tokenFingerprint: string;
  readonly kind: NotificationDispatchKind;
  readonly scheduledWorkoutId: string | null;
  readonly scheduledDate: string;
  readonly title: string;
  readonly body: string;
  readonly createdAt: string;
  readonly readAt: null;
};

export type NotificationDeviceRecord = {
  readonly uid: string;
  readonly tokenFingerprint: string;
  readonly fcmToken: string;
};

export type NotificationSendResult = {
  readonly status: "sent" | "invalid-token" | "skipped-duplicate";
  readonly disabledAt?: string;
};

export type NotificationSendAdapter = {
  readonly send: (
    dispatch: NotificationDispatch,
    device: NotificationDeviceRecord,
    inboxPayload: NotificationInboxPayload,
  ) => Promise<NotificationSendResult>;
  readonly disableToken: (device: NotificationDeviceRecord, disabledAt: string) => Promise<void>;
};

export type SendNotificationDispatchesInput = {
  readonly dispatches: readonly NotificationDispatch[];
  readonly devices: readonly NotificationDeviceRecord[];
  readonly adapter: NotificationSendAdapter;
  readonly sentDeliveryKeys: ReadonlySet<string>;
  readonly now: string;
};

export type NotificationDispatchSendResult = {
  readonly deliveryKey: string;
  readonly tokenFingerprint: string;
  readonly status: NotificationSendResult["status"];
};
