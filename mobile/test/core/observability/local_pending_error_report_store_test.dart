import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runiac_app/core/observability/error_report.dart';
import 'package:runiac_app/core/observability/local_pending_error_report_store.dart';

void main() {
  group('MemoryLocalPendingErrorReportStore', () {
    test('round-trips saved reports', () async {
      final store = MemoryLocalPendingErrorReportStore();
      final reports = [_report('a'), _report('b')];

      await store.save(reports);
      final loaded = await store.load();

      expect(loaded.map((report) => report.message), ['a', 'b']);
    });

    test('caps at 50 entries and drops the oldest first', () async {
      final store = MemoryLocalPendingErrorReportStore();
      final reports = [for (var i = 0; i < 60; i++) _report('message-$i')];

      await store.save(reports);
      final loaded = await store.load();

      expect(loaded, hasLength(pendingErrorReportCap));
      expect(loaded.first.message, 'message-10');
      expect(loaded.last.message, 'message-59');
    });
  });

  group('SharedPreferencesLocalPendingErrorReportStore', () {
    test('round-trips saved reports across store instances', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = SharedPreferencesLocalPendingErrorReportStore(
        key: 'test.pendingErrorReports',
      );

      await store.save([_report('a'), _report('b')]);
      final reloaded = const SharedPreferencesLocalPendingErrorReportStore(
        key: 'test.pendingErrorReports',
      );
      final loaded = await reloaded.load();

      expect(loaded.map((report) => report.message), ['a', 'b']);
    });

    test('caps at 50 entries and drops the oldest first', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = SharedPreferencesLocalPendingErrorReportStore(
        key: 'test.pendingErrorReportsOverflow',
      );
      final reports = [for (var i = 0; i < 60; i++) _report('message-$i')];

      await store.save(reports);
      final loaded = await store.load();

      expect(loaded, hasLength(pendingErrorReportCap));
      expect(loaded.first.message, 'message-10');
      expect(loaded.last.message, 'message-59');
    });
  });
}

ErrorReport _report(String message) {
  return ErrorReport(
    errorType: 'StateError',
    message: message,
    stackFrames: const <String>[],
    screen: 'HomeScreen',
    appVersion: '1.0.0+1',
    osVersion: 'test-os',
    platform: 'test-platform',
    fatal: false,
    occurredAt: DateTime.utc(2026, 1, 1),
  );
}
