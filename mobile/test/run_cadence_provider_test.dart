import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/run_cadence_sample.dart';
import 'package:runiac_app/features/run/domain/repositories/run_cadence_provider.dart';

void main() {
  group('RunCadenceProvider seam', () {
    test('RunCadenceSample preserves phone motion provenance', () {
      final recordedAt = DateTime.utc(2026, 6, 24, 7);
      final sample = RunCadenceSample(
        recordedAt: recordedAt,
        stepsPerMinute: 171,
        source: CadenceSource.phoneMotion,
        confidence: CadenceConfidence.estimated,
      );

      expect(sample.recordedAt, recordedAt);
      expect(sample.stepsPerMinute, 171);
      expect(sample.source, CadenceSource.phoneMotion);
      expect(sample.confidence, CadenceConfidence.estimated);
      expect(sample.isUsable, isTrue);
    });

    test('UnavailableRunCadenceProvider emits no fake cadence', () async {
      const provider = UnavailableRunCadenceProvider();

      await provider.start();

      expect(await provider.isAvailable(), isFalse);
      await expectLater(provider.cadenceStream, emitsDone);
    });

    test(
      'FakeRunCadenceProvider emits deterministic samples by lifecycle',
      () async {
        final provider = FakeRunCadenceProvider(cadencePattern: [166, 168]);
        final samples = <RunCadenceSample>[];
        final subscription = provider.cadenceStream.listen(samples.add);
        final startedAt = DateTime.utc(2026, 6, 24, 7);

        await provider.start();
        provider.emitNext(recordedAt: startedAt);
        provider.emitNext(
          recordedAt: startedAt.add(const Duration(seconds: 10)),
        );
        await provider.pause();
        provider.emitNext(
          recordedAt: startedAt.add(const Duration(seconds: 20)),
        );
        await provider.resume();
        provider.emitNext(
          recordedAt: startedAt.add(const Duration(seconds: 30)),
        );
        await Future<void>.delayed(Duration.zero);

        expect(samples.map((sample) => sample.stepsPerMinute), [166, 168, 166]);
        expect(
          samples.every((sample) => sample.source == CadenceSource.phoneMotion),
          isTrue,
        );

        await subscription.cancel();
        await provider.dispose();
      },
    );
  });
}
