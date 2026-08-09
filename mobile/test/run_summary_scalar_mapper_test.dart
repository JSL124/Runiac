import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/services/run_summary_scalar_mapper.dart';

void main() {
  group('RunSummaryScalarMapper', () {
    const mapper = RunSummaryScalarMapper();

    test('keeps distance duration and pace thresholds consistent', () {
      const cases = <_ScalarCase>[
        _ScalarCase(
          label: 'short distance',
          distanceMeters: 49,
          durationSeconds: 300,
          paceSecondsPerKm: 360,
          expectedPace: '--',
          expectedSufficientData: false,
        ),
        _ScalarCase(
          label: 'short duration',
          distanceMeters: 1000,
          durationSeconds: 59,
          paceSecondsPerKm: 360,
          expectedPace: '--',
          expectedSufficientData: false,
        ),
        _ScalarCase(
          label: 'too fast',
          distanceMeters: 1000,
          durationSeconds: 180,
          paceSecondsPerKm: 149,
          expectedPace: '--',
          expectedSufficientData: false,
        ),
        _ScalarCase(
          label: 'too slow',
          distanceMeters: 1000,
          durationSeconds: 1900,
          paceSecondsPerKm: 1801,
          expectedPace: '--',
          expectedSufficientData: false,
        ),
        _ScalarCase(
          label: 'normal pace',
          distanceMeters: 1000,
          durationSeconds: 450,
          paceSecondsPerKm: 450,
          expectedPace: '7’30”',
          expectedSufficientData: true,
        ),
      ];

      for (final testCase in cases) {
        final scalar = mapper.map(
          completedAt: DateTime.utc(2026, 6, 14, 7, 25),
          distanceMeters: testCase.distanceMeters,
          durationSeconds: testCase.durationSeconds,
          averagePaceSecondsPerKm: testCase.paceSecondsPerKm,
          routeLabel: 'Repository Result Route',
        );

        expect(scalar.avgPace, testCase.expectedPace, reason: testCase.label);
        expect(
          scalar.hasSufficientData,
          testCase.expectedSufficientData,
          reason: testCase.label,
        );
      }
    });
  });
}

class _ScalarCase {
  const _ScalarCase({
    required this.label,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.paceSecondsPerKm,
    required this.expectedPace,
    required this.expectedSufficientData,
  });

  final String label;
  final int distanceMeters;
  final int durationSeconds;
  final int paceSecondsPerKm;
  final String expectedPace;
  final bool expectedSufficientData;
}
