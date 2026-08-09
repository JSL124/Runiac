import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/guide/home_guide_agent.dart';

/// Immutable identity for one displayed stage and its plan-display context.
///
/// The value is local-only. It lets the Home surface reuse a single in-memory
/// agent future while a stage/request pair is unchanged; a new controller is
/// intentionally a fresh session and asks the server cache again.
@immutable
class HomeGuideCycleSignature {
  const HomeGuideCycleSignature._({
    required this.stageId,
    required this.request,
    required this._encodedValue,
  });

  factory HomeGuideCycleSignature.forRequest({
    required String stageId,
    required HomeGuideRequest request,
  }) {
    final snapshot = HomeGuideRequest(
      planTitle: request.planTitle,
      weekNumber: request.weekNumber,
      weekFocus: request.weekFocus,
      dayLabel: request.dayLabel,
      workoutTitle: request.workoutTitle,
      durationMinutes: request.durationMinutes,
      intensityLabel: request.intensityLabel,
      description: request.description,
      steps: List<String>.unmodifiable(request.steps),
      supportiveNote: request.supportiveNote,
      isRestDay: request.isRestDay,
    );
    return HomeGuideCycleSignature._(
      stageId: stageId,
      request: snapshot,
      encodedValue: jsonEncode(<Object?>[
        stageId,
        snapshot.planTitle,
        snapshot.weekNumber,
        snapshot.weekFocus,
        snapshot.dayLabel,
        snapshot.workoutTitle,
        snapshot.durationMinutes,
        snapshot.intensityLabel,
        snapshot.description,
        snapshot.steps,
        snapshot.supportiveNote,
        snapshot.isRestDay,
      ]),
    );
  }

  final String stageId;
  final HomeGuideRequest request;
  final String _encodedValue;

  @override
  bool operator ==(Object other) =>
      other is HomeGuideCycleSignature && _encodedValue == other._encodedValue;

  @override
  int get hashCode => _encodedValue.hashCode;
}

/// Read-only local state for the Home guide's message cycle.
///
/// The message count comes from the resolved [content], not from a constant:
/// the AI guide answers with a three-slot cycle and the on-device plan
/// read-out answers with a single message, and both present here.
@immutable
class HomeGuideCycleState {
  const HomeGuideCycleState({
    required this.isVisible,
    required this.isLoading,
    required this.currentIndex,
    required this.content,
  });

  final bool isVisible;
  final bool isLoading;
  final int currentIndex;
  final HomeGuideContent? content;

  List<HomeGuideMessage> get _messages =>
      content?.messages ?? const <HomeGuideMessage>[];

  HomeGuideMessage? get currentMessage {
    if (isLoading || currentIndex >= _messages.length) {
      return null;
    }
    return _messages[currentIndex];
  }

  /// Whether tapping the bubble moves to another message. Single-message
  /// content has nowhere to advance to, so the bubble offers no tap
  /// affordance and announces no "tap to hear" hint.
  bool get canAdvance => !isLoading && _messages.length > 1;
}

/// Owns the local-only presentation cycle for one guide answer.
///
/// It makes no persistence, progression, quota, or network-policy decision.
/// The supplied [HomeGuideAgent] remains the sole source of guide content.
class HomeGuideCycleController extends ChangeNotifier {
  HomeGuideCycleController({
    required this.agent,
    required HomeGuideCycleSignature signature,
  }) {
    _activate(signature);
  }

  final HomeGuideAgent agent;
  final Map<HomeGuideCycleSignature, Future<HomeGuideContent>> _bundleFutures =
      <HomeGuideCycleSignature, Future<HomeGuideContent>>{};

  late HomeGuideCycleSignature _activeSignature;
  late Future<HomeGuideContent> _activeBundleFuture;
  late HomeGuideCycleState _state;
  bool _isDisposed = false;

  HomeGuideCycleState get state => _state;

  /// Completes after the active content has settled, including a safe error
  /// settlement. It exists for deterministic widget/controller coordination.
  Future<void> get settled => _activeBundleFuture.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {},
  );

  /// Starts a new local cycle only when the stage/request display signature
  /// changes. Returning false means current visibility and message remain.
  bool updateSignature(HomeGuideCycleSignature signature) {
    if (signature == _activeSignature) {
      return false;
    }
    _activate(signature);
    return true;
  }

  void show() {
    if (_state.isVisible) {
      return;
    }
    _state = HomeGuideCycleState(
      isVisible: true,
      isLoading: _state.isLoading,
      currentIndex: _state.currentIndex,
      content: _state.content,
    );
    notifyListeners();
  }

  void hide() {
    if (!_state.isVisible) {
      return;
    }
    _state = HomeGuideCycleState(
      isVisible: false,
      isLoading: _state.isLoading,
      currentIndex: _state.currentIndex,
      content: _state.content,
    );
    notifyListeners();
  }

  /// Advances only after content has resolved, and only when there is more
  /// than one message to move between.
  void advance() {
    if (!_state.isVisible || !_state.canAdvance) {
      return;
    }
    final messageCount = _state.content!.messages.length;
    _state = HomeGuideCycleState(
      isVisible: _state.isVisible,
      isLoading: false,
      currentIndex: (_state.currentIndex + 1) % messageCount,
      content: _state.content,
    );
    notifyListeners();
  }

  void _activate(HomeGuideCycleSignature signature) {
    _activeSignature = signature;
    final bundleFuture = _bundleFutures.putIfAbsent(
      signature,
      () => Future<HomeGuideContent>.sync(
        () => agent.explainTodayPlan(signature.request),
      ),
    );
    _activeBundleFuture = bundleFuture;
    _state = const HomeGuideCycleState(
      isVisible: true,
      isLoading: true,
      currentIndex: 0,
      content: null,
    );
    notifyListeners();
    bundleFuture.then(
      (content) => _settleContent(signature, bundleFuture, content),
      onError: (Object _, StackTrace _) =>
          _settleFailure(signature, bundleFuture),
    );
  }

  void _settleContent(
    HomeGuideCycleSignature signature,
    Future<HomeGuideContent> bundleFuture,
    HomeGuideContent content,
  ) {
    if (!_isActive(signature, bundleFuture)) {
      return;
    }
    _state = HomeGuideCycleState(
      isVisible: _state.isVisible,
      isLoading: false,
      currentIndex: 0,
      content: content,
    );
    notifyListeners();
  }

  void _settleFailure(
    HomeGuideCycleSignature signature,
    Future<HomeGuideContent> bundleFuture,
  ) {
    if (!_isActive(signature, bundleFuture)) {
      return;
    }
    _state = HomeGuideCycleState(
      isVisible: _state.isVisible,
      isLoading: false,
      currentIndex: 0,
      content: null,
    );
    notifyListeners();
  }

  bool _isActive(
    HomeGuideCycleSignature signature,
    Future<HomeGuideContent> bundleFuture,
  ) =>
      !_isDisposed &&
      signature == _activeSignature &&
      identical(bundleFuture, _activeBundleFuture);

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
