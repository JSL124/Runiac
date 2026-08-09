// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/models/run_cadence_diagnostics.dart';
import '../domain/models/run_cadence_sample.dart';
import '../domain/models/cadence_analysis_series.dart';
import '../domain/repositories/run_cadence_provider.dart';

/// Reads step cadence from the phone's own motion hardware.
///
/// Cadence is estimated natively rather than in Dart — the Kotlin/Swift side
/// (`RuniacStepCadenceEstimator`) stays alive with the screen off, which a
/// Dart-side estimator would not. This class is the Flutter half of that
/// bridge: it starts and stops the native estimator over the method channel and
/// turns the event-channel stream into [RunCadenceSample]s.
///
/// Both channels are injectable so tests can drive cadence without a device.
class PhoneMotionRunCadenceProvider implements RunCadenceProvider {
  PhoneMotionRunCadenceProvider({
    MethodChannel methodChannel = const MethodChannel(
      'runiac/phone_motion_cadence',
    ),
    EventChannel eventChannel = const EventChannel(
      'runiac/phone_motion_cadence_events',
    ),
    Stream<Object?>? nativeEvents,
  }) : _methodChannel = methodChannel,
       _eventChannel = eventChannel,
       _nativeEvents = nativeEvents;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final Stream<Object?>? _nativeEvents;
  final StreamController<RunCadenceSample> _controller =
      StreamController<RunCadenceSample>.broadcast();
  final StreamController<RunCadenceDiagnostics> _diagnosticsController =
      StreamController<RunCadenceDiagnostics>.broadcast();

  StreamSubscription<Object?>? _nativeSubscription;
  RunCadenceDiagnostics _diagnostics = const RunCadenceDiagnostics.initial();

  @override
  Stream<RunCadenceSample> get cadenceStream => _controller.stream;

  @override
  Stream<RunCadenceDiagnostics> get diagnosticsStream =>
      _diagnosticsController.stream;

  @override
  Future<bool> isAvailable() async {
    try {
      final available = await _methodChannel.invokeMethod<bool>('isAvailable');
      final isAvailable = available ?? false;
      _emitDiagnostics(
        _diagnostics.copyWith(
          availabilityStatus: isAvailable
              ? RunCadenceAvailabilityStatus.available
              : RunCadenceAvailabilityStatus.unavailable,
          latestReason: isAvailable
              ? RunCadenceDiagnosticReason.available
              : RunCadenceDiagnosticReason.unavailable,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      return isAvailable;
    } on PlatformException {
      _recordNativeError(
        code: 'isAvailablePlatformException',
        message: 'Cadence availability check failed.',
      );
      return false;
    } on MissingPluginException {
      _recordNativeError(
        code: 'missingPlugin',
        message: 'Cadence native plugin is unavailable.',
      );
      return false;
    }
  }

  @override
  Future<void> start() async {
    final permissionGranted = await _requestPermission();
    if (!permissionGranted || !await isAvailable()) {
      return;
    }
    await _subscribe();
  }

  @override
  Future<void> pause() async {
    await _unsubscribe();
  }

  @override
  Future<void> resume() async {
    if (!await isAvailable()) {
      return;
    }
    await _subscribe();
  }

  @override
  Future<void> stop() async {
    await _unsubscribe();
  }

  Future<void> _subscribe() async {
    if (_nativeSubscription != null) {
      return;
    }
    final events = _nativeEvents ?? _eventChannel.receiveBroadcastStream();
    _nativeSubscription = events.listen(
      (event) {
        final sample = _handleNativeEvent(event);
        if (sample != null && !_controller.isClosed) {
          _controller.add(sample);
        }
      },
      onError: (Object error) {
        _recordNativeError(code: 'nativeStreamError', message: '$error');
      },
    );
  }

  Future<void> _unsubscribe() async {
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
  }

  Future<bool> _requestPermission() async {
    try {
      final result = await _methodChannel.invokeMethod<Object?>(
        'requestPermission',
      );
      final permissionStatus = _permissionStatusFrom(result);
      _emitDiagnostics(
        _diagnostics.copyWith(
          permissionStatus: permissionStatus,
          latestReason: _reasonForPermission(permissionStatus),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      return permissionStatus == RunCadencePermissionStatus.granted ||
          permissionStatus == RunCadencePermissionStatus.notRequired ||
          permissionStatus == RunCadencePermissionStatus.unknown;
    } on PlatformException catch (error) {
      _recordNativeError(
        code: error.code,
        message: error.message ?? 'Cadence permission request failed.',
      );
      return false;
    } on MissingPluginException {
      _recordNativeError(
        code: 'missingPlugin',
        message: 'Cadence native plugin is unavailable.',
      );
      return false;
    }
  }

  Future<void> dispose() async {
    await _unsubscribe();
    await _controller.close();
    await _diagnosticsController.close();
  }

  RunCadenceSample? _handleNativeEvent(Object? event) {
    if (event is! Map) {
      _recordMalformedEvent();
      return null;
    }
    if (event['type'] == 'diagnostic') {
      if ((event.containsKey('filteredCadenceCount') &&
              _readNonNegativeInt(event['filteredCadenceCount']) == null) ||
          (event.containsKey('nativeErrorCount') &&
              _readNonNegativeInt(event['nativeErrorCount']) == null)) {
        _recordMalformedEvent();
        return null;
      }
      _emitDiagnostics(_diagnosticsFromEvent(event));
      return null;
    }
    if (event['type'] != 'sample') {
      _recordMalformedEvent();
      return null;
    }
    final cadence = event['stepsPerMinute'];
    final recordedAtMillis = _readNativeTimestampMillis(
      event['recordedAtMillis'],
    );
    final acceptedCadenceCount = event.containsKey('acceptedCadenceCount')
        ? _readNonNegativeInt(event['acceptedCadenceCount'])
        : null;
    if (cadence is! num ||
        !cadence.isFinite ||
        cadence < 40 ||
        cadence > maxCadenceAnalysisSpm ||
        recordedAtMillis == null ||
        (event.containsKey('acceptedCadenceCount') &&
            acceptedCadenceCount == null)) {
      _recordMalformedEvent();
      return null;
    }
    final recordedAt = DateTime.fromMillisecondsSinceEpoch(
      recordedAtMillis,
      isUtc: true,
    );
    _emitDiagnostics(
      _diagnostics.copyWith(
        acceptedSampleCount:
            acceptedCadenceCount ?? _diagnostics.acceptedSampleCount + 1,
        latestReason: RunCadenceDiagnosticReason.acceptedSample,
        updatedAt: recordedAt,
      ),
    );
    return RunCadenceSample(
      recordedAt: recordedAt,
      stepsPerMinute: cadence.toDouble(),
      source: CadenceSource.phoneMotion,
      confidence: _confidenceFrom(event['confidence']),
    );
  }

  CadenceConfidence _confidenceFrom(Object? value) {
    return switch (value) {
      'high' => CadenceConfidence.high,
      'low' => CadenceConfidence.low,
      'unavailable' => CadenceConfidence.unavailable,
      _ => CadenceConfidence.estimated,
    };
  }

  RunCadenceDiagnostics _diagnosticsFromEvent(Map event) {
    final reason = _diagnosticReasonFrom(event['reason']);
    final filteredCount = _readNonNegativeInt(event['filteredCadenceCount']);
    final nativeErrorCount = _readNonNegativeInt(event['nativeErrorCount']);
    return _diagnostics.copyWith(
      latestReason: reason,
      availabilityStatus: _availabilityStatusFrom(event['availabilityStatus']),
      permissionStatus: _permissionStatusFrom(event['permissionStatus']),
      filteredCadenceCount:
          filteredCount ??
          (reason == RunCadenceDiagnosticReason.filteredOutOfRange
              ? _diagnostics.filteredCadenceCount + 1
              : _diagnostics.filteredCadenceCount),
      nativeErrorCount:
          nativeErrorCount ??
          (reason == RunCadenceDiagnosticReason.nativeError
              ? _diagnostics.nativeErrorCount + 1
              : _diagnostics.nativeErrorCount),
      latestFilteredCadenceSpm: _readInt(event['stepsPerMinute']),
      latestNativeErrorCode: _readString(event['errorCode']),
      latestNativeErrorMessage: _readString(event['errorMessage']),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  void _recordMalformedEvent() {
    _emitDiagnostics(
      _diagnostics.copyWith(
        latestReason: RunCadenceDiagnosticReason.malformedEvent,
        malformedEventCount: _diagnostics.malformedEventCount + 1,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _recordNativeError({required String code, required String message}) {
    _emitDiagnostics(
      _diagnostics.copyWith(
        latestReason: RunCadenceDiagnosticReason.nativeError,
        nativeErrorCount: _diagnostics.nativeErrorCount + 1,
        latestNativeErrorCode: code,
        latestNativeErrorMessage: message,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _emitDiagnostics(RunCadenceDiagnostics diagnostics) {
    _diagnostics = diagnostics;
    if (!_diagnosticsController.isClosed) {
      _diagnosticsController.add(diagnostics);
    }
  }

  RunCadencePermissionStatus _permissionStatusFrom(Object? value) {
    return switch (value) {
      'granted' => RunCadencePermissionStatus.granted,
      'authorized' => RunCadencePermissionStatus.granted,
      'notRequired' => RunCadencePermissionStatus.notRequired,
      'denied' => RunCadencePermissionStatus.denied,
      'restricted' => RunCadencePermissionStatus.restricted,
      'unknown' => RunCadencePermissionStatus.unknown,
      'notDetermined' => RunCadencePermissionStatus.unknown,
      _ => _diagnostics.permissionStatus,
    };
  }

  RunCadenceAvailabilityStatus _availabilityStatusFrom(Object? value) {
    return switch (value) {
      'available' => RunCadenceAvailabilityStatus.available,
      'unavailable' => RunCadenceAvailabilityStatus.unavailable,
      _ => _diagnostics.availabilityStatus,
    };
  }

  RunCadenceDiagnosticReason _reasonForPermission(
    RunCadencePermissionStatus status,
  ) {
    return switch (status) {
      RunCadencePermissionStatus.granted =>
        RunCadenceDiagnosticReason.permissionGranted,
      RunCadencePermissionStatus.notRequired =>
        RunCadenceDiagnosticReason.permissionGranted,
      RunCadencePermissionStatus.denied =>
        RunCadenceDiagnosticReason.permissionDenied,
      RunCadencePermissionStatus.restricted =>
        RunCadenceDiagnosticReason.permissionRestricted,
      RunCadencePermissionStatus.unknown =>
        RunCadenceDiagnosticReason.permissionUnknown,
      RunCadencePermissionStatus.notChecked => RunCadenceDiagnosticReason.none,
    };
  }

  RunCadenceDiagnosticReason _diagnosticReasonFrom(Object? value) {
    return switch (value) {
      'available' => RunCadenceDiagnosticReason.available,
      'unavailable' => RunCadenceDiagnosticReason.unavailable,
      'permissionDenied' => RunCadenceDiagnosticReason.permissionDenied,
      'permissionRestricted' => RunCadenceDiagnosticReason.permissionRestricted,
      'permissionUnknown' => RunCadenceDiagnosticReason.permissionUnknown,
      'streamStarted' => RunCadenceDiagnosticReason.streamStarted,
      'nativeError' => RunCadenceDiagnosticReason.nativeError,
      'nilData' => RunCadenceDiagnosticReason.nilData,
      'filteredOutOfRange' => RunCadenceDiagnosticReason.filteredOutOfRange,
      'malformedEvent' => RunCadenceDiagnosticReason.malformedEvent,
      _ => RunCadenceDiagnosticReason.none,
    };
  }

  int? _readInt(Object? value) {
    if (value is num && value.isFinite) {
      return value.round();
    }
    return null;
  }

  int? _readNonNegativeInt(Object? value) {
    final parsed = _readInt(value);
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  int? _readNativeTimestampMillis(Object? value) {
    if (value is! num || !value.isFinite) {
      return null;
    }
    const maxDateTimeMilliseconds = 8640000000000000;
    final rounded = value.round();
    if (value.toDouble() != rounded.toDouble() ||
        rounded < -maxDateTimeMilliseconds ||
        rounded > maxDateTimeMilliseconds) {
      return null;
    }
    return rounded;
  }

  String? _readString(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }
}
