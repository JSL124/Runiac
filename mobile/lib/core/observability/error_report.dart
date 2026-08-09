import 'dart:convert';

/// Immutable, client-pre-sanitised record of a captured error, queued for the
/// `reportAppError` callable.
///
/// The fields here are exactly the allowlisted payload keys the callable
/// accepts (`errorType, message, stackFrames, screen, appVersion, osVersion,
/// platform, fatal, occurredAt`). The server re-sanitises and re-derives
/// grouping, severity, and counters authoritatively; this model only carries
/// the observation, never anything computed client-side that the server is
/// meant to own.
class ErrorReport {
  const ErrorReport({
    required this.errorType,
    required this.message,
    required this.stackFrames,
    required this.screen,
    required this.appVersion,
    required this.osVersion,
    required this.platform,
    required this.fatal,
    required this.occurredAt,
  });

  final String errorType;
  final String message;
  final List<String> stackFrames;

  /// Never null and never empty. The server's `optionalScreen` validation
  /// rejects a literal `null` with `invalid-argument`, so this is always a
  /// real (if synthesised) label — see `resolveErrorReportScreen` in
  /// `runiac_error_reporter.dart` for how it is derived when no named route
  /// exists.
  final String screen;
  final String appVersion;
  final String osVersion;
  final String platform;
  final bool fatal;
  final DateTime occurredAt;

  /// The exact allowlisted payload the `reportAppError` callable accepts.
  /// Any additional key would be rejected server-side by
  /// `rejectUnsupportedFields`, so this map must never gain another key.
  Map<String, Object?> toPayload() {
    return <String, Object?>{
      'errorType': errorType,
      'message': message,
      'stackFrames': stackFrames,
      'screen': screen,
      'appVersion': appVersion,
      'osVersion': osVersion,
      'platform': platform,
      'fatal': fatal,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
    };
  }

  String encode() => jsonEncode(toPayload());

  static ErrorReport? tryDecode(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        return null;
      }
      final map = decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      return _fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static ErrorReport? _fromJson(Map<String, Object?> source) {
    final errorType = source['errorType'];
    final message = source['message'];
    final appVersion = source['appVersion'];
    final osVersion = source['osVersion'];
    final platform = source['platform'];
    final fatal = source['fatal'];
    final occurredAtRaw = source['occurredAt'];
    if (errorType is! String ||
        message is! String ||
        appVersion is! String ||
        osVersion is! String ||
        platform is! String ||
        fatal is! bool ||
        occurredAtRaw is! String) {
      return null;
    }
    final occurredAt = DateTime.tryParse(occurredAtRaw);
    if (occurredAt == null) {
      return null;
    }
    final rawFrames = source['stackFrames'];
    final stackFrames = rawFrames is List
        ? rawFrames.whereType<String>().toList(growable: false)
        : const <String>[];
    final rawScreen = source['screen'];
    // Tolerate a null/blank/missing `screen` on decode rather than failing
    // the whole record: this only affects a report persisted before the
    // client started deriving a real label, and "unknown" is exactly the
    // fallback a fresh report would carry in that same situation.
    final screen = (rawScreen is String && rawScreen.isNotEmpty)
        ? rawScreen
        : 'unknown';
    return ErrorReport(
      errorType: errorType,
      message: message,
      stackFrames: stackFrames,
      screen: screen,
      appVersion: appVersion,
      osVersion: osVersion,
      platform: platform,
      fatal: fatal,
      occurredAt: occurredAt,
    );
  }
}
