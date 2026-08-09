import 'dart:async';

import 'package:flutter/widgets.dart';

import '../domain/models/paywall_config_read_model.dart';
import '../domain/repositories/paywall_config_repository.dart';

/// App-level store for the admin-published paywall copy (`config/paywall`).
///
/// [config] is never null: it starts as the built-in defaults so the sheet
/// renders instantly, and swaps in the merged Firestore document once
/// [ensureLoaded] resolves. The read is one-shot and session-cached — pricing
/// copy changes are rare, so no live listener is held.
///
/// This store only relays display copy. It never computes or grants
/// subscription privilege.
class CurrentSessionPaywallConfig extends ChangeNotifier {
  CurrentSessionPaywallConfig({
    this._repository = const StaticPaywallConfigRepository(),
  });

  final PaywallConfigRepository _repository;
  PaywallConfigReadModel _config = PaywallConfigReadModel.defaults;
  Future<void>? _load;
  var _disposed = false;
  var _hasResolved = false;

  /// Current paywall copy — defaults until the one-shot read resolves.
  PaywallConfigReadModel get config => _config;

  /// Whether [config] is the real admin-published document rather than the
  /// pre-load defaults. Callers that act destructively on the `enabled` kill
  /// switch must wait for this, since the defaults say "paywall on" and would
  /// otherwise override an administrator who had turned it off.
  bool get hasResolved => _hasResolved;

  /// Kicks off the one-shot `config/paywall` read. Idempotent: repeated calls
  /// share the first in-flight load. Errors keep the defaults in place.
  Future<void> ensureLoaded() {
    return _load ??= _loadOnce();
  }

  Future<void> _loadOnce() async {
    try {
      final loaded = await _repository.loadPaywallConfig();
      if (_disposed) {
        return;
      }
      // Resolved even when the document happens to equal the defaults: the
      // point is that the read completed, not that the value changed.
      final wasUnresolved = !_hasResolved;
      _hasResolved = true;
      if (loaded == _config && !wasUnresolved) {
        return;
      }
      _config = loaded;
      notifyListeners();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac current session paywall config',
          context: ErrorDescription('loading paywall display config'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class PaywallConfigScope
    extends InheritedNotifier<CurrentSessionPaywallConfig> {
  const PaywallConfigScope({
    required CurrentSessionPaywallConfig store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static CurrentSessionPaywallConfig? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PaywallConfigScope>()
        ?.notifier;
  }

  static CurrentSessionPaywallConfig? maybeRead(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<PaywallConfigScope>()
        ?.notifier;
  }

  static CurrentSessionPaywallConfig of(BuildContext context) {
    final store = maybeOf(context);
    assert(store != null, 'No PaywallConfigScope found.');
    return store!;
  }
}
