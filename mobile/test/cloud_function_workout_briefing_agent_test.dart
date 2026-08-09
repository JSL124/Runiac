import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/you/data/cloud_function_workout_briefing_agent.dart';
import 'package:runiac_app/features/you/data/local_workout_briefing_cache_store.dart';
import 'package:runiac_app/features/you/domain/models/workout_briefing_agent.dart';

WorkoutBriefingRequest _request({
  String? cacheIdentity = 'plan-1|w3|Thursday',
}) {
  return WorkoutBriefingRequest(
    dayLabel: 'Thursday · Easy Run',
    planTitle: 'First Continuous Running Start',
    effortGuide: 'Keep the effort easy enough to talk in full sentences.',
    weekNumber: 3,
    metrics: const [WorkoutBriefingMetric(label: 'Distance', value: '3.0 km')],
    steps: const [
      WorkoutBriefingStep(title: 'Warm up', detail: 'Walk five minutes.'),
    ],
    coachNotes: const ['Start slower than you think.'],
    cacheIdentity: cacheIdentity,
  );
}

Map<String, Object?> _generatedResponse() {
  return <String, Object?>{
    'source': 'agent',
    'delivery': 'generated',
    'sections': <String, Object?>{
      'todaySession': 'Today is a short easy run.',
      'whyItHelps': 'It builds the habit without wearing you out.',
      'howItFeels': 'You should be able to talk the whole way.',
      'beforeYouStart': 'Set off slower than feels natural.',
    },
  };
}

void main() {
  group('CloudFunctionWorkoutBriefingAgent', () {
    test('maps a generated response onto the domain bundle', () async {
      final agent = CloudFunctionWorkoutBriefingAgent(
        callable: (_) async => _generatedResponse(),
      );

      final bundle = await agent.explainPlannedWorkout(_request());

      expect(bundle.source, WorkoutBriefingSource.generated);
      expect(bundle.isGenerated, isTrue);
      expect(bundle.sections.todaySession, 'Today is a short easy run.');
      expect(bundle.sections.steps.map((step) => step.title).toList(), [
        "Today's session",
        'Why it helps',
        'How it should feel',
        'Before you start',
      ]);
    });

    test('maps a quota response and carries the retry date', () async {
      final agent = CloudFunctionWorkoutBriefingAgent(
        callable: (_) async => <String, Object?>{
          ..._generatedResponse(),
          'source': 'quota',
          'delivery': 'quota',
          'retryAfterDate': '2026-07-30',
        },
      );

      final bundle = await agent.explainPlannedWorkout(_request());

      expect(bundle.source, WorkoutBriefingSource.quota);
      expect(bundle.retryAfterDate, '2026-07-30');
      expect(bundle.isGenerated, isFalse);
    });

    test(
      'maps a premium denial to the premium bundle, never an exception',
      () async {
        final agent = CloudFunctionWorkoutBriefingAgent(
          callable: (_) async => throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Premium required.',
            details: const {'reason': 'premium-required'},
          ),
        );

        final bundle = await agent.explainPlannedWorkout(_request());

        expect(bundle.source, WorkoutBriefingSource.fallback);
        expect(bundle.sections.todaySession, contains('Premium'));
      },
    );

    test('never throws, whatever the callable does', () async {
      final failures = <String, Future<Object?> Function(Map<String, Object?>)>{
        'arbitrary throw': (_) async => throw StateError('boom'),
        'other functions error': (_) async => throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'Backend down.',
        ),
        'null response': (_) async => null,
        'wrong shape': (_) async => <String, Object?>{'source': 'agent'},
        'missing section': (_) async => <String, Object?>{
          'source': 'agent',
          'delivery': 'generated',
          'sections': <String, Object?>{'todaySession': 'only one'},
        },
      };

      for (final entry in failures.entries) {
        final bundle = await CloudFunctionWorkoutBriefingAgent(
          callable: entry.value,
        ).explainPlannedWorkout(_request());
        expect(
          bundle.source,
          WorkoutBriefingSource.fallback,
          reason: '${entry.key} must degrade to fallback copy',
        );
      }
    });

    test('sends the builder payload and no plan identifier', () async {
      Map<String, Object?>? sent;
      final agent = CloudFunctionWorkoutBriefingAgent(
        callable: (payload) async {
          sent = payload;
          return _generatedResponse();
        },
      );

      await agent.explainPlannedWorkout(_request());

      expect(sent!['schemaVersion'], 1);
      expect(sent.toString(), isNot(contains('plan-1')));
    });
  });

  group('CachingWorkoutBriefingAgent', () {
    test(
      'serves a cached briefing without calling the delegate again',
      () async {
        final delegate = _CountingAgent(_generatedBundle());
        final store = _InMemoryCacheStore();
        var now = DateTime.utc(2026, 7, 29);
        final agent = CachingWorkoutBriefingAgent(
          delegate: delegate,
          cacheStore: store,
          ownerUidProvider: () => 'runner-1',
          clock: () => now,
        );

        await agent.explainPlannedWorkout(_request());
        now = now.add(const Duration(days: 6, hours: 23));
        final second = await agent.explainPlannedWorkout(_request());

        expect(delegate.calls, 1);
        expect(second.source, WorkoutBriefingSource.generated);
      },
    );

    test('re-fetches once the seven-day TTL lapses', () async {
      final delegate = _CountingAgent(_generatedBundle());
      final store = _InMemoryCacheStore();
      var now = DateTime.utc(2026, 7, 29);
      final agent = CachingWorkoutBriefingAgent(
        delegate: delegate,
        cacheStore: store,
        ownerUidProvider: () => 'runner-1',
        clock: () => now,
      );

      await agent.explainPlannedWorkout(_request());
      final firstCachedAt = store.entries.values.single.cachedAt;
      now = now.add(const Duration(days: 7, seconds: 1));
      await agent.explainPlannedWorkout(_request());

      expect(delegate.calls, 2);
      // The stale entry is evicted and replaced by the fresh result, so the
      // store holds exactly one entry stamped at the later clock reading.
      expect(store.entries.values.single.cachedAt, isNot(firstCachedAt));
      expect(store.entries.values.single.cachedAt, now);
    });

    test(
      'evicts an entry stamped in the future rather than trusting it',
      () async {
        final delegate = _CountingAgent(_generatedBundle());
        final store = _InMemoryCacheStore()
          ..entries['runner-1|plan-1|w3|Thursday|1991905a419eca7b'] =
              LocalWorkoutBriefingCacheEntry(
                cachedAt: DateTime.utc(2027),
                sections: _generatedBundle().sections,
              );
        final agent = CachingWorkoutBriefingAgent(
          delegate: delegate,
          cacheStore: store,
          ownerUidProvider: () => 'runner-1',
          clock: () => DateTime.utc(2026, 7, 29),
        );

        await agent.explainPlannedWorkout(_request());

        expect(delegate.calls, 1);
      },
    );

    test('re-fetches when the workout content changes', () async {
      final delegate = _CountingAgent(_generatedBundle());
      final agent = CachingWorkoutBriefingAgent(
        delegate: delegate,
        cacheStore: _InMemoryCacheStore(),
        ownerUidProvider: () => 'runner-1',
        clock: () => DateTime.utc(2026, 7, 29),
      );

      await agent.explainPlannedWorkout(_request());
      await agent.explainPlannedWorkout(
        WorkoutBriefingRequest(
          dayLabel: 'Thursday · Easy Run',
          planTitle: 'First Continuous Running Start',
          effortGuide: 'Hold one calm rhythm without pushing the pace.',
          weekNumber: 3,
          cacheIdentity: 'plan-1|w3|Thursday',
        ),
      );

      expect(delegate.calls, 2);
    });

    test('caches only generated bundles', () async {
      final store = _InMemoryCacheStore();
      final agent = CachingWorkoutBriefingAgent(
        delegate: _CountingAgent(fallbackWorkoutBriefingBundle()),
        cacheStore: store,
        ownerUidProvider: () => 'runner-1',
        clock: () => DateTime.utc(2026, 7, 29),
      );

      await agent.explainPlannedWorkout(_request());

      expect(store.entries, isEmpty);
    });

    test(
      'skips caching without a plan address or a signed-in runner',
      () async {
        final withoutAddress = _CountingAgent(_generatedBundle());
        final withoutUid = _CountingAgent(_generatedBundle());

        await CachingWorkoutBriefingAgent(
          delegate: withoutAddress,
          cacheStore: _InMemoryCacheStore(),
          ownerUidProvider: () => 'runner-1',
          clock: () => DateTime.utc(2026, 7, 29),
        ).explainPlannedWorkout(_request(cacheIdentity: null));
        await CachingWorkoutBriefingAgent(
          delegate: withoutAddress,
          cacheStore: _InMemoryCacheStore(),
          ownerUidProvider: () => 'runner-1',
          clock: () => DateTime.utc(2026, 7, 29),
        ).explainPlannedWorkout(_request(cacheIdentity: null));

        final agentWithoutUid = CachingWorkoutBriefingAgent(
          delegate: withoutUid,
          cacheStore: _InMemoryCacheStore(),
          ownerUidProvider: () => null,
          clock: () => DateTime.utc(2026, 7, 29),
        );
        await agentWithoutUid.explainPlannedWorkout(_request());
        await agentWithoutUid.explainPlannedWorkout(_request());

        expect(withoutAddress.calls, 2);
        expect(withoutUid.calls, 2);
      },
    );

    test('a cache read failure costs a call, never the briefing', () async {
      final delegate = _CountingAgent(_generatedBundle());
      final agent = CachingWorkoutBriefingAgent(
        delegate: delegate,
        cacheStore: _ThrowingCacheStore(),
        ownerUidProvider: () => 'runner-1',
        clock: () => DateTime.utc(2026, 7, 29),
      );

      final bundle = await agent.explainPlannedWorkout(_request());

      expect(bundle.source, WorkoutBriefingSource.generated);
      expect(delegate.calls, 1);
    });
  });
}

WorkoutBriefingBundle _generatedBundle() {
  return const WorkoutBriefingBundle(
    source: WorkoutBriefingSource.generated,
    sections: WorkoutBriefingSections(
      todaySession: 'Today is a short easy run.',
      whyItHelps: 'It builds the habit without wearing you out.',
      howItFeels: 'You should be able to talk the whole way.',
      beforeYouStart: 'Set off slower than feels natural.',
    ),
  );
}

class _CountingAgent implements WorkoutBriefingAgent {
  _CountingAgent(this.bundle);

  final WorkoutBriefingBundle bundle;
  var calls = 0;

  @override
  Future<WorkoutBriefingBundle> explainPlannedWorkout(
    WorkoutBriefingRequest request,
  ) async {
    calls += 1;
    return bundle;
  }
}

class _InMemoryCacheStore implements LocalWorkoutBriefingCacheStore {
  final entries = <String, LocalWorkoutBriefingCacheEntry>{};

  @override
  Future<LocalWorkoutBriefingCacheEntry?> load({
    required String ownerUid,
    required String workoutIdentity,
  }) async => entries['$ownerUid|$workoutIdentity'];

  @override
  Future<void> save({
    required String ownerUid,
    required String workoutIdentity,
    required LocalWorkoutBriefingCacheEntry entry,
  }) async {
    entries['$ownerUid|$workoutIdentity'] = entry;
  }

  @override
  Future<void> remove({
    required String ownerUid,
    required String workoutIdentity,
  }) async {
    entries.remove('$ownerUid|$workoutIdentity');
  }
}

class _ThrowingCacheStore implements LocalWorkoutBriefingCacheStore {
  @override
  Future<LocalWorkoutBriefingCacheEntry?> load({
    required String ownerUid,
    required String workoutIdentity,
  }) async => throw StateError('cache unavailable');

  @override
  Future<void> save({
    required String ownerUid,
    required String workoutIdentity,
    required LocalWorkoutBriefingCacheEntry entry,
  }) async => throw StateError('cache unavailable');

  @override
  Future<void> remove({
    required String ownerUid,
    required String workoutIdentity,
  }) async => throw StateError('cache unavailable');
}
