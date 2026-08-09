import 'package:cloud_functions/cloud_functions.dart';

/// Requests the server-owned `submitFeedback` callable. Injectable so tests
/// can substitute a fake without touching Firebase.
abstract interface class SubmitFeedbackCallable {
  Future<Map<String, Object?>> call(Map<String, Object?> request);
}

/// A typed, user-facing wrapper around the callable's failure modes. The
/// server is the source of truth for validation and rate limiting; this
/// exception only translates its response into copy the screen can show.
class SubmitFeedbackException implements Exception {
  const SubmitFeedbackException({
    required this.code,
    required this.userMessage,
  });

  final String code;
  final String userMessage;

  @override
  String toString() => 'SubmitFeedbackException(code: $code)';
}

class FlutterFireSubmitFeedbackCallable implements SubmitFeedbackCallable {
  FlutterFireSubmitFeedbackCallable({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    try {
      final result = await _functions
          .httpsCallable('submitFeedback')
          .call(request);
      final data = result.data;
      if (data is Map<String, Object?>) {
        return data;
      }
      if (data is Map) {
        return data.map((key, value) => MapEntry(key.toString(), value));
      }
      throw const SubmitFeedbackException(
        code: 'invalid-response',
        userMessage: 'Something went wrong. Please try again.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw SubmitFeedbackException(
        code: error.code,
        userMessage: _userMessageFor(error),
      );
    }
  }

  String _userMessageFor(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'resource-exhausted':
        return "You've sent several reports recently. Please try again later.";
      case 'unauthenticated':
        return 'Please sign in to send feedback.';
      case 'invalid-argument':
        return error.message ?? 'Please check your feedback and try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
