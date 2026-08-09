import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../auth/domain/runiac_auth_service.dart';
import '../data/firebase_friends_repository.dart';
import '../domain/models/friends_read_model.dart';
import '../domain/repositories/friends_repository.dart';

typedef FriendsMutationAction =
    Future<FriendsMutationResult> Function(String ownerUid);

class FriendsScreenController extends ChangeNotifier {
  FriendsScreenController({
    required this.authRepository,
    required this.repository,
  }) {
    _ownerUid = authRepository.currentUser?.uid;
    _authSubscription = authRepository.authStateChanges().listen(
      _handleAuthChanged,
    );
    final ownerUid = _ownerUid;
    if (ownerUid != null) {
      _subscribeToOverview(ownerUid);
    }
  }

  final RuniacAuthRepository authRepository;
  final FriendsRepository repository;

  FriendsOverviewReadModel? get overview => _overview;
  List<FriendUserReadModel>? get searchResults => _searchResults;
  String? get submittedSearch => _submittedSearch;
  String? get errorMessage => _errorMessage;
  String? get ownerUid => _ownerUid;
  bool get isLoading => _isLoading;
  bool get isSearchLoading => _isSearchLoading;

  final Map<String, Object> _inFlightActions = <String, Object>{};
  StreamSubscription<RuniacAuthUser?>? _authSubscription;
  StreamSubscription<FriendsOverviewReadModel>? _overviewSubscription;
  FriendsOverviewReadModel? _overview;
  List<FriendUserReadModel>? _searchResults;
  String? _submittedSearch;
  String? _errorMessage;
  String? _ownerUid;
  var _isLoading = false;
  var _isSearchLoading = false;
  var _disposed = false;
  var _loadGeneration = 0;
  var _searchGeneration = 0;
  var _overviewGeneration = 0;

  bool isActionInFlight(String actionKey) =>
      _inFlightActions.containsKey(actionKey);

  bool hasOutgoingRequest(
    FriendUserReadModel user,
    FriendsOverviewReadModel overview,
  ) {
    return overview.outgoingRequests.any(
          (request) => request.userId == user.userId,
        ) ||
        isActionInFlight('send:${user.userId}');
  }

  void onSearchTextChanged(String text) {
    if (_disposed) return;
    if (_submittedSearch == null || text == _submittedSearch) return;
    _searchGeneration += 1;
    _searchResults = null;
    _isSearchLoading = false;
    _errorMessage = null;
    _notifyListeners();
  }

  Future<void> loadOverview({required String ownerUid}) async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    _isLoading = true;
    _errorMessage = null;
    _notifyListeners();
    try {
      final result = await repository.loadFriendsOverview(ownerUid: ownerUid);
      if (!_isCurrentOwner(ownerUid, generation: generation)) return;
      _overview = result;
      _isLoading = false;
      _errorMessage = null;
      _notifyListeners();
    } catch (error) {
      if (!_isCurrentOwner(ownerUid, generation: generation)) return;
      _isLoading = false;
      _errorMessage = _messageFor(error);
      _notifyListeners();
    }
  }

  Future<void> submitSearch(String input) async {
    if (_disposed) return;
    final ownerUid = _ownerUid;
    if (ownerUid == null) {
      resetForOwner(null);
      return;
    }
    final nickname = input.trim();
    final runeLength = nickname.runes.length;
    if (runeLength < 1 || runeLength > 30) {
      _searchResults = null;
      _submittedSearch = nickname;
      _isSearchLoading = false;
      _errorMessage = 'Nickname must be 1-30 characters.';
      _notifyListeners();
      return;
    }
    final generation = ++_searchGeneration;
    _submittedSearch = nickname;
    _searchResults = null;
    _isSearchLoading = true;
    _errorMessage = null;
    _notifyListeners();
    try {
      final results = await repository.searchFriends(
        ownerUid: ownerUid,
        nickname: nickname,
      );
      if (!_isCurrentOwner(ownerUid) || generation != _searchGeneration) {
        return;
      }
      _searchResults = results.take(1).toList(growable: false);
      _isSearchLoading = false;
      _notifyListeners();
    } catch (error) {
      if (!_isCurrentOwner(ownerUid) || generation != _searchGeneration) {
        return;
      }
      _isSearchLoading = false;
      _errorMessage = _messageFor(error);
      _notifyListeners();
    }
  }

  Future<void> runMutation({
    required String actionKey,
    required FriendsMutationAction action,
  }) async {
    if (_disposed) return;
    final ownerUid = _ownerUid;
    if (ownerUid == null || !_isCurrentOwner(ownerUid)) {
      resetForOwner(null);
      return;
    }
    if (_inFlightActions.containsKey(actionKey)) return;
    final operationToken = Object();
    _inFlightActions[actionKey] = operationToken;
    _errorMessage = null;
    _notifyListeners();
    try {
      await action(ownerUid);
      if (!_isCurrentOwner(ownerUid)) return;
      await loadOverview(ownerUid: ownerUid);
    } catch (error) {
      if (!_isCurrentOwner(ownerUid)) return;
      _errorMessage = _messageFor(error);
      _notifyListeners();
    } finally {
      if (identical(_inFlightActions[actionKey], operationToken)) {
        _inFlightActions.remove(actionKey);
        if (_isCurrentOwner(ownerUid)) _notifyListeners();
      }
    }
  }

  Future<void> retry() async {
    final ownerUid = _ownerUid;
    if (ownerUid == null) return;
    _subscribeToOverview(ownerUid);
  }

  void resetForOwner(String? ownerUid) {
    if (_disposed) return;
    _loadGeneration += 1;
    _searchGeneration += 1;
    _overviewGeneration += 1;
    unawaited(_overviewSubscription?.cancel());
    _overviewSubscription = null;
    _ownerUid = ownerUid;
    _overview = null;
    _searchResults = null;
    _submittedSearch = null;
    _errorMessage = null;
    _isLoading = ownerUid != null;
    _isSearchLoading = false;
    _inFlightActions.clear();
    _notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loadGeneration += 1;
    _searchGeneration += 1;
    _overviewGeneration += 1;
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
    unawaited(_overviewSubscription?.cancel());
    _overviewSubscription = null;
    super.dispose();
  }

  void _handleAuthChanged(RuniacAuthUser? user) {
    if (_disposed) return;
    final nextOwnerUid = user?.uid;
    if (nextOwnerUid == _ownerUid) return;
    resetForOwner(nextOwnerUid);
    if (nextOwnerUid != null) {
      _subscribeToOverview(nextOwnerUid);
    }
  }

  /// Cancels any previous overview subscription for the current owner and
  /// starts a fresh live subscription via [FriendsRepository.watchFriendsOverview].
  /// The one-shot [loadOverview] method remains available for explicit
  /// refreshes (e.g. after a mutation callable succeeds); a subsequent
  /// snapshot emission harmlessly overwrites the same data.
  void _subscribeToOverview(String ownerUid) {
    unawaited(_overviewSubscription?.cancel());
    final generation = ++_overviewGeneration;
    _isLoading = true;
    _errorMessage = null;
    _notifyListeners();
    try {
      _overviewSubscription = repository
          .watchFriendsOverview(ownerUid: ownerUid)
          .listen(
            (result) {
              if (!_isCurrentOverviewSubscription(ownerUid, generation)) {
                return;
              }
              _overview = result;
              _isLoading = false;
              _errorMessage = null;
              _notifyListeners();
            },
            onError: (Object error) {
              if (!_isCurrentOverviewSubscription(ownerUid, generation)) {
                return;
              }
              _isLoading = false;
              _errorMessage = _messageFor(error);
              _notifyListeners();
            },
          );
    } catch (error) {
      if (!_isCurrentOverviewSubscription(ownerUid, generation)) return;
      _isLoading = false;
      _errorMessage = _messageFor(error);
      _notifyListeners();
    }
  }

  bool _isCurrentOverviewSubscription(String ownerUid, int generation) {
    return !_disposed &&
        _ownerUid == ownerUid &&
        authRepository.currentUser?.uid == ownerUid &&
        generation == _overviewGeneration;
  }

  bool _isCurrentOwner(String ownerUid, {int? generation}) {
    return !_disposed &&
        _ownerUid == ownerUid &&
        authRepository.currentUser?.uid == ownerUid &&
        (generation == null || generation == _loadGeneration);
  }

  String _messageFor(Object error) {
    if (error is FriendsRepositoryException) return error.userMessage;
    return 'Friends are temporarily unavailable. Try again.';
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }
}
