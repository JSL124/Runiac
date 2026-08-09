import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/paywall/domain/models/feature_access_read_model.dart';
import 'package:runiac_app/features/paywall/domain/repositories/feature_access_repository.dart';
import 'package:runiac_app/features/paywall/presentation/current_session_feature_access.dart';
import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';
import 'package:runiac_app/features/profile/presentation/current_session_user_account.dart';
import 'package:runiac_app/features/you/domain/models/workout_briefing_agent.dart';
import 'package:runiac_app/features/you/presentation/data/weekly_workout_demo_snapshots.dart';
import 'package:runiac_app/features/you/presentation/weekly_workout_detail_screen.dart';

// The Coach note card was replaced by the header sparkle button, so these
// cases pin both halves of that swap: the static copy is gone, and the button
// only reaches the agent for a runner the admin-published tier allows.

const _paywallTitleKey = Key('paywall-title');

class _FixedUserAccountRepository implements UserAccountRepository {
  const _FixedUserAccountRepository(this.account);

  final UserAccountReadModel account;

  @override
  Future<UserAccountReadModel> loadUserAccount() async => account;
}

class _FixedFeatureAccessRepository implements FeatureAccessRepository {
  const _FixedFeatureAccessRepository(this.premiumFeatureKeys);

  final List<String> premiumFeatureKeys;

  @override
  Future<FeatureAccessReadModel> loadFeatureAccess() async =>
      FeatureAccessReadModel(premiumFeatureKeys: premiumFeatureKeys);
}

class _RecordingAgent implements WorkoutBriefingAgent {
  final requests = <WorkoutBriefingRequest>[];

  @override
  Future<WorkoutBriefingBundle> explainPlannedWorkout(
    WorkoutBriefingRequest request,
  ) async {
    requests.add(request);
    return const WorkoutBriefingBundle(
      source: WorkoutBriefingSource.generated,
      sections: WorkoutBriefingSections(
        todaySession: 'Today is a short easy run with a walking warm up.',
        whyItHelps: 'It builds the habit without wearing you out.',
        howItFeels: 'You should be able to talk the whole way.',
        beforeYouStart: 'Set off slower than feels natural.',
      ),
    );
  }
}

/// Answers the way the callable does once the day's generations are spent:
/// generic sections plus the server's reset day. The dateless variant of the
/// notice is covered at the formatter level in `agent_quota_notice_test.dart`,
/// so this stub always carries a date.
class _QuotaExhaustedAgent implements WorkoutBriefingAgent {
  const _QuotaExhaustedAgent();

  @override
  Future<WorkoutBriefingBundle> explainPlannedWorkout(
    WorkoutBriefingRequest request,
  ) async {
    return fallbackWorkoutBriefingBundle(
      source: WorkoutBriefingSource.quota,
      retryAfterDate: '2026-08-09',
    );
  }
}

WeeklyWorkoutDetailSnapshot _snapshot({bool canEditSchedule = true}) {
  return WeeklyWorkoutDetailSnapshot(
    title: 'Workout detail',
    dayLabel: 'Thursday · Easy Run',
    planTitle: 'First Continuous Running Start',
    editScheduleCurrentLabel: 'Thursday · 07:00',
    editSchedulePreviewLabel: 'Preview only',
    metrics: const [
      WorkoutMetricDisplay('Distance', '3.0 km'),
      WorkoutMetricDisplay('Time', '20 min'),
    ],
    breakdown: const [
      WorkoutStepDisplay(
        Icons.directions_walk_rounded,
        'Warm up',
        'Walk briskly for five minutes.',
      ),
    ],
    effortGuide: 'Keep the effort easy enough to talk in full sentences.',
    coachNotes: const [
      'Start slower than you think.',
      'Stop early if anything feels off.',
    ],
    canEditSchedule: canEditSchedule,
    briefingContext: const WorkoutBriefingContext(
      planId: 'plan-1',
      weekNumber: 3,
      weekFocus: 'Build repeatable easy minutes.',
    ),
  );
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required UserSubscriptionStatus subscriptionStatus,
  required List<String> premiumFeatureKeys,
  WorkoutBriefingAgent? agent,
  bool showEditScheduleAction = true,
  WeeklyWorkoutDetailSnapshot? snapshot,
}) async {
  final originalSize = tester.view.physicalSize;
  final originalDevicePixelRatio = tester.view.devicePixelRatio;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.physicalSize = originalSize;
    tester.view.devicePixelRatio = originalDevicePixelRatio;
  });

  final accountStore = CurrentSessionUserAccount(
    repository: _FixedUserAccountRepository(
      UserAccountReadModel(subscriptionStatus: subscriptionStatus),
    ),
  );
  addTearDown(accountStore.dispose);
  final featureAccessStore = CurrentSessionFeatureAccess(
    repository: _FixedFeatureAccessRepository(premiumFeatureKeys),
  );
  addTearDown(featureAccessStore.dispose);
  await featureAccessStore.ensureLoaded();

  await tester.pumpWidget(
    MaterialApp(
      home: CurrentSessionUserAccountScope(
        store: accountStore,
        child: FeatureAccessScope(
          store: featureAccessStore,
          child: WeeklyWorkoutDetailScreen(
            onBack: () {},
            snapshot: snapshot ?? _snapshot(),
            showEditScheduleAction: showEditScheduleAction,
            enableForegroundGps: false,
            workoutBriefingAgent: agent,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _tapBriefing(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('workout_briefing_icon_action')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('the static Coach note card is gone from the detail body', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      subscriptionStatus: UserSubscriptionStatus.premium,
      premiumFeatureKeys: const ['workoutBriefing'],
    );

    expect(find.text('Coach note'), findsNothing);
    // Its source copy is now prompt context, not on-screen text.
    expect(find.text('Start slower than you think.'), findsNothing);
    // The surrounding cards are untouched.
    expect(find.text('Effort guide'), findsOneWidget);
  });

  testWidgets('the sparkle action sits beside the edit-schedule action', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      subscriptionStatus: UserSubscriptionStatus.premium,
      premiumFeatureKeys: const ['workoutBriefing'],
    );

    expect(
      find.byKey(const ValueKey('workout_briefing_icon_action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('edit_schedule_icon_action')),
      findsOneWidget,
    );
  });

  testWidgets('the sparkle action still shows on the Home today-plan path', (
    tester,
  ) async {
    // Home pushes this screen with showEditScheduleAction: false, which used
    // to leave the header's trailing slot empty.
    await _pumpDetail(
      tester,
      subscriptionStatus: UserSubscriptionStatus.premium,
      premiumFeatureKeys: const ['workoutBriefing'],
      showEditScheduleAction: false,
    );

    expect(
      find.byKey(const ValueKey('workout_briefing_icon_action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('edit_schedule_icon_action')),
      findsNothing,
    );
  });

  testWidgets('a Basic runner is intercepted and never reaches the agent', (
    tester,
  ) async {
    final agent = _RecordingAgent();
    await _pumpDetail(
      tester,
      subscriptionStatus: UserSubscriptionStatus.basic,
      premiumFeatureKeys: const ['workoutBriefing'],
      agent: agent,
    );

    await _tapBriefing(tester);

    expect(find.byKey(_paywallTitleKey), findsOneWidget);
    expect(agent.requests, isEmpty);
    await _teardownTree(tester);
  });

  testWidgets('a Basic runner proceeds once the admin opens the tier', (
    tester,
  ) async {
    final agent = _RecordingAgent();
    await _pumpDetail(
      tester,
      subscriptionStatus: UserSubscriptionStatus.basic,
      premiumFeatureKeys: const [],
      agent: agent,
    );

    await _tapBriefing(tester);

    expect(find.byKey(_paywallTitleKey), findsNothing);
    expect(agent.requests, hasLength(1));
    await _teardownTree(tester);
  });

  testWidgets('a Premium runner sees the character and all four pages', (
    tester,
  ) async {
    final agent = _RecordingAgent();
    await _pumpDetail(
      tester,
      subscriptionStatus: UserSubscriptionStatus.premium,
      premiumFeatureKeys: const ['workoutBriefing'],
      agent: agent,
    );

    await _tapBriefing(tester);

    expect(
      find.byKey(const ValueKey('workout_briefing_idle_character')),
      findsOneWidget,
    );
    expect(find.text("Today's session"), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);

    for (final expected in [
      'Why it helps',
      'How it should feel',
      'Before you start',
    ]) {
      await tester.tap(find.byTooltip('Next briefing step'));
      await tester.pump();
      expect(find.text(expected), findsOneWidget);
    }
    expect(find.text('4/4'), findsOneWidget);
    await _teardownTree(tester);
  });

  // Regression for manual script 6.2.3 step 3: the sixth briefing of the day
  // returned generic copy that never said the quota was spent or when it
  // resets.
  testWidgets('a quota refusal states the reset day on the first page', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      subscriptionStatus: UserSubscriptionStatus.premium,
      premiumFeatureKeys: const ['workoutBriefing'],
      agent: const _QuotaExhaustedAgent(),
    );

    await _tapBriefing(tester);

    expect(find.text("Today's session"), findsOneWidget);
    expect(
      find.textContaining(
        'Daily limit reached — your workout briefing unlocks again on '
        '9 August 2026.',
      ),
      findsOneWidget,
    );
    // The notice leads page one; the briefing keeps its four pages.
    expect(find.text('1/4'), findsOneWidget);
    await _teardownTree(tester);
  });

  testWidgets('a generated briefing carries no quota notice', (tester) async {
    await _pumpDetail(
      tester,
      subscriptionStatus: UserSubscriptionStatus.premium,
      premiumFeatureKeys: const ['workoutBriefing'],
      agent: _RecordingAgent(),
    );

    await _tapBriefing(tester);

    expect(find.textContaining('Daily limit reached'), findsNothing);
    await _teardownTree(tester);
  });

  testWidgets('the request carries display copy and the plan cache address', (
    tester,
  ) async {
    final agent = _RecordingAgent();
    await _pumpDetail(
      tester,
      subscriptionStatus: UserSubscriptionStatus.premium,
      premiumFeatureKeys: const ['workoutBriefing'],
      agent: agent,
    );

    await _tapBriefing(tester);

    final request = agent.requests.single;
    expect(request.dayLabel, 'Thursday · Easy Run');
    expect(request.weekNumber, 3);
    expect(request.weekFocus, 'Build repeatable easy minutes.');
    expect(request.metrics.map((metric) => metric.label), ['Distance', 'Time']);
    expect(request.steps.single.title, 'Warm up');
    // The retired card's copy now reaches the model as context.
    expect(request.coachNotes, contains('Start slower than you think.'));
    expect(request.cacheIdentity, 'plan-1|w3|Thursday · Easy Run');
    await _teardownTree(tester);
  });

  testWidgets('a snapshot without plan context still briefs, just uncached', (
    tester,
  ) async {
    final agent = _RecordingAgent();
    await _pumpDetail(
      tester,
      subscriptionStatus: UserSubscriptionStatus.premium,
      premiumFeatureKeys: const ['workoutBriefing'],
      agent: agent,
      snapshot: const WeeklyWorkoutDetailSnapshot(
        title: 'Workout detail',
        dayLabel: 'Monday · Recovery Walk',
        planTitle: 'Return to Movement',
        editScheduleCurrentLabel: 'Monday · 07:00',
        editSchedulePreviewLabel: 'Preview only',
        metrics: [WorkoutMetricDisplay('Time', '15 min')],
        breakdown: [
          WorkoutStepDisplay(
            Icons.directions_walk_rounded,
            'Walk',
            'Keep it light.',
          ),
        ],
        effortGuide: 'Very gentle.',
        coachNotes: ['Keep the pace easy.'],
      ),
    );

    await _tapBriefing(tester);

    expect(agent.requests.single.cacheIdentity, isNull);
    expect(find.text("Today's session"), findsOneWidget);
    await _teardownTree(tester);
  });
}
