class RunCompletionException implements Exception {
  const RunCompletionException({
    required this.code,
    required this.message,
    required this.isRetryable,
  });

  final String code;
  final String message;
  final bool isRetryable;

  @override
  String toString() {
    return 'RunCompletionException($code, retryable: $isRetryable): $message';
  }
}
