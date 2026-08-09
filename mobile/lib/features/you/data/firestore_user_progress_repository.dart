import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../auth/domain/runiac_auth_service.dart';
import '../domain/models/user_progress_read_model.dart';
import '../domain/repositories/user_progress_repository.dart';
import 'local_user_progress_cache_store.dart';
import 'user_streak_refresh_service.dart';

/// Reads the runner's progression state — level, XP, streak — from Firestore.
///
/// Read-only on purpose: these fields are backend-owned and client writes to
/// them are rejected by `firestore.rules`. The only thing this repository
/// triggers is a streak *refresh* (`UserStreakRefreshService`), which asks the
/// backend to re-evaluate an expired streak rather than editing it here.
///
/// Results are cached locally so the You tab can render immediately on a cold
/// start instead of showing a spinner over the user's own progress.
abstract interface class UserProgressDocumentReader {
  Future<Map<String, Object?>?> readUserProgress({required String uid});
}

abstract interface class LiveUserProgressDocumentReader
    implements UserProgressDocumentReader {
  Stream<void> watchUserProgress({required String uid});
}

class FirestoreUserProgressDocumentReader
    implements LiveUserProgressDocumentReader {
  FirestoreUserProgressDocumentReader({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<Map<String, Object?>?> readUserProgress({required String uid}) async {
    final snapshot = await _firestore.collection('userProfiles').doc(uid).get();
    final data = snapshot.data();
    return data == null ? null : Map<String, Object?>.from(data);
  }

  @override
  Stream<void> watchUserProgress({required String uid}) {
    return _firestore
        .collection('userProfiles')
        .doc(uid)
        .snapshots()
        .map<void>((_) {});
  }
}

class FirestoreUserProgressRepository
    implements UserProgressRepository, LiveUserProgressRepository {
  FirestoreUserProgressRepository({
    required this.authRepository,
    UserProgressDocumentReader? reader,
    LocalUserProgressCacheStore? cacheStore,
    this.streakRefreshService = const NoopUserStreakRefreshService(),
    DateTime Function()? clock,
    this.fallbackRepository = const StaticUserProgressRepository(),
  }) : _reader = reader ?? FirestoreUserProgressDocumentReader(),
       _cacheStore =
           cacheStore ?? const SharedPreferencesLocalUserProgressCacheStore(),
       _clock = clock ?? DateTime.now;

  final RuniacAuthRepository authRepository;
  final UserProgressDocumentReader _reader;
  final LocalUserProgressCacheStore _cacheStore;
  final DateTime Function() _clock;
  final UserStreakRefreshService streakRefreshService;
  final UserProgressRepository fallbackRepository;
  var _cacheWriteGeneration = 0;

  @override
  Future<UserProgressReadModel> loadUserProgress() async {
    final currentUser = authRepository.currentUser;
    if (currentUser == null) {
      return fallbackRepository.loadUserProgress();
    }

    final cacheWriteGeneration = _cacheWriteGeneration;
    try {
      await _refreshStreakSafely();
      return await _readAndCacheUserProgress(
        currentUser.uid,
        cacheWriteGeneration: cacheWriteGeneration,
      );
    } on Object catch (error, stackTrace) {
      final cached = await _loadCacheSafely(currentUser.uid);
      if (_isUsableCacheForCurrentUser(cached, currentUser.uid)) {
        return cached!.progress;
      }
      _reportCacheError(
        error,
        stackTrace,
        'loading user progress from backend',
      );
      rethrow;
    }
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() async {
    final currentUser = authRepository.currentUser;
    if (currentUser == null) {
      return fallbackRepository.refreshUserProgress();
    }

    _cacheWriteGeneration += 1;
    await _refreshStreakSafely();
    return _readAndCacheUserProgress(
      currentUser.uid,
      cacheWriteGeneration: _cacheWriteGeneration,
    );
  }

  @override
  Stream<UserProgressReadModel> watchUserProgress() {
    final currentUser = authRepository.currentUser;
    final reader = _reader;
    if (currentUser == null || reader is! LiveUserProgressDocumentReader) {
      return Stream.fromFuture(loadUserProgress());
    }
    final cacheWriteGeneration = _cacheWriteGeneration;
    return reader
        .watchUserProgress(uid: currentUser.uid)
        .asyncMap(
          (_) => _readAndCacheUserProgress(
            currentUser.uid,
            cacheWriteGeneration: cacheWriteGeneration,
          ),
        );
  }

  Future<void> _refreshStreakSafely() async {
    try {
      await streakRefreshService.refreshStreakStatus();
    } on Object catch (error, stackTrace) {
      _reportCacheError(error, stackTrace, 'refreshing streak status');
    }
  }

  Future<UserProgressReadModel> _readAndCacheUserProgress(
    String uid, {
    required int cacheWriteGeneration,
  }) async {
    final data = await _reader.readUserProgress(uid: uid);
    if (data == null) {
      final emptyProgress = _emptyProgress(uid);
      await _saveCacheSafely(
        emptyProgress,
        cacheWriteGeneration: cacheWriteGeneration,
      );
      return emptyProgress;
    }

    final progress = UserProgressReadModel(
      userId: uid,
      officialStreakLabel: _streakLabel(data['streakCount']),
      officialStreakCount: _nonNegativeInteger(data['streakCount']),
      lastStreakRunDate: _stringOrNull(data['lastStreakRunDate']),
      level: _nonNegativeInteger(data['level']),
      levelProgressFraction: _progressFraction(data['levelProgressPercent']),
      totalXp: _nonNegativeIntegerOrNull(data['totalXp']),
      nextLevelXp: _nonNegativeIntegerOrNull(data['nextLevelXp']),
      xpToNextLevel: _nonNegativeIntegerOrNull(data['xpToNextLevel']),
      divisionKey: _string(data['divisionKey']),
      divisionLabel: _string(data['divisionLabel']),
      isMaxLevel:
          data.containsKey('xpToNextLevel') && data['xpToNextLevel'] == null,
      levelLabel: _string(data['levelLabel']),
      totalXpLabel: _string(data['totalXpLabel']),
      monthlyXpLabel: _string(data['monthlyXpLabel']),
      weeklyXpLabel: '',
      weeklyDistanceLabel: _string(data['weeklyDistanceLabel']),
      goalProgressLabel: _string(data['goalProgressLabel']),
      longestStreakLabel: _string(data['longestStreakLabel']),
      totalDistanceLabel: _string(data['totalDistanceLabel']),
    );
    await _saveCacheSafely(
      progress,
      cacheWriteGeneration: cacheWriteGeneration,
    );
    return progress;
  }

  UserProgressReadModel _emptyProgress(String uid) {
    return UserProgressReadModel(
      userId: uid,
      officialStreakLabel: '',
      levelLabel: '',
      totalXpLabel: '',
      weeklyXpLabel: '',
      monthlyXpLabel: '',
      weeklyDistanceLabel: '',
      goalProgressLabel: '',
    );
  }

  String _streakLabel(Object? streakCount) {
    if (streakCount is! int || streakCount <= 0) {
      return '0 days';
    }
    return streakCount == 1 ? '1 day' : '$streakCount days';
  }

  String _string(Object? value) {
    return value is String ? value : '';
  }

  String? _stringOrNull(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }

  int _nonNegativeInteger(Object? value) {
    return value is int && value >= 0 ? value : 0;
  }

  int? _nonNegativeIntegerOrNull(Object? value) {
    return value is int && value >= 0 ? value : null;
  }

  double _progressFraction(Object? value) {
    if (value is int) {
      return value.clamp(0, 100) / 100;
    }
    if (value is double) {
      return value.clamp(0, 100) / 100;
    }
    return 0;
  }

  Future<LocalUserProgressCacheEntry?> _loadCacheSafely(String uid) async {
    try {
      return await _cacheStore.load(uid: uid);
    } on Object catch (error, stackTrace) {
      _reportCacheError(error, stackTrace, 'loading user progress cache');
      return null;
    }
  }

  Future<void> _saveCacheSafely(
    UserProgressReadModel progress, {
    required int cacheWriteGeneration,
  }) async {
    if (cacheWriteGeneration != _cacheWriteGeneration) {
      return;
    }
    try {
      await _cacheStore.save(
        LocalUserProgressCacheEntry(
          uid: progress.userId,
          refreshedAt: _clock(),
          progress: progress,
        ),
      );
    } on Object catch (error, stackTrace) {
      _reportCacheError(error, stackTrace, 'saving user progress cache');
      return;
    }
  }

  void _reportCacheError(
    Object error,
    StackTrace stackTrace,
    String operation,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'runiac user progress repository',
        context: ErrorDescription(operation),
      ),
    );
  }

  bool _isToday(DateTime refreshedAt) {
    final now = _clock();
    return refreshedAt.year == now.year &&
        refreshedAt.month == now.month &&
        refreshedAt.day == now.day;
  }

  bool _isUsableCacheForCurrentUser(
    LocalUserProgressCacheEntry? cached,
    String uid,
  ) {
    return cached != null &&
        cached.uid == uid &&
        cached.progress.userId == uid &&
        _isToday(cached.refreshedAt);
  }
}
