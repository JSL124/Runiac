enum FriendsRepositoryErrorCode {
  authRequired,
  invalidRequest,
  tryAgainLater,
  staleState,
  unavailable,
}

class FriendsRepositoryException implements Exception {
  const FriendsRepositoryException(this.code, {this.message});

  final FriendsRepositoryErrorCode code;
  final String? message;

  String get userMessage => switch (code) {
    FriendsRepositoryErrorCode.authRequired =>
      'Sign in to view and manage friends.',
    FriendsRepositoryErrorCode.invalidRequest =>
      'Check the nickname and try again.',
    FriendsRepositoryErrorCode.tryAgainLater =>
      'Please wait a moment and try again.',
    FriendsRepositoryErrorCode.staleState =>
      'That friend state changed. Refresh and try again.',
    FriendsRepositoryErrorCode.unavailable =>
      'Friends are temporarily unavailable. Try again.',
  };

  @override
  String toString() => 'FriendsRepositoryException(code: $code)';
}

FriendsRepositoryException mapFriendsCallableError({
  required String transportCode,
  Object? details,
}) {
  final reason = details is Map<Object?, Object?> ? details['reason'] : null;
  final reasonError = reason is String ? _mapCallableCode(reason) : null;
  return reasonError ??
      _mapCallableCode(transportCode) ??
      const FriendsRepositoryException(FriendsRepositoryErrorCode.unavailable);
}

FriendsRepositoryException mapFriendsFirestoreError(String code) {
  return const FriendsRepositoryException(
    FriendsRepositoryErrorCode.unavailable,
  );
}

FriendsRepositoryException? _mapCallableCode(String code) {
  return switch (code) {
    'AUTH_REQUIRED' || 'UNAUTHENTICATED' || 'unauthenticated' =>
      const FriendsRepositoryException(FriendsRepositoryErrorCode.authRequired),
    'INVALID_NICKNAME' ||
    'INVALID_ARGUMENT' ||
    'invalid-argument' => const FriendsRepositoryException(
      FriendsRepositoryErrorCode.invalidRequest,
    ),
    'TRY_AGAIN_LATER' ||
    'RESOURCE_EXHAUSTED' ||
    'resource-exhausted' => const FriendsRepositoryException(
      FriendsRepositoryErrorCode.tryAgainLater,
    ),
    'STALE_SOCIAL_STATE' || 'FAILED_PRECONDITION' || 'failed-precondition' =>
      const FriendsRepositoryException(FriendsRepositoryErrorCode.staleState),
    _ => null,
  };
}
