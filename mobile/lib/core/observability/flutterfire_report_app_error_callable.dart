import 'package:cloud_functions/cloud_functions.dart';

/// Requests the server-owned `reportAppError` callable. Injectable so tests
/// can substitute a fake without touching Firebase.
abstract interface class ReportAppErrorCallable {
  Future<Map<String, Object?>> call(Map<String, Object?> request);
}

/// Translates the callable's failure modes into a typed shape. Nothing in
/// `RuniacErrorReporter` surfaces this to the user — it exists so the
/// reporter has a single, typed failure to catch and swallow.
class ReportAppErrorException implements Exception {
  const ReportAppErrorException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'ReportAppErrorException(code: $code)';
}

class FlutterFireReportAppErrorCallable implements ReportAppErrorCallable {
  FlutterFireReportAppErrorCallable({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    try {
      final result = await _functions
          .httpsCallable('reportAppError')
          .call(request);
      final data = result.data;
      if (data is Map<String, Object?>) {
        return data;
      }
      if (data is Map) {
        return data.map((key, value) => MapEntry(key.toString(), value));
      }
      throw const ReportAppErrorException(
        code: 'invalid-response',
        message: 'reportAppError returned an unexpected response shape.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw ReportAppErrorException(
        code: error.code,
        message: error.message ?? 'reportAppError call failed.',
      );
    }
  }
}
