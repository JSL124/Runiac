import 'dart:async';

import 'package:flutter/widgets.dart';

import '../domain/models/user_account_read_model.dart';
import '../domain/repositories/user_account_repository.dart';

/// App-level store for the signed-in runner's trusted `users/{uid}` account
/// state.
///
/// One long-lived listener is held here and shared by every surface that needs
/// the trusted tier, instead of each screen opening its own. When the
/// repository supports [LiveUserAccountRepository], an admin-side
/// subscription change is pushed straight into the UI with no restart and no
/// re-login — Firestore Rules already re-evaluate `users/{uid}` on every
/// request, so the server-side privilege has already changed by then.
///
/// This store only relays trusted values. It never computes or grants
/// subscription privilege.
class CurrentSessionUserAccount extends ChangeNotifier {
  CurrentSessionUserAccount({
    this._ownerUid,
    this._repository = const StaticUserAccountRepository(),
  }) {
    _start();
  }

  final UserAccountRepository _repository;
  String? _ownerUid;
  UserAccountReadModel? _account;
  StreamSubscription<UserAccountReadModel>? _subscription;
  var _loadSerial = 0;
  var _disposed = false;

  String? get ownerUid => _ownerUid;

  /// Trusted account state, or `null` until the first read resolves.
  ///
  /// Signed out (or with a non-live repository) this settles on the safe
  /// non-privileged tier through a one-shot read. Signed in with a live
  /// repository it tracks `users/{uid}` continuously, so it stays `null` only
  /// for the brief moment before the first snapshot arrives — a premium runner
  /// never flashes as Basic on the way there.
  UserAccountReadModel? get account => _account;

  /// Backend-provided tier label, or an empty string while unresolved so
  /// callers hide the badge rather than guess a tier.
  String get subscriptionStatusLabel => _account?.subscriptionStatusLabel ?? '';

  /// Rebinds the listener when the signed-in user changes.
  void updateOwnerUid(String? ownerUid) {
    if (_ownerUid == ownerUid) {
      return;
    }
    _ownerUid = ownerUid;
    _cancelSubscription();
    _loadSerial += 1;
    _publish(null);
    _start();
  }

  void _start() {
    // A live repository decides for itself how to behave without a signed-in
    // user (it degrades to a one-shot read), so no owner check is needed here.
    final repository = _repository;
    if (repository is LiveUserAccountRepository) {
      _subscription = repository.watchUserAccount().listen(
        _publish,
        onError: _reportError,
      );
      return;
    }
    unawaited(_loadOnce());
  }

  Future<void> _loadOnce() async {
    final serial = ++_loadSerial;
    try {
      final account = await _repository.loadUserAccount();
      if (serial != _loadSerial) {
        return;
      }
      _publish(account);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
  }

  void _publish(UserAccountReadModel? account) {
    if (_disposed || _account == account) {
      return;
    }
    _account = account;
    notifyListeners();
  }

  void _reportError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'runiac current session user account',
        context: ErrorDescription(
          'watching trusted account subscription state',
        ),
      ),
    );
  }

  void _cancelSubscription() {
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscription();
    super.dispose();
  }
}

class CurrentSessionUserAccountScope
    extends InheritedNotifier<CurrentSessionUserAccount> {
  const CurrentSessionUserAccountScope({
    required CurrentSessionUserAccount store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static CurrentSessionUserAccount? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CurrentSessionUserAccountScope>()
        ?.notifier;
  }

  static CurrentSessionUserAccount? maybeRead(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<CurrentSessionUserAccountScope>()
        ?.notifier;
  }

  static CurrentSessionUserAccount of(BuildContext context) {
    final store = maybeOf(context);
    assert(store != null, 'No CurrentSessionUserAccountScope found.');
    return store!;
  }
}
