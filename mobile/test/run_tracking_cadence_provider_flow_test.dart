import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/data/static_run_repository.dart';
import 'package:runiac_app/features/run/domain/models/advanced_analysis_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/repositories/run_cadence_provider.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_provider.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';
import 'package:runiac_app/features/run/presentation/controllers/run_tracking_controller.dart';

void main() {
  group('Run tracking cadence provider flow', () {
    test(
      'fake phone cadence reaches local summary and Advanced Analysis',
      () async {
        final startedAt = DateTime.utc(2026, 6, 24, 7);
        final cadenceProvider = FakeRunCadenceProvider(
          cadencePattern: const <double>[168, 170, 172],
        );
        final controller = RunTrackingController(
          cadenceProvider: cadenceProvider,
          locationProvider: _replayLocationProvider(startedAt),
        );

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'cadence-flow',
        );
        await Future<void>.delayed(Duration.zero);
        cadenceProvider.emitNext(
          recordedAt: startedAt.add(const Duration(seconds: 10)),
        );
        cadenceProvider.emitNext(
          recordedAt: startedAt.add(const Duration(seconds: 20)),
        );
        cadenceProvider.emitNext(
          recordedAt: startedAt.add(const Duration(seconds: 30)),
        );
        await Future<void>.delayed(Duration.zero);
        controller.advanceBy(const Duration(seconds: 180));

        final payload = controller.completionPayload(
          completedAt: startedAt.add(const Duration(seconds: 180)),
        );
        final completedRun = await const StaticRunRepository().completeRun(
          payload,
        );
        final cadence = const AdvancedAnalysisSnapshotBuilder()
            .fromRunSummary(completedRun.summary)
            .formCadence;

        expect(payload.toRawClientMap().keys, isNot(contains('cadence')));
        expect(
          payload.cadenceAnalysisSeries?.validAcceptedSamples,
          hasLength(3),
        );
        expect(
          completedRun.summary.cadenceAnalysisSeries?.source.name,
          'phoneSensorEstimated',
        );
        expect(cadence.averageCadence.valueLabel, '170 spm');
        expect(
          cadence.averageCadence.source,
          AdvancedAnalysisMetricSource.phoneSensorEstimated,
        );
        expect(cadence.cadenceGraph.isAvailable, isTrue);

        await cadenceProvider.dispose();
      },
    );

    test(
      'paused run ignores cadence emitted outside active lifecycle',
      () async {
        final startedAt = DateTime.utc(2026, 6, 24, 7);
        final cadenceProvider = FakeRunCadenceProvider(
          cadencePattern: const <double>[168, 170, 172],
        );
        final controller = RunTrackingController(
          cadenceProvider: cadenceProvider,
          locationProvider: _replayLocationProvider(startedAt),
        );

        controller.start(startedAt: startedAt);
        await Future<void>.delayed(Duration.zero);
        cadenceProvider.emitNext(
          recordedAt: startedAt.add(const Duration(seconds: 10)),
        );
        await Future<void>.delayed(Duration.zero);
        controller.advanceBy(const Duration(seconds: 20));
        controller.pause(pausedAt: startedAt.add(const Duration(seconds: 20)));
        cadenceProvider.emitNext(
          recordedAt: startedAt.add(const Duration(seconds: 25)),
        );
        await Future<void>.delayed(Duration.zero);
        controller.resume(
          resumedAt: startedAt.add(const Duration(seconds: 40)),
        );
        await Future<void>.delayed(Duration.zero);
        cadenceProvider.emitNext(
          recordedAt: startedAt.add(const Duration(seconds: 50)),
        );
        await Future<void>.delayed(Duration.zero);
        controller.advanceBy(const Duration(seconds: 10));

        final payload = controller.completionPayload(
          completedAt: startedAt.add(const Duration(seconds: 120)),
        );

        expect(
          payload.cadenceAnalysisSeries?.validAcceptedSamples,
          hasLength(2),
        );

        await cadenceProvider.dispose();
      },
    );

    test('cadence elapsed time never exceeds completion duration', () async {
      final startedAt = DateTime.utc(2026, 6, 24, 7);
      final cadenceProvider = FakeRunCadenceProvider(
        cadencePattern: const <double>[168, 170],
      );
      final controller = RunTrackingController(
        cadenceProvider: cadenceProvider,
        locationProvider: _replayLocationProvider(startedAt),
      );

      controller.start(startedAt: startedAt);
      await Future<void>.delayed(Duration.zero);
      cadenceProvider.emitNext(recordedAt: startedAt);
      await Future<void>.delayed(Duration.zero);
      controller.pause(pausedAt: startedAt);
      controller.resume(resumedAt: startedAt.add(const Duration(seconds: 1)));
      await Future<void>.delayed(Duration.zero);
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(seconds: 1)),
      );
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(seconds: 5)),
      );
      await Future<void>.delayed(Duration.zero);

      final payload = controller.completionPayload(
        completedAt: startedAt.add(const Duration(seconds: 1)),
      );
      final samples = payload.cadenceAnalysisSeries?.validAcceptedSamples;

      expect(payload.durationSeconds, 0);
      expect(samples, hasLength(1));
      expect(samples?.single.elapsedSeconds, 0);
      expect(
        samples?.every(
          (sample) => sample.elapsedSeconds <= payload.durationSeconds,
        ),
        isTrue,
      );

      await cadenceProvider.dispose();
    });

    test('same-second cadence samples remain analysis eligible', () async {
      final startedAt = DateTime.utc(2026, 6, 24, 7);
      final cadenceProvider = FakeRunCadenceProvider(
        cadencePattern: const <double>[168, 170, 172, 174],
      );
      final controller = RunTrackingController(
        cadenceProvider: cadenceProvider,
        locationProvider: _replayLocationProvider(startedAt),
      );

      controller.start(startedAt: startedAt);
      await Future<void>.delayed(Duration.zero);
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(milliseconds: 1100)),
      );
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(milliseconds: 1900)),
      );
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(milliseconds: 2100)),
      );
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(milliseconds: 3100)),
      );
      await Future<void>.delayed(Duration.zero);
      controller.advanceBy(const Duration(seconds: 4));

      final series = controller
          .completionPayload(
            completedAt: startedAt.add(const Duration(seconds: 4)),
          )
          .cadenceAnalysisSeries;

      expect(series?.validAcceptedSamples, hasLength(3));
      expect(series?.hasMonotonicValidSamples, isTrue);
      expect(
        series?.validAcceptedSamples.map((sample) => sample.elapsedSeconds),
        <int>[1, 2, 3],
      );
      expect(
        series?.validAcceptedSamples.first.cadenceSpm,
        170,
        reason: 'the latest reading should represent each elapsed second',
      );

      await cadenceProvider.dispose();
    });

    test('older same-second cadence cannot replace a newer reading', () async {
      final startedAt = DateTime.utc(2026, 6, 24, 7);
      final cadenceProvider = FakeRunCadenceProvider(
        cadencePattern: const <double>[168, 170, 172],
      );
      final controller = RunTrackingController(
        cadenceProvider: cadenceProvider,
        locationProvider: _replayLocationProvider(startedAt),
      );

      controller.start(startedAt: startedAt);
      await Future<void>.delayed(Duration.zero);
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(milliseconds: 1900)),
      );
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(milliseconds: 1100)),
      );
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(milliseconds: 2100)),
      );
      await Future<void>.delayed(Duration.zero);
      controller.advanceBy(const Duration(seconds: 3));

      final samples = controller
          .completionPayload(
            completedAt: startedAt.add(const Duration(seconds: 3)),
          )
          .cadenceAnalysisSeries
          ?.validAcceptedSamples;

      expect(samples, hasLength(2));
      expect(samples?.first.cadenceSpm, 168);
      expect(samples?.last.cadenceSpm, 172);

      await cadenceProvider.dispose();
    });

    test('post-completion cadence is excluded from the payload', () async {
      final startedAt = DateTime.utc(2026, 6, 24, 7);
      final cadenceProvider = FakeRunCadenceProvider(
        cadencePattern: const <double>[168, 170],
      );
      final controller = RunTrackingController(
        cadenceProvider: cadenceProvider,
        locationProvider: _replayLocationProvider(startedAt),
      );

      controller.start(startedAt: startedAt);
      await Future<void>.delayed(Duration.zero);
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(seconds: 5)),
      );
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(seconds: 8)),
      );
      await Future<void>.delayed(Duration.zero);
      controller.advanceBy(const Duration(seconds: 10));

      final samples = controller
          .completionPayload(
            completedAt: startedAt.add(const Duration(seconds: 6)),
          )
          .cadenceAnalysisSeries
          ?.validAcceptedSamples;

      expect(samples, hasLength(1));
      expect(samples?.single.elapsedSeconds, 5);
      expect(samples?.single.cadenceSpm, 168);

      await cadenceProvider.dispose();
    });

    test('unavailable provider leaves cadence analysis unavailable', () {
      final startedAt = DateTime.utc(2026, 6, 24, 7);
      final controller = RunTrackingController(
        cadenceProvider: const UnavailableRunCadenceProvider(),
        locationProvider: _replayLocationProvider(startedAt),
      );

      controller.start(startedAt: startedAt);
      controller.advanceBy(const Duration(seconds: 180));
      final payload = controller.completionPayload(
        completedAt: startedAt.add(const Duration(seconds: 180)),
      );

      expect(payload.cadenceAnalysisSeries, isNull);
    });
  });
}

RunLocationProvider _replayLocationProvider(DateTime startedAt) {
  return ReplayRunLocationProvider([
    RunLocationReplaySample(
      activeOffset: Duration.zero,
      sample: RunLocationSample(
        recordedAt: startedAt,
        latitude: 1.300000,
        longitude: 103.800000,
      ),
    ),
    RunLocationReplaySample(
      activeOffset: const Duration(seconds: 60),
      sample: RunLocationSample(
        recordedAt: startedAt.add(const Duration(seconds: 60)),
        latitude: 1.301349,
        longitude: 103.800000,
      ),
    ),
    RunLocationReplaySample(
      activeOffset: const Duration(seconds: 120),
      sample: RunLocationSample(
        recordedAt: startedAt.add(const Duration(seconds: 120)),
        latitude: 1.302698,
        longitude: 103.800000,
      ),
    ),
    RunLocationReplaySample(
      activeOffset: const Duration(seconds: 180),
      sample: RunLocationSample(
        recordedAt: startedAt.add(const Duration(seconds: 180)),
        latitude: 1.304047,
        longitude: 103.800000,
      ),
    ),
  ]);
}
