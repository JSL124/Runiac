import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  createInboxPayload,
  deliveryKeyFor,
  deviceDeliveryKey,
  planNotificationDispatches,
  sendNotificationDispatches,
  type NotificationDeviceRecord,
  type NotificationSendAdapter,
} from "../src/notifications/dispatchPlanner.js";

const USER_UID = "notification-runner-002";
const WORKOUT_ID = "week-1-thu-easy-run";

describe("notification dispatch planner", () => {
  it("emits plan reminder cases at midnight, before starts, and after missed runs", () => {
    const expectedCases = [
      ["2026-07-09T16:00:00.000Z", "today_plan_midnight"],
      ["2026-07-09T21:00:00.000Z", "plan_start_minus_120"],
      ["2026-07-09T22:00:00.000Z", "plan_start_minus_60"],
      ["2026-07-09T22:50:00.000Z", "plan_start_minus_10"],
      ["2026-07-10T00:00:00.000Z", "missed_run_plus_60"],
      ["2026-07-10T01:00:00.000Z", "missed_run_plus_120"],
    ] as const;

    for (const [now, expectedKind] of expectedCases) {
      const dispatches = planNotificationDispatches(planContext(now));

      assert.equal(dispatches.length, 1);
      assert.equal(dispatches[0]?.kind, expectedKind);
      assert.equal(dispatches[0]?.scheduledWorkoutId, WORKOUT_ID);
      assert.equal(dispatches[0]?.deliveryKey, deliveryKeyFor(dispatches[0]));
    }
  });

  it("reaches a workout whose start minute is off the ten-minute sweep grid", () => {
    // The sweep runs `every 10 minutes`, so it only ever asks the planner
    // about minutes 0, 10, 20, ... An exact-minute offset match made every
    // reminder for a 07:31 workout unreachable: the offsets seen were -119,
    // -109, ... never -120/-60/-10. Drive a full local day of sweeps and
    // assert each reminder is planned exactly once.
    const seen: string[] = [];
    for (const now of tenMinuteSweepsOverLocalDay("2026-07-10")) {
      for (const dispatch of planNotificationDispatches(
        planContext(now, { startTime: "07:31", streakRiskEnabled: false }),
      )) {
        seen.push(dispatch.kind);
      }
    }

    // Set, not list: the window is deliberately wider than the sweep interval
    // for scheduler-delay tolerance, so a reminder may be planned by two
    // consecutive sweeps. Collapsing that to one SEND is the delivery layer's
    // job, asserted separately below.
    assert.deepEqual(
      [...new Set(seen)],
      [
        "today_plan_midnight",
        "plan_start_minus_120",
        "plan_start_minus_60",
        "plan_start_minus_10",
        "missed_run_plus_60",
        "missed_run_plus_120",
      ],
    );
  });

  it("still reaches a reminder when Cloud Scheduler fires late", () => {
    // Cloud Scheduler does not fire on an exact grid. A sweep nominally due at
    // 05:40 that actually runs at 05:42 stepped straight over a ten-minute
    // window, which is the original defect in a narrower form.
    for (const delayMinutes of [0, 2, 5, 11, 14]) {
      const seen: string[] = [];
      for (const now of tenMinuteSweepsOverLocalDay("2026-07-10", delayMinutes)) {
        for (const dispatch of planNotificationDispatches(
          planContext(now, { startTime: "07:31", streakRiskEnabled: false }),
        )) {
          seen.push(dispatch.kind);
        }
      }

      assert.ok(
        seen.includes("plan_start_minus_120"),
        `a ${delayMinutes}-minute scheduler delay dropped plan_start_minus_120`,
      );
      assert.ok(
        seen.includes("plan_start_minus_10"),
        `a ${delayMinutes}-minute scheduler delay dropped plan_start_minus_10`,
      );
      assert.ok(
        seen.includes("today_plan_midnight"),
        `a ${delayMinutes}-minute scheduler delay dropped today_plan_midnight`,
      );
    }
  });

  it("does not let the midnight window mask an overlapping offset window", () => {
    // A 02:05 start puts the -120 window at 00:05-00:20, overlapping the
    // midnight window. Chaining the kinds with `??` returned midnight alone at
    // the 00:10 sweep, and by 00:20 the -120 window had closed — so that
    // reminder was never sent at all.
    const seen: string[] = [];
    for (const now of tenMinuteSweepsOverLocalDay("2026-07-10")) {
      for (const dispatch of planNotificationDispatches(
        planContext(now, { startTime: "02:05", streakRiskEnabled: false }),
      )) {
        seen.push(dispatch.kind);
      }
    }

    assert.ok(seen.includes("today_plan_midnight"));
    assert.ok(
      seen.includes("plan_start_minus_120"),
      "the midnight window swallowed the -120 reminder",
    );
    assert.ok(seen.includes("plan_start_minus_60"));
    assert.ok(seen.includes("plan_start_minus_10"));
  });

  it("never matches two offset windows on the same sweep", () => {
    // The window is wider than the sweep interval, so two consecutive sweeps
    // can both find one reminder due — that is what the delivery dedup covers.
    // What must never happen is one sweep matching two different OFFSETS, which
    // would mean the windows had grown into each other. (The midnight kind may
    // legitimately co-occur with an offset kind; it is a different reminder,
    // not a widened window, so it is excluded here.)
    for (const now of tenMinuteSweepsOverLocalDay("2026-07-10")) {
      const offsetKinds = planNotificationDispatches(
        planContext(now, { startTime: "07:31", streakRiskEnabled: false }),
      )
        .map((dispatch) => dispatch.kind)
        .filter((kind) => kind !== "today_plan_midnight");
      assert.equal(new Set(offsetKinds).size, offsetKinds.length);
      assert.ok(
        offsetKinds.length <= 1,
        `${now} matched ${offsetKinds.length} offset windows`,
      );
    }
  });

  it("sends each reminder once even when consecutive sweeps both plan it", async () => {
    // The delay-tolerant window means a reminder is planned more than once, so
    // this is the assertion that actually protects the runner from a duplicate
    // push. `sentDeliveryKeys` models the durable `notificationDeliveries`
    // lookup the real sweep performs.
    const devices: readonly NotificationDeviceRecord[] = [
      { uid: USER_UID, tokenFingerprint: "fingerprint-001", fcmToken: "fcm-token-001" },
    ];
    const sentDeliveryKeys = new Set<string>();
    const sends: string[] = [];
    const adapter: NotificationSendAdapter = {
      send: async (dispatch, device) => {
        sends.push(dispatch.kind);
        sentDeliveryKeys.add(deviceDeliveryKey(dispatch.deliveryKey, device.tokenFingerprint));
        return { status: "sent" };
      },
      disableToken: async () => {},
    };

    let planned = 0;
    for (const now of tenMinuteSweepsOverLocalDay("2026-07-10")) {
      const dispatches = planNotificationDispatches(
        planContext(now, { startTime: "07:00", streakRiskEnabled: false }),
      );
      planned += dispatches.length;
      await sendNotificationDispatches({
        dispatches,
        devices,
        adapter,
        sentDeliveryKeys,
        now,
      });
    }

    // Planned more than once, sent exactly once per reminder kind.
    assert.ok(planned > 6, `expected repeated planning, got ${planned}`);
    assert.equal(sends.length, 6);
    assert.equal(new Set(sends).size, 6);
  });

  it("emits streak-risk reminders only at 22:00 or 23:00 Singapore time when enabled and incomplete", () => {
    const enabledAt22 = planNotificationDispatches(streakContext("2026-07-10T14:00:00.000Z"));
    const enabledAt23 = planNotificationDispatches(streakContext("2026-07-10T15:00:00.000Z"));
    const enabledAt21 = planNotificationDispatches(streakContext("2026-07-10T13:00:00.000Z"));
    const disabled = planNotificationDispatches(
      streakContext("2026-07-10T14:00:00.000Z", {
        streakRiskEnabled: false,
        completedToday: false,
      }),
    );
    const completed = planNotificationDispatches(
      streakContext("2026-07-10T14:00:00.000Z", {
        streakRiskEnabled: true,
        completedToday: true,
      }),
    );

    assert.equal(enabledAt22.length, 1);
    assert.equal(enabledAt22[0]?.kind, "streak_risk_22");
    assert.equal(enabledAt23.length, 1);
    assert.equal(enabledAt23[0]?.kind, "streak_risk_23");
    assert.equal(enabledAt21.length, 0);
    assert.equal(disabled.length, 0);
    assert.equal(completed.length, 0);
  });

  it("generates stable delivery keys and inbox payloads without raw tokens", () => {
    const dispatch = planNotificationDispatches(planContext("2026-07-09T21:00:00.000Z"))[0];
    assert.ok(dispatch !== undefined);

    const firstKey = deliveryKeyFor(dispatch);
    const secondKey = deliveryKeyFor({ ...dispatch });
    const payload = createInboxPayload(dispatch, "fingerprint-001", "2026-07-09T21:00:00.000Z");

    assert.equal(firstKey, secondKey);
    assert.equal(payload.deliveryKey, firstKey);
    assert.equal(payload.ownerUid, USER_UID);
    assert.equal(payload.tokenFingerprint, "fingerprint-001");
    assert.equal(JSON.stringify(payload).includes("fcm-token"), false);
  });

  it("disables invalid or unregistered notification devices through the send adapter cleanup seam", async () => {
    const dispatch = planNotificationDispatches(planContext("2026-07-09T21:00:00.000Z"))[0];
    assert.ok(dispatch !== undefined);
    const disabledFingerprints: string[] = [];
    const adapter: NotificationSendAdapter = {
      send: async () => ({
        status: "invalid-token",
        disabledAt: "2026-07-09T21:00:01.000Z",
      }),
      disableToken: async (device: NotificationDeviceRecord, disabledAt: string) => {
        disabledFingerprints.push(`${device.tokenFingerprint}:${disabledAt}`);
      },
    };
    const devices: readonly NotificationDeviceRecord[] = [
      {
        uid: USER_UID,
        tokenFingerprint: "fingerprint-invalid",
        fcmToken: "fcm-token-invalid",
      },
    ];

    const results = await sendNotificationDispatches({
      dispatches: [dispatch],
      devices,
      adapter,
      sentDeliveryKeys: new Set<string>(),
      now: "2026-07-09T21:00:01.000Z",
    });

    assert.deepEqual(results, [
      {
        deliveryKey: dispatch.deliveryKey,
        tokenFingerprint: "fingerprint-invalid",
        status: "invalid-token",
      },
    ]);
    assert.deepEqual(disabledFingerprints, ["fingerprint-invalid:2026-07-09T21:00:01.000Z"]);
  });

});

/**
 * Every instant the `every 10 minutes` sweep hands the planner across one
 * Singapore local day, as UTC ISO strings.
 */
function tenMinuteSweepsOverLocalDay(
  localDate: string,
  delayMinutes = 0,
): readonly string[] {
  const startMs = Date.parse(`${localDate}T00:00:00.000+08:00`);
  const sweeps: string[] = [];
  for (let minute = 0; minute < 24 * 60; minute += 10) {
    sweeps.push(new Date(startMs + (minute + delayMinutes) * 60_000).toISOString());
  }
  return sweeps;
}

function planContext(
  now: string,
  options: {
    readonly startTime?: string;
    readonly streakRiskEnabled?: boolean;
  } = {},
) {
  return {
    now,
    uid: USER_UID,
    notificationPreferences: {
      planRemindersEnabled: true,
      streakRiskEnabled: options.streakRiskEnabled ?? true,
    },
    plannedWorkouts: [
      {
        scheduledWorkoutId: WORKOUT_ID,
        title: "Easy Run",
        scheduledDate: "2026-07-10",
        startTime: options.startTime ?? "07:00",
      },
    ],
    completedWorkoutIds: [],
    streakState: {
      streakCount: 2,
      lastStreakRunDate: "2026-07-09",
    },
  };
}

function streakContext(
  now: string,
  options: {
    readonly streakRiskEnabled: boolean;
    readonly completedToday: boolean;
  } = {
    streakRiskEnabled: true,
    completedToday: false,
  },
) {
  return {
    now,
    uid: USER_UID,
    notificationPreferences: {
      planRemindersEnabled: false,
      streakRiskEnabled: options.streakRiskEnabled,
    },
    plannedWorkouts: [],
    completedWorkoutIds: [],
    streakState: {
      streakCount: 4,
      lastStreakRunDate: options.completedToday ? "2026-07-10" : "2026-07-09",
    },
  };
}
