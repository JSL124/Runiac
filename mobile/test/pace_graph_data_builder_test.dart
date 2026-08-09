import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/services/pace_graph_data_builder.dart';
import 'package:runiac_app/features/run/presentation/data/pace_graph_demo_snapshots.dart';

void main() {
  group('PaceGraphDataBuilder', () {
    const builder = PaceGraphDataBuilder();

    test(
      'normal easy run returns available graph with normalized progress',
      () {
        final graph = builder.build(
          samples: normalEasyRunPaceSamples,
          durationSeconds: 1815,
          distanceMeters: 4030,
          averagePaceSecondsPerKm: 390,
        );

        expect(graph.isAvailable, isTrue);
        expect(graph.points.length, greaterThanOrEqualTo(3));
        expect(graph.points.first.progressFraction, 0);
        expect(graph.points.last.progressFraction, closeTo(1770 / 1815, 0.001));
        expect(
          graph.points.every(
            (point) =>
                point.progressFraction >= 0 && point.progressFraction <= 1,
          ),
          isTrue,
        );
        expect(graph.totalDurationSeconds, 1815);
        expect(graph.averagePaceSecondsPerKm, 390);
        expect(graph.bestPacePoint?.paceSecondsPerKm, 382);
        expect(graph.slowestPacePoint?.paceSecondsPerKm, 405);
        expect(graph.paceRangeMinSecondsPerKm, 360);
        expect(graph.paceRangeMaxSecondsPerKm, 440);
      },
    );

    test('normal easy fixture graph matches builder output', () {
      final graph = builder.build(
        samples: normalEasyRunPaceSamples,
        durationSeconds: 1815,
        distanceMeters: 4030,
        averagePaceSecondsPerKm: 390,
      );

      expect(graph.isAvailable, normalEasyRunPaceGraph.isAvailable);
      expect(graph.xAxisLabels, normalEasyRunPaceGraph.xAxisLabels);
      expect(graph.yAxisLabels, normalEasyRunPaceGraph.yAxisLabels);
      expect(
        graph.totalDurationSeconds,
        normalEasyRunPaceGraph.totalDurationSeconds,
      );
      expect(
        graph.averagePaceSecondsPerKm,
        normalEasyRunPaceGraph.averagePaceSecondsPerKm,
      );
      expect(
        graph.bestPacePoint?.paceSecondsPerKm,
        normalEasyRunPaceGraph.bestPacePoint?.paceSecondsPerKm,
      );
      expect(
        graph.slowestPacePoint?.paceSecondsPerKm,
        normalEasyRunPaceGraph.slowestPacePoint?.paceSecondsPerKm,
      );
      expect(
        graph.paceRangeMinSecondsPerKm,
        normalEasyRunPaceGraph.paceRangeMinSecondsPerKm,
      );
      expect(
        graph.paceRangeMaxSecondsPerKm,
        normalEasyRunPaceGraph.paceRangeMaxSecondsPerKm,
      );
      expect(
        graph.points.map((point) => point.elapsedSeconds),
        normalEasyRunPaceGraph.points.map((point) => point.elapsedSeconds),
      );
      expect(
        graph.points.map((point) => point.paceSecondsPerKm),
        normalEasyRunPaceGraph.points.map((point) => point.paceSecondsPerKm),
      );
      expect(
        graph.points.map((point) => point.progressFraction),
        normalEasyRunPaceGraph.points.map((point) => point.progressFraction),
      );
    });

    test('build keeps time labels separate from distance axis data', () {
      final graph = builder.build(
        samples: const [
          PaceGraphSample(
            elapsedSeconds: 0,
            paceSecondsPerKm: 430,
            cumulativeDistanceMeters: 0,
          ),
          PaceGraphSample(
            elapsedSeconds: 120,
            paceSecondsPerKm: 432,
            cumulativeDistanceMeters: 250,
          ),
          PaceGraphSample(
            elapsedSeconds: 240,
            paceSecondsPerKm: 456,
            cumulativeDistanceMeters: 700,
          ),
          PaceGraphSample(
            elapsedSeconds: 480,
            paceSecondsPerKm: 425,
            cumulativeDistanceMeters: 1100,
          ),
        ],
        durationSeconds: 480,
        distanceMeters: 1100,
        averagePaceSecondsPerKm: 436,
      );

      expect(graph.isAvailable, isTrue);
      expect(graph.xAxisLabels, ['0:00', '4:00', '8:00']);
      expect(graph.distanceAxisLabels, ['0 km', '0.5 km', '1.1 km']);
      expect(
        graph.distanceAxisLabels,
        isNot(contains(anyOf('0:00', '4:00', '8:00'))),
      );
      expect(
        graph.points.map((point) => point.distanceProgressFraction).toList(),
        [0, closeTo(250 / 1100, 0.001), closeTo(700 / 1100, 0.001), 1],
      );
      expect(
        graph.points.map((point) => point.distanceProgressFraction).toList(),
        isNot(
          equals(graph.points.map((point) => point.progressFraction).toList()),
        ),
      );
      expect(graph.hasDistanceAxis, isTrue);
    });

    test('gps spike run filters unrealistic fast and slow pace values', () {
      final graph = builder.build(
        samples: gpsSpikeRunPaceSamples,
        durationSeconds: 1450,
        distanceMeters: 3200,
        averagePaceSecondsPerKm: 425,
      );

      expect(graph.isAvailable, isTrue);
      expect(graph.points.length, greaterThanOrEqualTo(3));
      expect(graph.xAxisLabels, ['0:00', '8:00', '16:00', '24:10']);
      expect(graph.averagePaceSecondsPerKm, 425);
      expect(graph.bestPacePoint?.paceSecondsPerKm, 410);
      expect(graph.slowestPacePoint?.paceSecondsPerKm, 440);
      expect(
        graph.points.any((point) => point.paceSecondsPerKm == 80),
        isFalse,
      );
      expect(
        graph.points.any((point) => point.paceSecondsPerKm == 2700),
        isFalse,
      );
    });

    test('build smooths noisy short-run samples for display', () {
      const rawSamples = <PaceGraphSample>[
        PaceGraphSample(elapsedSeconds: 12, paceSecondsPerKm: 380),
        PaceGraphSample(elapsedSeconds: 24, paceSecondsPerKm: 620),
        PaceGraphSample(elapsedSeconds: 36, paceSecondsPerKm: 410),
        PaceGraphSample(elapsedSeconds: 48, paceSecondsPerKm: 590),
        PaceGraphSample(elapsedSeconds: 66, paceSecondsPerKm: 430),
        PaceGraphSample(elapsedSeconds: 82, paceSecondsPerKm: 560),
        PaceGraphSample(elapsedSeconds: 101, paceSecondsPerKm: 445),
        PaceGraphSample(elapsedSeconds: 123, paceSecondsPerKm: 540),
        PaceGraphSample(elapsedSeconds: 144, paceSecondsPerKm: 460),
        PaceGraphSample(elapsedSeconds: 166, paceSecondsPerKm: 520),
        PaceGraphSample(elapsedSeconds: 188, paceSecondsPerKm: 475),
        PaceGraphSample(elapsedSeconds: 210, paceSecondsPerKm: 505),
      ];

      final graph = builder.build(
        samples: rawSamples,
        durationSeconds: 214,
        distanceMeters: 350,
        averagePaceSecondsPerKm: 611,
      );

      final rawRange = _paceRange(
        rawSamples.map((sample) {
          return sample.paceSecondsPerKm;
        }),
      );
      final displayRange = _paceRange(
        graph.points.map((point) {
          return point.paceSecondsPerKm;
        }),
      );

      expect(graph.isAvailable, isTrue);
      expect(graph.points.length, lessThan(rawSamples.length));
      expect(
        graph.points.first.elapsedSeconds,
        rawSamples.first.elapsedSeconds,
      );
      expect(graph.points.last.elapsedSeconds, rawSamples.last.elapsedSeconds);
      expect(
        _isStrictlyIncreasing(
          graph.points.map((point) {
            return point.elapsedSeconds;
          }),
        ),
        isTrue,
      );
      expect(displayRange, lessThan(rawRange));
    });

    test(
      'build prevents single-sample spike from dominating display range',
      () {
        final graph = builder.build(
          samples: const [
            PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 430),
            PaceGraphSample(elapsedSeconds: 10, paceSecondsPerKm: 300),
            PaceGraphSample(elapsedSeconds: 18, paceSecondsPerKm: 432),
            PaceGraphSample(elapsedSeconds: 40, paceSecondsPerKm: 434),
            PaceGraphSample(elapsedSeconds: 60, paceSecondsPerKm: 436),
            PaceGraphSample(elapsedSeconds: 80, paceSecondsPerKm: 438),
            PaceGraphSample(elapsedSeconds: 100, paceSecondsPerKm: 440),
          ],
          durationSeconds: 120,
          distanceMeters: 260,
          averagePaceSecondsPerKm: 462,
        );

        expect(graph.isAvailable, isTrue);
        expect(graph.bestPacePoint?.paceSecondsPerKm, isNot(300));
        expect(
          graph.points.map((point) => point.paceSecondsPerKm),
          isNot(contains(300)),
        );
        expect(
          graph.paceRangeMaxSecondsPerKm! - graph.paceRangeMinSecondsPerKm!,
          lessThanOrEqualTo(100),
        );
      },
    );

    test(
      'build prevents first endpoint fast spike from dominating display',
      () {
        final graph = builder.build(
          samples: const [
            PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 240),
            PaceGraphSample(elapsedSeconds: 22, paceSecondsPerKm: 430),
            PaceGraphSample(elapsedSeconds: 42, paceSecondsPerKm: 432),
            PaceGraphSample(elapsedSeconds: 62, paceSecondsPerKm: 434),
            PaceGraphSample(elapsedSeconds: 82, paceSecondsPerKm: 436),
            PaceGraphSample(elapsedSeconds: 102, paceSecondsPerKm: 438),
            PaceGraphSample(elapsedSeconds: 122, paceSecondsPerKm: 440),
          ],
          durationSeconds: 140,
          distanceMeters: 310,
          averagePaceSecondsPerKm: 452,
        );

        expect(graph.isAvailable, isTrue);
        expect(graph.points.first.elapsedSeconds, 0);
        expect(graph.bestPacePoint?.paceSecondsPerKm, isNot(240));
        expect(
          graph.points.map((point) => point.paceSecondsPerKm),
          isNot(contains(240)),
        );
        expect(graph.paceRangeMinSecondsPerKm, greaterThanOrEqualTo(380));
      },
    );

    test('build prevents last endpoint slow spike from dominating display', () {
      final graph = builder.build(
        samples: const [
          PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 430),
          PaceGraphSample(elapsedSeconds: 22, paceSecondsPerKm: 432),
          PaceGraphSample(elapsedSeconds: 42, paceSecondsPerKm: 434),
          PaceGraphSample(elapsedSeconds: 62, paceSecondsPerKm: 436),
          PaceGraphSample(elapsedSeconds: 82, paceSecondsPerKm: 438),
          PaceGraphSample(elapsedSeconds: 102, paceSecondsPerKm: 440),
          PaceGraphSample(elapsedSeconds: 122, paceSecondsPerKm: 900),
        ],
        durationSeconds: 140,
        distanceMeters: 310,
        averagePaceSecondsPerKm: 452,
      );

      expect(graph.isAvailable, isTrue);
      expect(graph.points.last.elapsedSeconds, 122);
      expect(graph.slowestPacePoint?.paceSecondsPerKm, isNot(900));
      expect(
        graph.points.map((point) => point.paceSecondsPerKm),
        isNot(contains(900)),
      );
      expect(graph.paceRangeMaxSecondsPerKm, lessThanOrEqualTo(480));
    });

    test(
      'build prevents singleton bucket fast spike from dominating display',
      () {
        final graph = builder.build(
          samples: const [
            PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 430),
            PaceGraphSample(elapsedSeconds: 22, paceSecondsPerKm: 432),
            PaceGraphSample(elapsedSeconds: 45, paceSecondsPerKm: 240),
            PaceGraphSample(elapsedSeconds: 82, paceSecondsPerKm: 434),
            PaceGraphSample(elapsedSeconds: 102, paceSecondsPerKm: 436),
            PaceGraphSample(elapsedSeconds: 122, paceSecondsPerKm: 438),
          ],
          durationSeconds: 140,
          distanceMeters: 310,
          averagePaceSecondsPerKm: 452,
        );

        expect(graph.isAvailable, isTrue);
        expect(graph.bestPacePoint?.paceSecondsPerKm, isNot(240));
        expect(
          graph.points.map((point) => point.paceSecondsPerKm),
          isNot(contains(240)),
        );
        expect(graph.paceRangeMinSecondsPerKm, greaterThanOrEqualTo(380));
      },
    );

    test(
      'build prevents singleton bucket slow spike from dominating display range',
      () {
        final graph = builder.build(
          samples: const [
            PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 430),
            PaceGraphSample(elapsedSeconds: 22, paceSecondsPerKm: 432),
            PaceGraphSample(elapsedSeconds: 45, paceSecondsPerKm: 900),
            PaceGraphSample(elapsedSeconds: 82, paceSecondsPerKm: 434),
            PaceGraphSample(elapsedSeconds: 102, paceSecondsPerKm: 436),
            PaceGraphSample(elapsedSeconds: 122, paceSecondsPerKm: 438),
          ],
          durationSeconds: 140,
          distanceMeters: 310,
          averagePaceSecondsPerKm: 452,
        );

        expect(graph.isAvailable, isTrue);
        expect(graph.slowestPacePoint?.paceSecondsPerKm, isNot(900));
        expect(
          graph.points.map((point) => point.paceSecondsPerKm),
          isNot(contains(900)),
        );
        expect(graph.paceRangeMaxSecondsPerKm, lessThanOrEqualTo(480));
      },
    );

    test(
      'filters samples beyond duration before returning pace graph points',
      () {
        final graph = builder.build(
          samples: const [
            PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 1100),
            PaceGraphSample(elapsedSeconds: 120, paceSecondsPerKm: 480),
            PaceGraphSample(elapsedSeconds: 180, paceSecondsPerKm: 720),
            PaceGraphSample(elapsedSeconds: 452, paceSecondsPerKm: 1100),
            PaceGraphSample(elapsedSeconds: 453, paceSecondsPerKm: 320),
            PaceGraphSample(elapsedSeconds: 470, paceSecondsPerKm: 1080),
          ],
          durationSeconds: 452,
          distanceMeters: 620,
          averagePaceSecondsPerKm: 729,
        );

        expect(graph.isAvailable, isTrue);
        expect(
          graph.points.every((point) => point.elapsedSeconds <= 452),
          isTrue,
        );
        expect(
          _isStrictlyIncreasing(
            graph.points.map((point) {
              return point.elapsedSeconds;
            }),
          ),
          isTrue,
        );
        expect(
          _hasUniqueRenderedProgress(
            graph.points.map((point) => point.elapsedSeconds),
            durationSeconds: 452,
          ),
          isTrue,
        );
      },
    );

    test(
      'build returns unavailable when fewer than three rendered x positions remain',
      () {
        final graph = builder.build(
          samples: const [
            PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 710),
            PaceGraphSample(elapsedSeconds: 452, paceSecondsPerKm: 720),
            PaceGraphSample(elapsedSeconds: 453, paceSecondsPerKm: 760),
            PaceGraphSample(elapsedSeconds: 470, paceSecondsPerKm: 840),
          ],
          durationSeconds: 452,
          distanceMeters: 620,
          averagePaceSecondsPerKm: 729,
        );

        expect(graph.isAvailable, isFalse);
        expect(graph.points, isEmpty);
      },
    );

    test(
      'invalid same-second samples do not block later valid graph samples',
      () {
        final graph = builder.build(
          samples: const [
            PaceGraphSample(elapsedSeconds: 30, paceSecondsPerKm: 90),
            PaceGraphSample(elapsedSeconds: 30, paceSecondsPerKm: 720),
            PaceGraphSample(elapsedSeconds: 60, paceSecondsPerKm: 730),
            PaceGraphSample(elapsedSeconds: 90, paceSecondsPerKm: 740),
          ],
          durationSeconds: 120,
          distanceMeters: 260,
          averagePaceSecondsPerKm: 729,
        );

        expect(graph.isAvailable, isTrue);
        expect(graph.points.map((point) => point.elapsedSeconds), [30, 60, 90]);
        expect(graph.points.map((point) => point.paceSecondsPerKm), [
          720,
          730,
          740,
        ]);
      },
    );

    test('endpoint anchoring does not restore beyond-duration line points', () {
      final graph = builder.build(
        samples: const [
          PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 710),
          PaceGraphSample(elapsedSeconds: 160, paceSecondsPerKm: 720),
          PaceGraphSample(elapsedSeconds: 320, paceSecondsPerKm: 730),
          PaceGraphSample(elapsedSeconds: 470, paceSecondsPerKm: 840),
        ],
        durationSeconds: 452,
        distanceMeters: 620,
        averagePaceSecondsPerKm: 729,
      );

      expect(graph.isAvailable, isTrue);
      expect(graph.points.last.elapsedSeconds, 320);
      expect(graph.points.every((point) => point.progressFraction < 1), isTrue);
    });

    test('build preserves broad pace trend after smoothing', () {
      final graph = builder.build(
        samples: const [
          PaceGraphSample(elapsedSeconds: 20, paceSecondsPerKm: 560),
          PaceGraphSample(elapsedSeconds: 45, paceSecondsPerKm: 525),
          PaceGraphSample(elapsedSeconds: 70, paceSecondsPerKm: 555),
          PaceGraphSample(elapsedSeconds: 95, paceSecondsPerKm: 520),
          PaceGraphSample(elapsedSeconds: 130, paceSecondsPerKm: 545),
          PaceGraphSample(elapsedSeconds: 170, paceSecondsPerKm: 510),
          PaceGraphSample(elapsedSeconds: 210, paceSecondsPerKm: 485),
          PaceGraphSample(elapsedSeconds: 250, paceSecondsPerKm: 455),
          PaceGraphSample(elapsedSeconds: 290, paceSecondsPerKm: 475),
          PaceGraphSample(elapsedSeconds: 330, paceSecondsPerKm: 445),
          PaceGraphSample(elapsedSeconds: 370, paceSecondsPerKm: 465),
          PaceGraphSample(elapsedSeconds: 410, paceSecondsPerKm: 435),
        ],
        durationSeconds: 430,
        distanceMeters: 900,
        averagePaceSecondsPerKm: 478,
      );

      final midpoint = graph.points.length ~/ 2;
      final firstHalfAverage = _averagePace(
        graph.points.take(midpoint).map((point) => point.paceSecondsPerKm),
      );
      final secondHalfAverage = _averagePace(
        graph.points.skip(midpoint).map((point) => point.paceSecondsPerKm),
      );

      expect(graph.isAvailable, isTrue);
      expect(firstHalfAverage, greaterThan(secondHalfAverage));
      expect(firstHalfAverage - secondHalfAverage, greaterThan(25));
    });

    test('build caps long-run display points deterministically', () {
      final rawSamples = List<PaceGraphSample>.generate(361, (index) {
        return PaceGraphSample(
          elapsedSeconds: index * 10,
          paceSecondsPerKm: 480 + (index % 9) - 4,
        );
      });

      final firstGraph = builder.build(
        samples: rawSamples,
        durationSeconds: 3600,
        distanceMeters: 8000,
        averagePaceSecondsPerKm: 450,
      );
      final secondGraph = builder.build(
        samples: rawSamples,
        durationSeconds: 3600,
        distanceMeters: 8000,
        averagePaceSecondsPerKm: 450,
      );

      expect(firstGraph.isAvailable, isTrue);
      expect(firstGraph.points.length, lessThanOrEqualTo(60));
      expect(
        firstGraph.points.first.elapsedSeconds,
        rawSamples.first.elapsedSeconds,
      );
      expect(
        firstGraph.points.last.elapsedSeconds,
        rawSamples.last.elapsedSeconds,
      );
      expect(
        _isStrictlyIncreasing(
          firstGraph.points.map((point) {
            return point.elapsedSeconds;
          }),
        ),
        isTrue,
      );
      expect(
        firstGraph.points.map((point) => point.elapsedSeconds),
        secondGraph.points.map((point) => point.elapsedSeconds),
      );
    });

    test('duration-based x axis uses total run time', () {
      final thirtyMinuteGraph = builder.build(
        samples: normalEasyRunPaceSamples,
        durationSeconds: 1815,
        distanceMeters: 4030,
      );
      final twelveMinuteGraph = builder.build(
        samples: normalEasyRunPaceSamples,
        durationSeconds: 720,
        distanceMeters: 1600,
      );

      expect(thirtyMinuteGraph.xAxisLabels, [
        '0:00',
        '10:00',
        '20:00',
        '30:15',
      ]);
      expect(twelveMinuteGraph.xAxisLabels, ['0:00', '6:00', '12:00']);
    });

    test('recovery fixture covers the long summary duration', () {
      expect(recoveryJogPaceGraph.isAvailable, isTrue);
      expect(recoveryJogPaceGraph.xAxisLabels, [
        '0:00',
        '13:00',
        '26:00',
        '39:38',
      ]);
      expect(recoveryJogPaceGraph.points.length, greaterThanOrEqualTo(3));
      expect(recoveryJogPaceGraph.points.last.elapsedSeconds, 2370);
      expect(
        recoveryJogPaceGraph.points.last.progressFraction,
        greaterThan(0.95),
      );
    });

    test('low-data run returns unavailable graph', () {
      final graph = builder.build(
        samples: lowDataRunPaceSamples,
        durationSeconds: 35,
        distanceMeters: 20,
      );

      expect(graph.isAvailable, isFalse);
      expect(graph.points, isEmpty);
      expect(graph.averagePaceSecondsPerKm, isNull);
      expect(graph.bestPacePoint, isNull);
      expect(graph.slowestPacePoint, isNull);
    });

    test('too few valid points run returns unavailable graph', () {
      final graph = builder.build(
        samples: tooFewValidPointsRunPaceSamples,
        durationSeconds: 360,
        distanceMeters: 800,
      );

      expect(graph.isAvailable, isFalse);
      expect(graph.points.length, lessThan(3));
    });

    test('filters threshold and non-increasing elapsed samples', () {
      final graph = builder.build(
        samples: const [
          PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 149),
          PaceGraphSample(elapsedSeconds: 30, paceSecondsPerKm: 450),
          PaceGraphSample(elapsedSeconds: 30, paceSecondsPerKm: 460),
          PaceGraphSample(elapsedSeconds: 20, paceSecondsPerKm: 470),
          PaceGraphSample(elapsedSeconds: 60, paceSecondsPerKm: 1801),
          PaceGraphSample(elapsedSeconds: 90, paceSecondsPerKm: 480),
          PaceGraphSample(elapsedSeconds: 120, paceSecondsPerKm: 490),
        ],
        durationSeconds: 180,
        distanceMeters: 600,
      );

      expect(graph.isAvailable, isTrue);
      expect(graph.points.map((point) => point.paceSecondsPerKm), [
        450,
        480,
        490,
      ]);
      expect(graph.points.map((point) => point.elapsedSeconds), [30, 90, 120]);
    });

    test('pace axis range keeps a minimum visible spread', () {
      final graph = builder.build(
        samples: const [
          PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 390),
          PaceGraphSample(elapsedSeconds: 120, paceSecondsPerKm: 392),
          PaceGraphSample(elapsedSeconds: 240, paceSecondsPerKm: 394),
        ],
        durationSeconds: 300,
        distanceMeters: 1000,
      );

      expect(graph.isAvailable, isTrue);
      expect(
        graph.paceRangeMaxSecondsPerKm! - graph.paceRangeMinSecondsPerKm!,
        greaterThanOrEqualTo(minVisiblePaceRangeSeconds),
      );

      final nearMaxGraph = builder.build(
        samples: const [
          PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 1788),
          PaceGraphSample(elapsedSeconds: 120, paceSecondsPerKm: 1792),
          PaceGraphSample(elapsedSeconds: 240, paceSecondsPerKm: 1796),
        ],
        durationSeconds: 300,
        distanceMeters: 1000,
      );
      expect(
        nearMaxGraph.paceRangeMaxSecondsPerKm! -
            nearMaxGraph.paceRangeMinSecondsPerKm!,
        greaterThanOrEqualTo(minVisiblePaceRangeSeconds),
      );
    });

    test('slow walk or pause run filters over-threshold slow values', () {
      final graph = builder.build(
        samples: slowWalkOrPauseRunPaceSamples,
        durationSeconds: 900,
        distanceMeters: 650,
      );

      expect(graph.isAvailable, isTrue);
      expect(
        graph.points.any((point) => point.paceSecondsPerKm > 1800),
        isFalse,
      );
    });
  });
}

int _paceRange(Iterable<int> values) {
  final list = values.toList();
  final min = list.reduce((a, b) => a < b ? a : b);
  final max = list.reduce((a, b) => a > b ? a : b);
  return max - min;
}

double _averagePace(Iterable<int> values) {
  final list = values.toList();
  return list.reduce((a, b) => a + b) / list.length;
}

bool _isStrictlyIncreasing(Iterable<int> values) {
  int? previous;
  for (final value in values) {
    if (previous != null && value <= previous) {
      return false;
    }
    previous = value;
  }
  return true;
}

bool _hasUniqueRenderedProgress(
  Iterable<int> elapsedSeconds, {
  required int durationSeconds,
}) {
  final renderedPositions = <double>{};
  for (final elapsedSecond in elapsedSeconds) {
    final progress = elapsedSecond / durationSeconds;
    final renderedProgress = progress.clamp(0.0, 1.0).toDouble();
    if (!renderedPositions.add(renderedProgress)) {
      return false;
    }
  }
  return true;
}
