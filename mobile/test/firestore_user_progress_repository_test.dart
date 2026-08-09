import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runiac_app/features/you/data/firestore_user_progress_repository.dart';
import 'package:runiac_app/features/you/data/local_user_progress_cache_store.dart';
import 'package:runiac_app/features/you/data/user_streak_refresh_service.dart';
import 'package:runiac_app/features/you/domain/models/user_progress_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/user_progress_repository.dart';

import 'support/fake_runiac_auth_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'maps backend-owned streak count into singular official label',
    () async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final repository = FirestoreUserProgressRepository(
        authRepository: authRepository,
        reader: const _FakeUserProgressDocumentReader({'streakCount': 1}),
      );

      final progress = await repository.loadUserProgress();

      expect(progress.officialStreakLabel, '1 day');
    },
  );

  test('maps backend-owned streak count into plural official label', () async {
    final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
    final repository = FirestoreUserProgressRepository(
      authRepository: authRepository,
      reader: const _FakeUserProgressDocumentReader({'streakCount': 17}),
    );

    final progress = await repository.loadUserProgress();

    expect(progress.officialStreakLabel, '17 days');
  });

  test('maps backend-owned lifetime stat labels into the read model', () async {
    final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
    final repository = FirestoreUserProgressRepository(
      authRepository: authRepository,
      reader: const _FakeUserProgressDocumentReader({
        'streakCount': 3,
        'longestStreakLabel': '14 days',
        'totalDistanceLabel': '148.6 km',
      }),
    );

    final progress = await repository.loadUserProgress();

    expect(progress.longestStreakLabel, '14 days');
    expect(progress.totalDistanceLabel, '148.6 km');
  });

  test(
    'defaults lifetime stat labels to empty when the backend omits them',
    () async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final repository = FirestoreUserProgressRepository(
        authRepository: authRepository,
        reader: const _FakeUserProgressDocumentReader({'streakCount': 0}),
      );

      final progress = await repository.loadUserProgress();

      expect(progress.longestStreakLabel, isEmpty);
      expect(progress.totalDistanceLabel, isEmpty);
    },
  );

  test(
    'refreshes backend-owned streak before reading official progress',
    () async {
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'streak-refresh-user');
      final refreshService = _RecordingUserStreakRefreshService();
      final reader = _RefreshOrderedUserProgressDocumentReader(refreshService);
      final repository = FirestoreUserProgressRepository(
        authRepository: authRepository,
        reader: reader,
        streakRefreshService: refreshService,
      );

      final progress = await repository.loadUserProgress();

      expect(refreshService.refreshCount, 1);
      expect(reader.readAfterRefresh, isTrue);
      expect(progress.officialStreakLabel, '0 days');
      expect(progress.officialStreakCount, 0);
    },
  );

  test('uses fallback progress when no user is signed in', () async {
    final repository = FirestoreUserProgressRepository(
      authRepository: FakeRuniacAuthRepository(),
      reader: const _FakeUserProgressDocumentReader({'streakCount': 17}),
      fallbackRepository: const _FallbackUserProgressRepository(),
    );

    final progress = await repository.loadUserProgress();

    expect(progress.officialStreakLabel, 'fallback');
  });

  test(
    'loadUserProgress refreshes same-day cache from backend-owned document',
    () async {
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'cache-user-1');
      final reader = _CountingUserProgressDocumentReader({
        'streakCount': 3,
        'level': 6,
        'levelProgressPercent': 42,
        'levelLabel': 'Level 3',
      });
      final cacheStore = _MemoryUserProgressCacheStore(
        LocalUserProgressCacheEntry(
          uid: 'cache-user-1',
          refreshedAt: DateTime.utc(2026, 7, 6, 8),
          progress: const UserProgressReadModel(
            userId: 'cache-user-1',
            officialStreakLabel: '1 day',
            levelLabel: 'Level 1',
            totalXpLabel: '300 XP',
            weeklyXpLabel: '90 XP',
            monthlyXpLabel: '210 XP',
            weeklyDistanceLabel: '8.0 km',
            goalProgressLabel: '30%',
          ),
        ),
      );
      final repository = FirestoreUserProgressRepository(
        authRepository: authRepository,
        reader: reader,
        cacheStore: cacheStore,
        clock: () => DateTime.utc(2026, 7, 6, 22),
      );

      final progress = await repository.loadUserProgress();

      expect(progress.officialStreakLabel, '3 days');
      expect(progress.level, 6);
      expect(progress.levelBadgeLabel, 'Lv.6');
      expect(progress.levelProgressFraction, 0.42);
      expect(progress.levelLabel, 'Level 3');
      expect(reader.readCount, 1);
      expect(cacheStore.entry?.progress.officialStreakLabel, '3 days');
    },
  );

  test(
    'loadUserProgress maps backend-owned division values into progress model',
    () async {
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'division-user');
      final repository = FirestoreUserProgressRepository(
        authRepository: authRepository,
        reader: const _FakeUserProgressDocumentReader({
          'level': 1,
          'levelProgressPercent': 50,
          'divisionKey': 'tier_01',
          'divisionLabel': 'Iron League',
        }),
      );

      final progress = await repository.loadUserProgress();

      expect(progress.level, 1);
      expect(progress.levelProgressFraction, 0.5);
      expect(progress.divisionKey, 'tier_01');
      expect(progress.divisionLabel, 'Iron League');
    },
  );

  test('local user progress cache preserves backend-owned division values', () {
    final entry = LocalUserProgressCacheEntry(
      uid: 'division-cache-user',
      refreshedAt: DateTime.utc(2026, 7, 13, 8),
      progress: const UserProgressReadModel(
        userId: 'division-cache-user',
        officialStreakLabel: '',
        level: 100,
        levelProgressFraction: 1,
        divisionKey: 'tier_10',
        divisionLabel: 'Challenger League',
        levelLabel: 'Level 100',
        totalXpLabel: '100,000 XP',
        weeklyXpLabel: '',
        monthlyXpLabel: '100,000 XP',
        weeklyDistanceLabel: '',
        goalProgressLabel: '',
      ),
    );

    final decoded = LocalUserProgressCacheEntry.tryDecode(entry.encode());

    expect(decoded?.progress.level, 100);
    expect(decoded?.progress.divisionKey, 'tier_10');
    expect(decoded?.progress.divisionLabel, 'Challenger League');
  });

  test(
    'loadUserProgress falls back to same-day cache when backend read fails',
    () async {
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'cache-user-1');
      final cacheStore = _MemoryUserProgressCacheStore(
        LocalUserProgressCacheEntry(
          uid: 'cache-user-1',
          refreshedAt: DateTime.utc(2026, 7, 6, 8),
          progress: const UserProgressReadModel(
            userId: 'cache-user-1',
            officialStreakLabel: '2 days',
            levelLabel: 'Level 2',
            totalXpLabel: '200 XP',
            weeklyXpLabel: '70 XP',
            monthlyXpLabel: '160 XP',
            weeklyDistanceLabel: '6.0 km',
            goalProgressLabel: '20%',
          ),
        ),
      );
      final repository = FirestoreUserProgressRepository(
        authRepository: authRepository,
        reader: const _ThrowingUserProgressDocumentReader(),
        cacheStore: cacheStore,
        clock: () => DateTime.utc(2026, 7, 6, 22),
      );

      final progress = await repository.loadUserProgress();

      expect(progress.officialStreakLabel, '2 days');
    },
  );

  test(
    'loadUserProgress refreshes stale cache from reader and updates cache',
    () async {
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'cache-user-1');
      final reader = _CountingUserProgressDocumentReader({
        'streakCount': 4,
        'levelLabel': 'Level 4',
        'totalXpLabel': '400 XP',
        'weeklyXpLabel': '120 XP',
        'monthlyXpLabel': '260 XP',
        'weeklyDistanceLabel': '9.4 km',
        'goalProgressLabel': '40%',
      });
      final cacheStore = _MemoryUserProgressCacheStore(
        LocalUserProgressCacheEntry(
          uid: 'cache-user-1',
          refreshedAt: DateTime.utc(2026, 7, 5, 23, 59),
          progress: const UserProgressReadModel(
            userId: 'cache-user-1',
            officialStreakLabel: '2 days',
            levelLabel: 'Level 2',
            totalXpLabel: '200 XP',
            weeklyXpLabel: '70 XP',
            monthlyXpLabel: '160 XP',
            weeklyDistanceLabel: '6.0 km',
            goalProgressLabel: '20%',
          ),
        ),
      );
      final repository = FirestoreUserProgressRepository(
        authRepository: authRepository,
        reader: reader,
        cacheStore: cacheStore,
        clock: () => DateTime.utc(2026, 7, 6, 1),
      );

      final progress = await repository.loadUserProgress();

      expect(progress.officialStreakLabel, '4 days');
      expect(progress.levelLabel, 'Level 4');
      expect(reader.readCount, 1);
      expect(cacheStore.entry?.progress.officialStreakLabel, '4 days');
      expect(cacheStore.entry?.refreshedAt, DateTime.utc(2026, 7, 6, 1));
    },
  );

  test(
    'loadUserProgress still reads progress when streak refresh fails',
    () async {
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'refresh-fallback-user');
      final reader = _CountingUserProgressDocumentReader({
        'streakCount': 2,
        'levelLabel': 'Level 2',
      });
      final repository = FirestoreUserProgressRepository(
        authRepository: authRepository,
        reader: reader,
        cacheStore: _MemoryUserProgressCacheStore(null),
        streakRefreshService: const _ThrowingUserStreakRefreshService(),
      );

      final progress = await repository.loadUserProgress();

      expect(progress.officialStreakCount, 2);
      expect(reader.readCount, 1);
    },
  );

  test('loadUserProgress ignores wrong-user cache and corrupt cache', () async {
    final authRepository = FakeRuniacAuthRepository()
      ..emitSignedIn(uid: 'cache-user-1');
    final wrongUserReader = _CountingUserProgressDocumentReader({
      'streakCount': 5,
      'levelLabel': 'Level 5',
    });
    final wrongUserCacheStore = _MemoryUserProgressCacheStore(
      LocalUserProgressCacheEntry(
        uid: 'other-user',
        refreshedAt: DateTime.utc(2026, 7, 6, 8),
        progress: const UserProgressReadModel(
          userId: 'other-user',
          officialStreakLabel: '99 days',
          levelLabel: 'Level 99',
          totalXpLabel: '9,900 XP',
          weeklyXpLabel: '990 XP',
          monthlyXpLabel: '2,990 XP',
          weeklyDistanceLabel: '99.0 km',
          goalProgressLabel: '99%',
        ),
      ),
    );
    final wrongUserRepository = FirestoreUserProgressRepository(
      authRepository: authRepository,
      reader: wrongUserReader,
      cacheStore: wrongUserCacheStore,
      clock: () => DateTime.utc(2026, 7, 6, 9),
    );

    final wrongUserProgress = await wrongUserRepository.loadUserProgress();

    expect(wrongUserProgress.officialStreakLabel, '5 days');
    expect(wrongUserReader.readCount, 1);
    expect(wrongUserCacheStore.entry?.progress.officialStreakLabel, '5 days');

    final corruptReader = _CountingUserProgressDocumentReader({
      'streakCount': 6,
      'levelLabel': 'Level 6',
    });
    final corruptCacheStore = _MemoryUserProgressCacheStore.corrupt();
    final corruptRepository = FirestoreUserProgressRepository(
      authRepository: authRepository,
      reader: corruptReader,
      cacheStore: corruptCacheStore,
      clock: () => DateTime.utc(2026, 7, 6, 10),
    );

    final corruptProgress = await corruptRepository.loadUserProgress();

    expect(corruptProgress.officialStreakLabel, '6 days');
    expect(corruptReader.readCount, 1);
    expect(corruptCacheStore.entry?.progress.officialStreakLabel, '6 days');
  });

  test(
    'refreshUserProgress always reads Firestore and updates cache',
    () async {
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'cache-user-1');
      final reader = _CountingUserProgressDocumentReader({
        'streakCount': 8,
        'levelLabel': 'Level 8',
      });
      final cacheStore = _MemoryUserProgressCacheStore(
        LocalUserProgressCacheEntry(
          uid: 'cache-user-1',
          refreshedAt: DateTime.utc(2026, 7, 6, 8),
          progress: const UserProgressReadModel(
            userId: 'cache-user-1',
            officialStreakLabel: '3 days',
            levelLabel: 'Level 3',
            totalXpLabel: '',
            weeklyXpLabel: '',
            monthlyXpLabel: '',
            weeklyDistanceLabel: '',
            goalProgressLabel: '',
          ),
        ),
      );
      final repository = FirestoreUserProgressRepository(
        authRepository: authRepository,
        reader: reader,
        cacheStore: cacheStore,
        clock: () => DateTime.utc(2026, 7, 6, 11),
      );

      final progress = await repository.refreshUserProgress();

      expect(progress.officialStreakLabel, '8 days');
      expect(reader.readCount, 1);
      expect(cacheStore.entry?.progress.officialStreakLabel, '8 days');
    },
  );

  test('in-flight load does not overwrite newer refresh cache', () async {
    final authRepository = FakeRuniacAuthRepository()
      ..emitSignedIn(uid: 'cache-user-1');
    final reader = _QueuedUserProgressDocumentReader();
    final cacheStore = _MemoryUserProgressCacheStore(null);
    final repository = FirestoreUserProgressRepository(
      authRepository: authRepository,
      reader: reader,
      cacheStore: cacheStore,
      clock: () => DateTime.utc(2026, 7, 6, 13),
    );

    final staleLoad = repository.loadUserProgress();
    await reader.waitForReadCount(1);
    final freshRefresh = repository.refreshUserProgress();
    await reader.waitForReadCount(2);

    reader.completeRead(1, {'streakCount': 9, 'levelLabel': 'Level 9'});
    final refreshed = await freshRefresh;
    expect(refreshed.officialStreakLabel, '9 days');
    expect(cacheStore.entry?.progress.officialStreakLabel, '9 days');

    reader.completeRead(0, {'streakCount': 1, 'levelLabel': 'Level 1'});
    final stale = await staleLoad;
    expect(stale.officialStreakLabel, '1 day');
    expect(cacheStore.entry?.progress.officialStreakLabel, '9 days');
  });

  test(
    'shared preferences cache store round trips display-only progress',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = SharedPreferencesLocalUserProgressCacheStore(
        keyPrefix: 'test.userProgressCache.',
      );
      final entry = LocalUserProgressCacheEntry(
        uid: 'cache-user-1',
        refreshedAt: DateTime.utc(2026, 7, 6, 12),
        progress: const UserProgressReadModel(
          userId: 'cache-user-1',
          officialStreakLabel: '2 days',
          levelLabel: 'Level 2',
          totalXpLabel: '200 XP',
          weeklyXpLabel: '80 XP',
          monthlyXpLabel: '140 XP',
          weeklyDistanceLabel: '6.2 km',
          goalProgressLabel: '25%',
        ),
      );

      await store.save(entry);

      final restored = await store.load(uid: 'cache-user-1');
      final otherUser = await store.load(uid: 'cache-user-2');

      expect(restored?.uid, 'cache-user-1');
      expect(restored?.refreshedAt, DateTime.utc(2026, 7, 6, 12));
      expect(restored?.progress.officialStreakLabel, '2 days');
      expect(restored?.progress.totalXpLabel, '200 XP');
      expect(otherUser, isNull);
    },
  );

  test(
    'shared preferences corrupt cache is ignored after backend read succeeds',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'test.userProgressCache.cache-user-1': '{bad json',
      });
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'cache-user-1');
      final reader = _CountingUserProgressDocumentReader({'streakCount': 3});
      final reportedErrors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reportedErrors.add;
      addTearDown(() => FlutterError.onError = previousOnError);
      final repository = FirestoreUserProgressRepository(
        authRepository: authRepository,
        reader: reader,
        cacheStore: const SharedPreferencesLocalUserProgressCacheStore(
          keyPrefix: 'test.userProgressCache.',
        ),
        clock: () => DateTime.utc(2026, 7, 6, 14),
      );

      final progress = await repository.loadUserProgress();

      expect(progress.officialStreakLabel, '3 days');
      expect(reader.readCount, 1);
      expect(reportedErrors, isEmpty);
    },
  );
}

class _FakeUserProgressDocumentReader implements UserProgressDocumentReader {
  const _FakeUserProgressDocumentReader(this.document);

  final Map<String, Object?>? document;

  @override
  Future<Map<String, Object?>?> readUserProgress({required String uid}) async {
    return document;
  }
}

class _RecordingUserStreakRefreshService implements UserStreakRefreshService {
  int refreshCount = 0;

  @override
  Future<void> refreshStreakStatus() async {
    refreshCount += 1;
  }
}

class _ThrowingUserStreakRefreshService implements UserStreakRefreshService {
  const _ThrowingUserStreakRefreshService();

  @override
  Future<void> refreshStreakStatus() async {
    throw StateError('Streak refresh failed.');
  }
}

class _RefreshOrderedUserProgressDocumentReader
    implements UserProgressDocumentReader {
  _RefreshOrderedUserProgressDocumentReader(this.refreshService);

  final _RecordingUserStreakRefreshService refreshService;
  bool readAfterRefresh = false;

  @override
  Future<Map<String, Object?>?> readUserProgress({required String uid}) async {
    readAfterRefresh = refreshService.refreshCount == 1;
    return const {'streakCount': 0};
  }
}

class _CountingUserProgressDocumentReader
    implements UserProgressDocumentReader {
  _CountingUserProgressDocumentReader(this.document);

  final Map<String, Object?>? document;
  int readCount = 0;

  @override
  Future<Map<String, Object?>?> readUserProgress({required String uid}) async {
    readCount += 1;
    return document;
  }
}

class _ThrowingUserProgressDocumentReader
    implements UserProgressDocumentReader {
  const _ThrowingUserProgressDocumentReader();

  @override
  Future<Map<String, Object?>?> readUserProgress({required String uid}) async {
    throw StateError('Backend read failed.');
  }
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

class _QueuedUserProgressDocumentReader implements UserProgressDocumentReader {
  final List<Completer<Map<String, Object?>?>> _reads =
      <Completer<Map<String, Object?>?>>[];
  final List<Completer<void>> _readCountWaiters = <Completer<void>>[];

  @override
  Future<Map<String, Object?>?> readUserProgress({required String uid}) {
    final read = Completer<Map<String, Object?>?>();
    _reads.add(read);
    for (final waiter in _readCountWaiters.toList(growable: false)) {
      if (!waiter.isCompleted && _reads.length >= _readCountTargets[waiter]!) {
        waiter.complete();
      }
    }
    return read.future;
  }

  final Map<Completer<void>, int> _readCountTargets = <Completer<void>, int>{};

  Future<void> waitForReadCount(int count) {
    if (_reads.length >= count) {
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _readCountTargets[waiter] = count;
    _readCountWaiters.add(waiter);
    return waiter.future;
  }

  void completeRead(int index, Map<String, Object?>? document) {
    _reads[index].complete(document);
  }
}

class _FallbackUserProgressRepository implements UserProgressRepository {
  const _FallbackUserProgressRepository();

  @override
  Future<UserProgressReadModel> loadUserProgress() async {
    return const UserProgressReadModel(
      userId: 'fallback-user',
      officialStreakLabel: 'fallback',
      levelLabel: '',
      totalXpLabel: '',
      weeklyXpLabel: '',
      monthlyXpLabel: '',
      weeklyDistanceLabel: '',
      goalProgressLabel: '',
    );
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() {
    return loadUserProgress();
  }
}
