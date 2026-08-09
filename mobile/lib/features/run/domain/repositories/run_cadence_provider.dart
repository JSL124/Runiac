import 'dart:async';

import '../models/run_cadence_diagnostics.dart';
import '../models/run_cadence_sample.dart';

abstract interface class RunCadenceProvider {
  Stream<RunCadenceSample> get cadenceStream;

  Stream<RunCadenceDiagnostics> get diagnosticsStream;

  Future<bool> isAvailable();

  Future<void> start();

  Future<void> pause();

  Future<void> resume();

  Future<void> stop();
}

class UnavailableRunCadenceProvider implements RunCadenceProvider {
  const UnavailableRunCadenceProvider();

  @override
  Stream<RunCadenceSample> get cadenceStream => const Stream.empty();

  @override
  Stream<RunCadenceDiagnostics> get diagnosticsStream => Stream.value(
    const RunCadenceDiagnostics(
      availabilityStatus: RunCadenceAvailabilityStatus.unavailable,
      latestReason: RunCadenceDiagnosticReason.unavailable,
    ),
  );

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> start() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}
}

class FakeRunCadenceProvider implements RunCadenceProvider {
  FakeRunCadenceProvider({
    this.cadencePattern = const <double>[168, 170, 172, 174],
  });

  final List<double> cadencePattern;
  final StreamController<RunCadenceSample> _controller =
      StreamController<RunCadenceSample>.broadcast();
  final StreamController<RunCadenceDiagnostics> _diagnosticsController =
      StreamController<RunCadenceDiagnostics>.broadcast();

  bool _active = false;
  int _sampleIndex = 0;

  @override
  Stream<RunCadenceSample> get cadenceStream => _controller.stream;

  @override
  Stream<RunCadenceDiagnostics> get diagnosticsStream =>
      _diagnosticsController.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> start() async {
    _active = true;
    _sampleIndex = 0;
    _emitDiagnostics(
      const RunCadenceDiagnostics(
        availabilityStatus: RunCadenceAvailabilityStatus.available,
        permissionStatus: RunCadencePermissionStatus.notRequired,
        latestReason: RunCadenceDiagnosticReason.available,
      ),
    );
  }

  @override
  Future<void> pause() async {
    _active = false;
  }

  @override
  Future<void> resume() async {
    _active = true;
  }

  @override
  Future<void> stop() async {
    _active = false;
  }

  void emitNext({required DateTime recordedAt}) {
    if (!_active || _controller.isClosed || cadencePattern.isEmpty) {
      return;
    }
    final cadence = cadencePattern[_sampleIndex % cadencePattern.length];
    _sampleIndex += 1;
    _controller.add(
      RunCadenceSample(
        recordedAt: recordedAt,
        stepsPerMinute: cadence,
        source: CadenceSource.phoneMotion,
        confidence: CadenceConfidence.estimated,
      ),
    );
    _emitDiagnostics(
      RunCadenceDiagnostics(
        availabilityStatus: RunCadenceAvailabilityStatus.available,
        permissionStatus: RunCadencePermissionStatus.notRequired,
        latestReason: RunCadenceDiagnosticReason.acceptedSample,
        acceptedSampleCount: _sampleIndex,
        updatedAt: recordedAt,
      ),
    );
  }

  void _emitDiagnostics(RunCadenceDiagnostics diagnostics) {
    if (!_diagnosticsController.isClosed) {
      _diagnosticsController.add(diagnostics);
    }
  }

  Future<void> dispose() async {
    await _controller.close();
    await _diagnosticsController.close();
  }
}
