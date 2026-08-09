import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/local_user_progress_cache_store.dart';
import '../domain/models/user_progress_read_model.dart';
import '../domain/repositories/user_progress_repository.dart';

/// Holds the signed-in runner's progression state for the lifetime of the
/// session, and exposes it to the widget tree through
/// [CurrentSessionUserProgressScope].
///
/// Level, XP and streak are shown on several surfaces at once (You tab, Home,
/// share cards). Fetching per surface would both waste reads and let them
/// disagree mid-frame, so they all read this one store.
///
/// [CurrentSessionUserProgressStatus.failure] is a state the UI is expected to
/// render, not an error to swallow — progress that failed to load must look
/// different from progress that is genuinely zero.
enum CurrentSessionUserProgressStatus { idle, loading, loaded, failure }

class CurrentSessionUserProgressSnapshot {
  const CurrentSessionUserProgressSnapshot({
    required this.ownerUid,
    required this.status,
    required this.canRetry,
    this.progress,
    this.error,
  });

  final String? ownerUid;
  final CurrentSessionUserProgressStatus status;
  final bool canRetry;
  final UserProgressReadModel? progress;
  final Object? error;
}

class CurrentSessionUserProgress extends ChangeNotifier {
  CurrentSessionUserProgress({
    required this._ownerUid,
    required this._repository,
    required this._cacheStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final UserProgressRepository _repository;
  final LocalUserProgressCacheStore _cacheStore;
  final DateTime Function() _clock;
  String? _ownerUid;
  CurrentSessionUserProgressStatus _status =
      CurrentSessionUserProgressStatus.idle;
  UserProgressReadModel? _progress;
  Object? _error;
  Future<UserProgressReadModel?>? _inFlightLoad;
  var _generation = 0;
  var _disposed = false;

  CurrentSessionUserProgressSnapshot get snapshot {
    return CurrentSessionUserProgressSnapshot(
      ownerUid: _ownerUid,
      status: _status,
      progress: _progress,
      error: _error,
      canRetry: _status == CurrentSessionUserProgressStatus.failure,
    );
  }

  Future<UserProgressReadModel?> load() {
    final inFlight = _inFlightLoad;
    if (inFlight != null) {
      return inFlight;
    }
    final nextLoad = _loadRemoteWithCacheFirst();
    _inFlightLoad = nextLoad;
    nextLoad.whenComplete(() {
      if (identical(_inFlightLoad, nextLoad)) {
        _inFlightLoad = null;
      }
    });
    return nextLoad;
  }

  Future<UserProgressReadModel?> refresh() {
    final inFlight = _inFlightLoad;
    if (inFlight != null) {
      return inFlight;
    }
    final nextLoad = _loadRemoteWithCacheFirst(skipCache: true);
    _inFlightLoad = nextLoad;
    nextLoad.whenComplete(() {
      if (identical(_inFlightLoad, nextLoad)) {
        _inFlightLoad = null;
      }
    });
    return nextLoad;
  }

  void updateOwnerUid(String? ownerUid) {
    if (_ownerUid == ownerUid) {
      return;
    }
    _ownerUid = ownerUid;
    _generation += 1;
    _progress = null;
    _error = null;
    _status = CurrentSessionUserProgressStatus.idle;
    _inFlightLoad = null;
    _notifyIfActive();
  }

  void recordRemoteProgress(UserProgressReadModel progress) {
    final ownerUid = _ownerUid;
    if (ownerUid == null || progress.userId != ownerUid) {
      return;
    }
    final generation = _generation;
    _progress = progress;
    _status = CurrentSessionUserProgressStatus.loaded;
    _error = null;
    _notifyIfActive();
    unawaited(_saveRemoteCache(progress, generation, ownerUid));
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }

  Future<UserProgressReadModel?> _loadRemoteWithCacheFirst({
    bool skipCache = false,
  }) async {
    final ownerUid = _ownerUid;
    final generation = _generation;
    _error = null;
    _status = CurrentSessionUserProgressStatus.loading;
    _notifyIfActive();

    if (ownerUid == null || ownerUid.isEmpty) {
      _progress = null;
      _status = CurrentSessionUserProgressStatus.failure;
      _error = StateError('Cannot load user progress without an owner UID.');
      _notifyIfCurrent(generation, ownerUid);
      return null;
    }

    if (!skipCache) {
      final cached = await _loadUsableCache(ownerUid);
      if (!_isCurrent(generation, ownerUid)) {
        return null;
      }
      if (cached != null) {
        _progress = cached.progress;
        _status = CurrentSessionUserProgressStatus.loading;
        _notifyIfActive();
      }
    }

    try {
      final remote = await _repository.refreshUserProgress();
      if (!_isCurrent(generation, ownerUid)) {
        return null;
      }
      if (remote.userId != ownerUid) {
        _error = StateError('Received progress for a different owner UID.');
        _status = CurrentSessionUserProgressStatus.failure;
        _notifyIfActive();
        return null;
      }
      _progress = remote;
      _status = CurrentSessionUserProgressStatus.loaded;
      _error = null;
      _notifyIfActive();
      unawaited(_saveRemoteCache(remote, generation, ownerUid));
      return remote;
    } catch (error) {
      if (!_isCurrent(generation, ownerUid)) {
        return null;
      }
      _error = error;
      _status = CurrentSessionUserProgressStatus.failure;
      _notifyIfActive();
      return null;
    }
  }

  Future<LocalUserProgressCacheEntry?> _loadUsableCache(String ownerUid) async {
    try {
      final cached = await _cacheStore.load(uid: ownerUid);
      if (cached == null ||
          cached.uid != ownerUid ||
          cached.progress.userId != ownerUid ||
          !_isSameDay(cached.refreshedAt, _clock())) {
        return null;
      }
      return cached;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveRemoteCache(
    UserProgressReadModel remote,
    int generation,
    String ownerUid,
  ) async {
    if (!_isCurrent(generation, ownerUid)) {
      return;
    }
    try {
      await _cacheStore.save(
        LocalUserProgressCacheEntry(
          uid: ownerUid,
          refreshedAt: _clock(),
          progress: remote,
        ),
      );
    } catch (_) {
      return;
    }
  }

  bool _isCurrent(int generation, String? ownerUid) {
    return !_disposed && generation == _generation && ownerUid == _ownerUid;
  }

  void _notifyIfCurrent(int generation, String? ownerUid) {
    if (_isCurrent(generation, ownerUid)) {
      _notifyIfActive();
    }
  }

  void _notifyIfActive() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class CurrentSessionUserProgressScope
    extends InheritedNotifier<CurrentSessionUserProgress> {
  const CurrentSessionUserProgressScope({
    required CurrentSessionUserProgress store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static CurrentSessionUserProgress? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CurrentSessionUserProgressScope>()
        ?.notifier;
  }

  static CurrentSessionUserProgress? maybeRead(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<CurrentSessionUserProgressScope>()
        ?.notifier;
  }

  static CurrentSessionUserProgress of(BuildContext context) {
    final store = maybeOf(context);
    assert(store != null, 'No CurrentSessionUserProgressScope found.');
    return store!;
  }
}
