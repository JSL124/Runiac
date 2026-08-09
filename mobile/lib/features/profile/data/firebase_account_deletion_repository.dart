import 'package:cloud_functions/cloud_functions.dart';

/// Requests the server-owned `requestAccountDeletion` callable.
///
/// The client cannot delete anything itself and deliberately does not try:
/// `firestore.rules` denies `create, update, delete` on `users/{uid}` to the
/// owner themselves, and the same denial covers every other collection holding
/// this runner's data. The whole erase is server-owned; this seam exists only
/// to ask for it and to translate the answer into copy a screen can show.
///
/// The interface lives beside its Firebase implementation rather than in
/// `domain/` because it has exactly one method and no domain model — splitting
/// it would add a file that says nothing the signature does not.
abstract interface class AccountDeletionRepository {
  /// Returns true when this call is what started the deletion, false when a
  /// deletion was already in flight for this account.
  Future<bool> requestAccountDeletion();
}

/// A typed, user-facing wrapper around the callable's failure modes.
class AccountDeletionException implements Exception {
  const AccountDeletionException({required this.code, required this.userMessage});

  final String code;
  final String userMessage;

  @override
  String toString() => 'AccountDeletionException(code: $code)';
}

class FirebaseAccountDeletionRepository implements AccountDeletionRepository {
  FirebaseAccountDeletionRepository({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  @override
  Future<bool> requestAccountDeletion() async {
    try {
      final result = await _functions
          .httpsCallable('requestAccountDeletion')
          // The server requires this exact token too. The screen already gates
          // on it, so sending it is belt-and-braces against a mis-wired caller
          // rather than a security control — an attacker would simply send it.
          .call<Object?>(<String, Object?>{'confirmation': 'DELETE'});
      final data = result.data;
      final status = data is Map ? data['status'] : null;
      return status != 'already_requested';
    } on FirebaseFunctionsException catch (error) {
      throw AccountDeletionException(
        code: error.code,
        userMessage: _userMessageFor(error),
      );
    }
  }

  String _userMessageFor(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Please sign in again before deleting your account.';
      case 'permission-denied':
        return 'This account cannot be deleted right now. Please contact support.';
      case 'invalid-argument':
        return 'We could not confirm the request. Please try again.';
      default:
        return 'We could not delete your account. Please try again.';
    }
  }
}
