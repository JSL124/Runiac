import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/data/cloud_function_activity_feedback_agent.dart';
import 'package:runiac_app/features/run/data/local_activity_feedback_cache_store.dart';
import 'package:runiac_app/features/run/domain/models/activity_feedback_agent.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CloudFunctionActivityFeedbackAgent', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('sends only derived metrics and parses generated sections', () async {
      Map<String, Object?>? capturedPayload;
      final agent = CloudFunctionActivityFeedbackAgent(
        callable: (payload) async {
          capturedPayload = payload;
          return _response(source: 'agent', delivery: 'generated');
        },
        ownerUidProvider: () => 'owner-private-123',
      );
      final summary = _summary();

      final bundle = await agent.explainRun(
        ActivityFeedbackRequest(
          summary: summary,
          analysis: const AdvancedAnalysisSnapshotBuilder().fromRunSummary(
            summary,
          ),
          cacheIdentity: 'activity-private-456',
        ),
      );

      expect(bundle.isGenerated, isTrue);
      expect(bundle.sections.summary, 'You completed a steady run.');
      final encoded = capturedPayload.toString();
      for (final forbidden in <String>[
        'routeName',
        'activityId',
        'polyline',
        'coordinates',
        'Private loop',
        'owner-private-123',
        'activity-private-456',
      ]) {
        expect(encoded, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test(
      'reuses generated feedback across fresh agents for the same run',
      () async {
        var callableCount = 0;
        Future<Object?> callable(Map<String, Object?> _) async {
          callableCount += 1;
          return _response(source: 'agent', delivery: 'generated');
        }

        await CloudFunctionActivityFeedbackAgent(
          callable: callable,
          ownerUidProvider: () => 'owner-1',
        ).explainRun(_request(cacheIdentity: 'activity_123'));
        await CloudFunctionActivityFeedbackAgent(
          callable: callable,
          ownerUidProvider: () => 'owner-1',
        ).explainRun(_request(cacheIdentity: 'activity_123'));

        expect(callableCount, 1);
      },
    );

    test('expires generated feedback after 24 hours', () async {
      var callableCount = 0;
      var now = DateTime.utc(2026, 7, 13, 1);
      Future<Object?> callable(Map<String, Object?> _) async {
        callableCount += 1;
        return _response(source: 'agent', delivery: 'generated');
      }

      await CloudFunctionActivityFeedbackAgent(
        callable: callable,
        ownerUidProvider: () => 'owner-1',
        clock: () => now,
      ).explainRun(_request(cacheIdentity: 'activity_123'));
      now = now.add(const Duration(hours: 24));
      await CloudFunctionActivityFeedbackAgent(
        callable: callable,
        ownerUidProvider: () => 'owner-1',
        clock: () => now,
      ).explainRun(_request(cacheIdentity: 'activity_123'));

      expect(callableCount, 2);
    });

    test('keeps cache entries isolated by owner and run', () async {
      var callableCount = 0;
      Future<Object?> callable(Map<String, Object?> _) async {
        callableCount += 1;
        return _response(source: 'agent', delivery: 'generated');
      }

      Future<void> explain(String ownerUid, String runIdentity) {
        return CloudFunctionActivityFeedbackAgent(
          callable: callable,
          ownerUidProvider: () => ownerUid,
        ).explainRun(_request(cacheIdentity: runIdentity));
      }

      await explain('owner-1', 'activity_123');
      await explain('owner-1', 'activity_123');
      await explain('owner-2', 'activity_123');
      await explain('owner-1', 'activity_456');

      expect(callableCount, 3);
    });

    test('does not cache quota or fallback responses', () async {
      for (final response in <Map<String, Object?>>[
        _response(source: 'quota', delivery: 'quota'),
        _response(source: 'unavailable', delivery: 'fallback'),
      ]) {
        var callableCount = 0;
        Future<Object?> callable(Map<String, Object?> _) async {
          callableCount += 1;
          return response;
        }

        final runIdentity = 'activity_${response['source']}';

        await CloudFunctionActivityFeedbackAgent(
          callable: callable,
          ownerUidProvider: () => 'owner-1',
        ).explainRun(_request(cacheIdentity: runIdentity));
        await CloudFunctionActivityFeedbackAgent(
          callable: callable,
          ownerUidProvider: () => 'owner-1',
        ).explainRun(_request(cacheIdentity: runIdentity));

        expect(callableCount, 2, reason: '${response['source']}');
      }
    });

    test('returns generated feedback when the cache write fails', () async {
      final bundle = await CloudFunctionActivityFeedbackAgent(
        callable: (_) async =>
            _response(source: 'agent', delivery: 'generated'),
        cacheStore: _ThrowingActivityFeedbackCacheStore(throwOnSave: true),
        ownerUidProvider: () => 'owner-1',
      ).explainRun(_request(cacheIdentity: 'activity_123'));

      expect(bundle.source, ActivityFeedbackSource.generated);
      expect(bundle.sections.summary, 'You completed a steady run.');
    });

    test('removes malformed cache and requests fresh feedback', () async {
      final cacheStore = _ThrowingActivityFeedbackCacheStore(throwOnLoad: true);
      var callableCount = 0;

      final bundle = await CloudFunctionActivityFeedbackAgent(
        callable: (_) async {
          callableCount += 1;
          return _response(source: 'agent', delivery: 'generated');
        },
        cacheStore: cacheStore,
        ownerUidProvider: () => 'owner-1',
      ).explainRun(_request(cacheIdentity: 'activity_123'));

      expect(bundle.source, ActivityFeedbackSource.generated);
      expect(callableCount, 1);
      expect(cacheStore.removeCount, 1);
    });

    test(
      'replaces a malformed SharedPreferences entry with generated feedback',
      () async {
        const ownerUid = 'owner-corrupt';
        const runIdentity = 'activity-corrupt';
        final cacheKey = _sharedPreferencesCacheKey(ownerUid, runIdentity);
        SharedPreferences.setMockInitialValues(<String, Object>{
          cacheKey: '{not-valid-json',
        });
        var callableCount = 0;

        final bundle = await CloudFunctionActivityFeedbackAgent(
          callable: (_) async {
            callableCount += 1;
            return _response(source: 'agent', delivery: 'generated');
          },
          ownerUidProvider: () => ownerUid,
        ).explainRun(_request(cacheIdentity: runIdentity));

        final preferences = await SharedPreferences.getInstance();
        final persisted = preferences.getString(cacheKey);
        expect(bundle.source, ActivityFeedbackSource.generated);
        expect(callableCount, 1);
        expect(persisted, isNot('{not-valid-json'));
        expect(LocalActivityFeedbackCacheEntry.tryDecode(persisted), isNotNull);
      },
    );

    test('parses quota and fallback responses', () async {
      final quotaAgent = CloudFunctionActivityFeedbackAgent(
        callable: (_) async => _response(
          source: 'quota',
          delivery: 'quota',
          retryAfterDate: '2026-07-12',
        ),
      );
      final fallbackAgent = CloudFunctionActivityFeedbackAgent(
        callable: (_) async =>
            _response(source: 'unavailable', delivery: 'fallback'),
      );

      final quota = await quotaAgent.explainRun(_request());
      final fallback = await fallbackAgent.explainRun(_request());

      expect(quota.source, ActivityFeedbackSource.quota);
      expect(quota.retryAfterDate, '2026-07-12');
      expect(fallback.source, ActivityFeedbackSource.fallback);
    });

    test(
      'falls back locally on callable errors or malformed responses',
      () async {
        final throwingAgent = CloudFunctionActivityFeedbackAgent(
          callable: (_) async => throw StateError('network unavailable'),
        );
        final malformedAgent = CloudFunctionActivityFeedbackAgent(
          callable: (_) async => <String, Object?>{'source': 'agent'},
        );

        expect(
          (await throwingAgent.explainRun(_request())).source,
          ActivityFeedbackSource.fallback,
        );
        expect(
          (await malformedAgent.explainRun(_request())).source,
          ActivityFeedbackSource.fallback,
        );
      },
    );
  });
}

ActivityFeedbackRequest _request({String? cacheIdentity}) {
  final summary = _summary();
  return ActivityFeedbackRequest(
    summary: summary,
    analysis: const AdvancedAnalysisSnapshotBuilder().fromRunSummary(summary),
    cacheIdentity: cacheIdentity,
  );
}

RunSummarySnapshot _summary() {
  return const RunSummarySnapshot(
    title: 'Morning Run',
    dateLabel: 'Today',
    timeLabel: '7:00 AM',
    distanceKm: '4.00 km',
    avgPace: '6’00” / km',
    duration: '24:00',
    avgHeartRate: '--',
    calories: '200 kcal',
    routeName: 'Private loop',
  );
}

class _ThrowingActivityFeedbackCacheStore
    implements LocalActivityFeedbackCacheStore {
  _ThrowingActivityFeedbackCacheStore({
    this.throwOnLoad = false,
    this.throwOnSave = false,
  });

  final bool throwOnLoad;
  final bool throwOnSave;
  var removeCount = 0;

  @override
  Future<LocalActivityFeedbackCacheEntry?> load({
    required String ownerUid,
    required String runIdentity,
  }) async {
    if (throwOnLoad) throw const FormatException('malformed cache');
    return null;
  }

  @override
  Future<void> remove({
    required String ownerUid,
    required String runIdentity,
  }) async {
    removeCount += 1;
  }

  @override
  Future<void> save({
    required String ownerUid,
    required String runIdentity,
    required LocalActivityFeedbackCacheEntry entry,
  }) async {
    if (throwOnSave) throw StateError('cache write failed');
  }
}

Map<String, Object?> _response({
  required String source,
  required String delivery,
  String? retryAfterDate,
}) {
  return <String, Object?>{
    'source': source,
    'delivery': delivery,
    'retryAfterDate': ?retryAfterDate,
    'sections': <String, Object?>{
      'summary': 'You completed a steady run.',
      'wentWell': 'You kept the effort controlled.',
      'improve': 'Start the next run gently.',
      'nextFocus': 'Keep the next session repeatable.',
    },
  };
}

String _sharedPreferencesCacheKey(String ownerUid, String runIdentity) {
  String encodeKeyPart(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }

  return 'runiac.activityFeedbackCache.v1.'
      '${encodeKeyPart(ownerUid)}.${encodeKeyPart(runIdentity)}';
}
