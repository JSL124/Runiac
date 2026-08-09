import 'dart:async';

import 'package:flutter/widgets.dart';

import '../domain/models/feature_access_read_model.dart';
import '../domain/repositories/feature_access_repository.dart';

/// App-level store for the admin-published premium feature checklist
/// (`config/featureAccess`).
///
/// [featureAccess] is never null: it starts as the built-in defaults so the
/// upsell renders instantly, and swaps in the merged Firestore document once
/// [ensureLoaded] resolves. One-shot and session-cached — feature tiers
/// change rarely, so no live listener is held.
///
/// The document is readable only by a signed-in runner, so [ensureLoaded]
/// must be kicked once auth resolves ([RuniacApp] does this from the auth
/// gate) and [reset] on sign-out so the next account reads it again. A failed
/// read is NOT cached: it clears the in-flight future so a later gate check
/// retries instead of holding the defaults for the whole session.
///
/// This store relays admin policy; it never decides feature access on its own.
/// It drives upsell copy plus the client-side paywall interception, and every
/// feature with a server surface is re-checked against the same document
/// inside Cloud Functions, which is the real enforcement.
class CurrentSessionFeatureAccess extends ChangeNotifier {
  CurrentSessionFeatureAccess({
    this._repository = const StaticFeatureAccessRepository(),
  });

  final FeatureAccessRepository _repository;
  FeatureAccessReadModel _featureAccess = FeatureAccessReadModel.defaults;
  Future<void>? _load;
  var _disposed = false;

  /// Current premium feature checklist — defaults until the read resolves.
  FeatureAccessReadModel get featureAccess => _featureAccess;

  /// Kicks off the one-shot `config/featureAccess` read. Idempotent:
  /// repeated calls share the first in-flight load. Errors keep the
  /// defaults in place and release the cached future so the next call
  /// retries — a read that raced sign-in (the document is signed-in-only)
  /// must not pin the defaults for the rest of the session.
  Future<void> ensureLoaded() {
    return _load ??= _loadOnce();
  }

  /// Drops the loaded document on sign-out so the next account reads the
  /// policy again instead of inheriting the previous session's copy.
  void reset() {
    _load = null;
    if (_featureAccess == FeatureAccessReadModel.defaults) {
      return;
    }
    _featureAccess = FeatureAccessReadModel.defaults;
    notifyListeners();
  }

  Future<void> _loadOnce() async {
    try {
      final loaded = await _repository.loadFeatureAccess();
      if (_disposed || loaded == _featureAccess) {
        return;
      }
      _featureAccess = loaded;
      notifyListeners();
    } catch (error, stackTrace) {
      _load = null;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac current session feature access',
          context: ErrorDescription('loading premium feature checklist'),
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

class FeatureAccessScope
    extends InheritedNotifier<CurrentSessionFeatureAccess> {
  const FeatureAccessScope({
    required CurrentSessionFeatureAccess store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static CurrentSessionFeatureAccess? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FeatureAccessScope>()
        ?.notifier;
  }

  static CurrentSessionFeatureAccess? maybeRead(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<FeatureAccessScope>()
        ?.notifier;
  }
}
