import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/observability/error_report.dart';

void main() {
  test('toPayload emits exactly the allowlisted keys', () {
    final report = ErrorReport(
      errorType: 'StateError',
      message: 'boom',
      stackFrames: const ['package:runiac_app/a.dart 1:1 foo'],
      screen: 'HomeScreen',
      appVersion: '1.0.0+1',
      osVersion: 'test-os',
      platform: 'test-platform',
      fatal: true,
      occurredAt: DateTime.utc(2026, 1, 1),
    );

    expect(report.toPayload().keys.toSet(), {
      'errorType',
      'message',
      'stackFrames',
      'screen',
      'appVersion',
      'osVersion',
      'platform',
      'fatal',
      'occurredAt',
    });
    expect(report.toPayload()['occurredAt'], '2026-01-01T00:00:00.000Z');
  });

  test('encode/tryDecode round-trips a report', () {
    final report = ErrorReport(
      errorType: 'StateError',
      message: 'boom',
      stackFrames: const ['package:runiac_app/a.dart 1:1 foo'],
      screen: 'HomeScreen',
      appVersion: '1.0.0+1',
      osVersion: 'test-os',
      platform: 'test-platform',
      fatal: true,
      occurredAt: DateTime.utc(2026, 1, 1),
    );

    final decoded = ErrorReport.tryDecode(report.encode());

    expect(decoded, isNotNull);
    expect(decoded!.toPayload(), report.toPayload());
  });

  test('tryDecode rejects malformed input', () {
    expect(ErrorReport.tryDecode('not json'), isNull);
    expect(ErrorReport.tryDecode('{"errorType": 1}'), isNull);
    expect(ErrorReport.tryDecode('[]'), isNull);
  });
}
