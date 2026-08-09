import 'package:shared_preferences/shared_preferences.dart';

import 'error_report.dart';

/// Bounds how many reports the durable buffer keeps. Older entries are
/// dropped first once the cap is exceeded, so a crash-on-launch loop cannot
/// grow this store without bound.
const int pendingErrorReportCap = 50;

abstract interface class LocalPendingErrorReportStore {
  Future<List<ErrorReport>> load();

  Future<void> save(List<ErrorReport> reports);
}

class MemoryLocalPendingErrorReportStore
    implements LocalPendingErrorReportStore {
  List<ErrorReport> _reports = const <ErrorReport>[];

  @override
  Future<List<ErrorReport>> load() async {
    return List<ErrorReport>.of(_reports);
  }

  @override
  Future<void> save(List<ErrorReport> reports) async {
    _reports = _capped(reports);
  }
}

class SharedPreferencesLocalPendingErrorReportStore
    implements LocalPendingErrorReportStore {
  const SharedPreferencesLocalPendingErrorReportStore({
    this.key = 'runiac.pendingErrorReports.v1',
  });

  final String key;

  @override
  Future<List<ErrorReport>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final rawRecords = preferences.getStringList(key) ?? const <String>[];
    return rawRecords
        .map(ErrorReport.tryDecode)
        .nonNulls
        .toList(growable: false);
  }

  @override
  Future<void> save(List<ErrorReport> reports) async {
    final preferences = await SharedPreferences.getInstance();
    final didPersist = await preferences.setStringList(
      key,
      _capped(
        reports,
      ).map((report) => report.encode()).toList(growable: false),
    );
    if (!didPersist) {
      throw StateError('Pending error report storage write failed.');
    }
  }
}

/// Keeps only the newest [pendingErrorReportCap] entries, dropping the
/// oldest first. Reports are expected to be stored oldest-first.
List<ErrorReport> _capped(List<ErrorReport> reports) {
  if (reports.length <= pendingErrorReportCap) {
    return List<ErrorReport>.of(reports);
  }
  return reports
      .sublist(reports.length - pendingErrorReportCap)
      .toList(growable: false);
}
