import 'package:flutter/widgets.dart';

import '../domain/models/character_access_read_model.dart';
import '../domain/repositories/character_access_repository.dart';

/// App-level store for the admin-published premium-character list
/// (`config/characterAccess`).
///
/// [characterAccess] is never null: it starts as the built-in defaults so the
/// picker renders instantly, and swaps in the Firestore document once
/// [ensureLoaded] resolves. One-shot and session-cached — character tiers
/// change rarely, so no live listener is held.
///
/// This store only relays display data. The character is cosmetic, device-local
/// personalization, so the lock it drives is presentation only; it never writes
/// XP, level, rank, streak, or leaderboard values.
class CurrentSessionCharacterAccess extends ChangeNotifier {
  CurrentSessionCharacterAccess({
    this._repository = const StaticCharacterAccessRepository(),
  });

  final CharacterAccessRepository _repository;
  CharacterAccessReadModel _characterAccess = CharacterAccessReadModel.defaults;
  Future<void>? _load;
  var _disposed = false;
  var _hasResolved = false;

  /// Current premium-character list — defaults until the read resolves.
  CharacterAccessReadModel get characterAccess => _characterAccess;

  /// Whether [characterAccess] is the real admin-published document rather
  /// than the pre-load defaults.
  ///
  /// The picker does not need this — locking a buddy on the defaults for a
  /// moment is harmless and reverts itself. A caller that *acts* on the list
  /// destructively (dropping a stored selection) does, because acting on a
  /// guess would strip a buddy the administrator had actually opened to
  /// everyone. Stays false when the read fails, so those callers do nothing.
  bool get hasResolved => _hasResolved;

  /// Kicks off the one-shot `config/characterAccess` read. Idempotent:
  /// repeated calls share the first in-flight load. Errors keep the defaults
  /// in place.
  Future<void> ensureLoaded() {
    return _load ??= _loadOnce();
  }

  Future<void> _loadOnce() async {
    try {
      final loaded = await _repository.loadCharacterAccess();
      if (_disposed) {
        return;
      }
      // Resolved even when the document happens to equal the defaults: the
      // point is that the read completed, not that the value changed.
      final wasUnresolved = !_hasResolved;
      _hasResolved = true;
      if (loaded == _characterAccess && !wasUnresolved) {
        return;
      }
      _characterAccess = loaded;
      notifyListeners();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac current session character access',
          context: ErrorDescription('loading premium character list'),
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

class CharacterAccessScope
    extends InheritedNotifier<CurrentSessionCharacterAccess> {
  const CharacterAccessScope({
    required CurrentSessionCharacterAccess store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static CurrentSessionCharacterAccess? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CharacterAccessScope>()
        ?.notifier;
  }

  static CurrentSessionCharacterAccess? maybeRead(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<CharacterAccessScope>()
        ?.notifier;
  }
}
