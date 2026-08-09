import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/plan/data/firestore_adaptive_plan_estimate_repository.dart';
import 'package:runiac_app/features/plan/domain/models/adaptive_plan_estimate_read_model.dart';

void main() {
  group('AdaptivePlanEstimateReadModel.fromBackend', () {
    test('hydrates usable backend adaptive estimate for planned run display', () {
      // Given: completeRun has written a usable backend-owned pace estimate.
      final estimate = AdaptivePlanEstimateReadModel.fromBackend(const {
        'averageRecentPaceSecondsPerKm': 469,
        'completedRunCount': 1,
        'positivePaceRunCount': 1,
        'readinessBand': 'learning',
        'updatedAt': '2026-07-07T09:00:00.000Z',
        'latestAcceptedActivityId': 'activity-1',
        'latestClientRunSessionId': 'session-1',
      });

      // When: the current generated workout is a 25 minute duration run.
      final targetMeters = estimate.targetDistanceMetersForDurationMinutes(25);

      // Then: the app can display the backend pace as conservative distance copy.
      expect(estimate.isUsableForPlannedRun, isTrue);
      expect(estimate.estimateConfidence, AdaptivePlanEstimateConfidence.low);
      expect(targetMeters, 3198);
      expect(estimate.distanceLabelForDurationMinutes(25), '~3.2 km');
    });

    test('keeps conservative or zero pace adaptive estimates hidden', () {
      // Given: backend state is explicitly conservative or has no positive pace.
      final conservative = AdaptivePlanEstimateReadModel.fromBackend(const {
        'averageRecentPaceSecondsPerKm': 469,
        'completedRunCount': 1,
        'positivePaceRunCount': 1,
        'readinessBand': 'conservative',
      });
      final zeroPace = AdaptivePlanEstimateReadModel.fromBackend(const {
        'averageRecentPaceSecondsPerKm': 0,
        'completedRunCount': 1,
        'positivePaceRunCount': 0,
        'readinessBand': 'learning',
      });
      final noPositivePaceSample =
          AdaptivePlanEstimateReadModel.fromBackend(const {
            'averageRecentPaceSecondsPerKm': 469,
            'completedRunCount': 1,
            'positivePaceRunCount': 0,
            'readinessBand': 'learning',
          });

      // Then: neither state creates a misleading planned-run target.
      expect(conservative.isUsableForPlannedRun, isFalse);
      expect(
        conservative.estimateConfidence,
        AdaptivePlanEstimateConfidence.none,
      );
      expect(conservative.targetDistanceMetersForDurationMinutes(25), isNull);
      expect(zeroPace.isUsableForPlannedRun, isFalse);
      expect(zeroPace.distanceLabelForDurationMinutes(25), isNull);
      expect(noPositivePaceSample.isUsableForPlannedRun, isFalse);
      expect(noPositivePaceSample.distanceLabelForDurationMinutes(25), isNull);
    });
  });

  group('AdaptivePlanEstimateRepository', () {
    test('adaptive estimate repository loads owner read model', () async {
      // Given: the owner document store returns backend-owned adaptive estimate data.
      final repository = FirestoreAdaptivePlanEstimateRepository(
        documentStore: _LoadedAdaptiveEstimateDocumentStore(const {
          'averageRecentPaceSecondsPerKm': 469,
          'completedRunCount': 2,
          'positivePaceRunCount': 2,
          'readinessBand': 'learning',
        }),
      );

      // When: the owner estimate is loaded.
      final estimate = await repository.loadAdaptivePlanEstimate(
        uid: 'runner-1',
      );

      // Then: the parsed model is available as display-only state.
      expect(estimate.isUsableForPlannedRun, isTrue);
      expect(
        estimate.estimateConfidence,
        AdaptivePlanEstimateConfidence.medium,
      );
    });

    test(
      'adaptive estimate repository falls back to empty on read exceptions',
      () async {
        // Given: Firestore owner-read fails because of permission/offline state.
        final repository = FirestoreAdaptivePlanEstimateRepository(
          documentStore: _ThrowingAdaptiveEstimateDocumentStore(),
        );

        // When: the owner estimate is loaded.
        final estimate = await repository.loadAdaptivePlanEstimate(
          uid: 'runner-1',
        );

        // Then: the app receives safe empty state instead of a thrown error.
        expect(estimate.isUsableForPlannedRun, isFalse);
        expect(
          estimate.estimateConfidence,
          AdaptivePlanEstimateConfidence.none,
        );
      },
    );
  });
}

class _LoadedAdaptiveEstimateDocumentStore
    implements AdaptivePlanEstimateDocumentStore {
  const _LoadedAdaptiveEstimateDocumentStore(this.data);

  final Map<String, Object?>? data;

  @override
  Future<Map<String, Object?>?> loadAdaptivePlanEstimate({
    required String uid,
  }) async {
    return data;
  }
}

class _ThrowingAdaptiveEstimateDocumentStore
    implements AdaptivePlanEstimateDocumentStore {
  @override
  Future<Map<String, Object?>?> loadAdaptivePlanEstimate({
    required String uid,
  }) {
    throw StateError('offline');
  }
}
