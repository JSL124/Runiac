import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/you/data/local_user_progress_cache_store.dart';
import 'package:runiac_app/features/you/domain/models/user_progress_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/user_progress_repository.dart';
import 'package:runiac_app/features/you/presentation/current_session_user_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_runiac_auth_repository.dart';

void main() {
  const ownerA = 'owner-a';
  const ownerB = 'owner-b';
  final sameDay = DateTime.utc(2026, 7, 13, 9);

  testWidgets(
    'RuniacApp renders cached You progress before held remote refresh completes',
    (tester) async {
      const uid = 'test-auth-user-1';
      final cachedProgress = _progress(uid, levelLabel: 'Level 4');
      final cacheEntry = _cacheEntry(uid, sameDay, cachedProgress);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'runiac.userProgressCache.v1.$uid': cacheEntry.encode(),
      });
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn(uid: uid);
      final repository = _QueuedUserProgressRepository();
      addTearDown(authRepository.dispose);

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showAuth: false,
          authRepository: authRepository,
          userProgressRepository: repository,
          youProgressToday: sameDay,
        ),
      );
      await repository.waitForLoadCount(1);
      await tester.tap(find.byTooltip('You'));
      await tester.pump();

      expect(find.text('backend streak'), findsOneWidget);
      expect(repository.loadCount, 1);

      repository.completeLoad(0, _progress(uid, levelLabel: 'Level 5'));
      await tester.pumpAndSettle();

      expect(find.text('backend streak'), findsOneWidget);
      expect(repository.loadCount, 1);
    },
  );

  test(
    'Given same-UID same-day cache When refresh is held Then cached progress is emitted first',
    () async {
      // Given: a same-owner, same-day cache and a backend refresh that has not
      // completed yet.
      final repository = _QueuedUserProgressRepository();
      final cacheStore = _MemoryUserProgressCacheStore(
        _cacheEntry(ownerA, sameDay, _progress(ownerA, levelLabel: 'Level 4')),
      );
      final progress = CurrentSessionUserProgress(
        ownerUid: ownerA,
        repository: repository,
        cacheStore: cacheStore,
        clock: () => sameDay,
      );
      addTearDown(progress.dispose);

      final emissions = _record(progress);

      // When: the app-level coordinator loads progress for the current owner.
      final load = progress.load();
      await repository.waitForLoadCount(1);

      // Then: the cached backend-produced read model is visible before the
      // held authoritative refresh resolves; no zero/default model is emitted.
      expect(emissions.progressLabels, ['Level 4']);
      expect(emissions.statuses.last, CurrentSessionUserProgressStatus.loading);

      repository.completeLoad(0, _progress(ownerA, levelLabel: 'Level 6'));
      await load;
      expect(emissions.progressLabels, ['Level 4', 'Level 6']);
    },
  );

  test(
    'Given multiple consumers When progress is requested Then one remote refresh is coalesced',
    () async {
      // Given: no usable cache and two consumers entering Home and You during
      // the same session tick.
      final repository = _QueuedUserProgressRepository();
      final progress = CurrentSessionUserProgress(
        ownerUid: ownerA,
        repository: repository,
        cacheStore: _MemoryUserProgressCacheStore(null),
        clock: () => sameDay,
      );
      addTearDown(progress.dispose);

      // When: both consumers request the current progress.
      final firstLoad = progress.load();
      final secondLoad = progress.load();
      await repository.waitForLoadCount(1);

      // Then: both requests share one authoritative backend refresh.
      expect(repository.loadCount, 1);
      repository.completeLoad(0, _progress(ownerA, levelLabel: 'Level 5'));
      await Future.wait(<Future<void>>[firstLoad, secondLoad]);
      expect(progress.snapshot.progress?.levelLabel, 'Level 5');
    },
  );

  test(
    'Given last-good progress When refresh fails Then last-good is retained',
    () async {
      // Given: a previously loaded backend-produced progress model.
      final repository = _QueuedUserProgressRepository();
      final progress = CurrentSessionUserProgress(
        ownerUid: ownerA,
        repository: repository,
        cacheStore: _MemoryUserProgressCacheStore(null),
        clock: () => sameDay,
      );
      addTearDown(progress.dispose);

      final initialLoad = progress.load();
      await repository.waitForLoadCount(1);
      repository.completeLoad(0, _progress(ownerA, levelLabel: 'Level 7'));
      await initialLoad;

      // When: a later refresh fails.
      final refresh = progress.refresh();
      await repository.waitForLoadCount(2);
      repository.failLoad(1, StateError('backend unavailable'));
      await refresh;

      // Then: the last-good model remains visible and the failure is retryable.
      expect(progress.snapshot.progress?.levelLabel, 'Level 7');
      expect(
        progress.snapshot.status,
        CurrentSessionUserProgressStatus.failure,
      );
      expect(progress.snapshot.canRetry, isTrue);
    },
  );

  test(
    'Given no cache When initial refresh fails Then failure and retry are exposed',
    () async {
      // Given: a first-time owner with no cache.
      final repository = _QueuedUserProgressRepository();
      final progress = CurrentSessionUserProgress(
        ownerUid: ownerA,
        repository: repository,
        cacheStore: _MemoryUserProgressCacheStore(null),
        clock: () => sameDay,
      );
      addTearDown(progress.dispose);

      // When: the initial authoritative load fails.
      final load = progress.load();
      await repository.waitForLoadCount(1);
      repository.failLoad(0, StateError('initial backend unavailable'));
      await load;

      // Then: no fake zero/default progress is exposed as loaded data.
      expect(progress.snapshot.progress, isNull);
      expect(
        progress.snapshot.status,
        CurrentSessionUserProgressStatus.failure,
      );
      expect(progress.snapshot.canRetry, isTrue);
    },
  );

  test(
    'Given owner changes When late owner A cache and remote finish Then owner B is not updated by A',
    () async {
      // Given: owner A has a held refresh, and owner B signs in before it
      // completes.
      final repository = _QueuedUserProgressRepository();
      final cacheStore = _MemoryUserProgressCacheStore(
        _cacheEntry(ownerA, sameDay, _progress(ownerA, levelLabel: 'Level 9')),
      );
      final progress = CurrentSessionUserProgress(
        ownerUid: ownerA,
        repository: repository,
        cacheStore: cacheStore,
        clock: () => sameDay,
      );
      addTearDown(progress.dispose);

      final ownerALoad = progress.load();
      await repository.waitForLoadCount(1);

      // When: owner B becomes current before owner A's refresh resolves.
      progress.updateOwnerUid(ownerB);

      // Then: owner A state is cleared synchronously.
      expect(progress.snapshot.ownerUid, ownerB);
      expect(progress.snapshot.progress, isNull);

      final ownerBLoad = progress.load();
      await repository.waitForLoadCount(2);
      repository.completeLoad(0, _progress(ownerA, levelLabel: 'Level 10'));
      repository.completeLoad(1, _progress(ownerB, levelLabel: 'Level 2'));
      await Future.wait(<Future<void>>[ownerALoad, ownerBLoad]);

      expect(progress.snapshot.ownerUid, ownerB);
      expect(progress.snapshot.progress?.userId, ownerB);
      expect(progress.snapshot.progress?.levelLabel, 'Level 2');
    },
  );

  test(
    'Given wrong stale and corrupt caches When loading Then each cache is rejected',
    () async {
      // Given: three cache entries that must never render as current user data.
      final cases = <_RejectedCacheCase>[
        _RejectedCacheCase(
          'wrong owner',
          _cacheEntry(
            ownerB,
            sameDay,
            _progress(ownerB, levelLabel: 'Level 8'),
          ),
        ),
        _RejectedCacheCase(
          'stale day',
          _cacheEntry(
            ownerA,
            DateTime.utc(2026, 7, 12, 23, 59),
            _progress(ownerA, levelLabel: 'Level 8'),
          ),
        ),
        _RejectedCacheCase.corrupt('corrupt cache'),
      ];

      for (final currentCase in cases) {
        final repository = _QueuedUserProgressRepository();
        final progress = CurrentSessionUserProgress(
          ownerUid: ownerA,
          repository: repository,
          cacheStore: currentCase.cacheStore,
          clock: () => sameDay,
        );
        addTearDown(progress.dispose);
        final emissions = _record(progress);

        // When: progress is loaded while the remote read is held.
        final load = progress.load();
        await repository.waitForLoadCount(1);

        // Then: the rejected cache never renders before the authoritative
        // backend-produced model arrives.
        expect(
          emissions.progressLabels,
          isEmpty,
          reason: '${currentCase.name} cache must not render',
        );

        repository.completeLoad(0, _progress(ownerA, levelLabel: 'Level 3'));
        await load;
        expect(progress.snapshot.progress?.levelLabel, 'Level 3');
      }
    },
  );
}

UserProgressReadModel _progress(String uid, {required String levelLabel}) {
  return UserProgressReadModel(
    userId: uid,
    officialStreakLabel: 'backend streak',
    level: int.tryParse(levelLabel.replaceFirst('Level ', '')) ?? 0,
    levelLabel: levelLabel,
    totalXpLabel: 'backend XP',
    weeklyXpLabel: 'backend weekly XP',
    monthlyXpLabel: 'backend monthly XP',
    weeklyDistanceLabel: 'backend distance',
    goalProgressLabel: 'backend goal',
  );
}

LocalUserProgressCacheEntry _cacheEntry(
  String uid,
  DateTime refreshedAt,
  UserProgressReadModel progress,
) {
  return LocalUserProgressCacheEntry(
    uid: uid,
    refreshedAt: refreshedAt,
    progress: progress,
  );
}

_ProgressEmissionRecorder _record(CurrentSessionUserProgress progress) {
  final recorder = _ProgressEmissionRecorder();
  progress.addListener(() {
    recorder.snapshots.add(progress.snapshot);
  });
  return recorder;
}

class _ProgressEmissionRecorder {
  final List<CurrentSessionUserProgressSnapshot> snapshots =
      <CurrentSessionUserProgressSnapshot>[];

  List<String> get progressLabels {
    return snapshots
        .map((snapshot) => snapshot.progress?.levelLabel)
        .whereType<String>()
        .toList(growable: false);
  }

  List<CurrentSessionUserProgressStatus> get statuses {
    return snapshots.map((snapshot) => snapshot.status).toList(growable: false);
  }
}

class _RejectedCacheCase {
  _RejectedCacheCase(String name, LocalUserProgressCacheEntry? entry)
    : this._(name, _MemoryUserProgressCacheStore(entry));

  _RejectedCacheCase.corrupt(String name)
    : this._(name, _MemoryUserProgressCacheStore.corrupt());

  _RejectedCacheCase._(this.name, this.cacheStore);

  final String name;
  final LocalUserProgressCacheStore cacheStore;
}

class _MemoryUserProgressCacheStore implements LocalUserProgressCacheStore {
  _MemoryUserProgressCacheStore(this.entry) : _throwsOnLoad = false;

  _MemoryUserProgressCacheStore.corrupt() : entry = null, _throwsOnLoad = true;

  LocalUserProgressCacheEntry? entry;
  final bool _throwsOnLoad;

  @override
  Future<LocalUserProgressCacheEntry?> load({required String uid}) async {
    if (_throwsOnLoad) {
      throw const FormatException('Corrupt user progress cache.');
    }
    return entry;
  }

  @override
  Future<void> save(LocalUserProgressCacheEntry entry) async {
    this.entry = entry;
  }
}

class _QueuedUserProgressRepository implements UserProgressRepository {
  final List<Completer<UserProgressReadModel>> _loads =
      <Completer<UserProgressReadModel>>[];
  final List<Completer<void>> _loadCountWaiters = <Completer<void>>[];
  final Map<Completer<void>, int> _loadCountTargets = <Completer<void>, int>{};

  int get loadCount => _loads.length;

  @override
  Future<UserProgressReadModel> loadUserProgress() {
    return _queueLoad();
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() {
    return _queueLoad();
  }

  Future<void> waitForLoadCount(int count) {
    if (_loads.length >= count) {
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _loadCountTargets[waiter] = count;
    _loadCountWaiters.add(waiter);
    return waiter.future;
  }

  void completeLoad(int index, UserProgressReadModel progress) {
    _loads[index].complete(progress);
  }

  void failLoad(int index, Object error) {
    _loads[index].completeError(error, StackTrace.current);
  }

  Future<UserProgressReadModel> _queueLoad() {
    final load = Completer<UserProgressReadModel>();
    _loads.add(load);
    for (final waiter in _loadCountWaiters.toList(growable: false)) {
      final target = _loadCountTargets[waiter];
      if (target != null && !waiter.isCompleted && _loads.length >= target) {
        waiter.complete();
      }
    }
    return load.future;
  }
}
