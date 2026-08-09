part of 'home_stage_map.dart';

class _GuideSpeechBubble extends StatelessWidget {
  const _GuideSpeechBubble({
    required this.state,
    required this.isRestDay,
    required this.onAdvance,
    required this.onDismiss,
    super.key,
  });

  final HomeGuideCycleState state;
  final bool isRestDay;
  final VoidCallback onAdvance;
  final VoidCallback onDismiss;

  static const String _fallbackErrorText =
      "Let's get moving — you've got this today.";

  @override
  Widget build(BuildContext context) {
    final message = state.currentMessage;
    return _GuideBubbleCard(
      key: ValueKey<String>('${state.isLoading}:${message?.text}'),
      message: message,
      isLoading: state.isLoading,
      isUnavailable: !state.isLoading && message == null,
      isRestDay: isRestDay,
      canAdvance: state.canAdvance,
      fallbackText: _fallbackErrorText,
      onAdvance: onAdvance,
      onDismiss: onDismiss,
    );
  }
}

class _GuideBubbleCard extends StatelessWidget {
  const _GuideBubbleCard({
    required this.message,
    required this.isLoading,
    required this.isUnavailable,
    required this.isRestDay,
    required this.canAdvance,
    required this.fallbackText,
    required this.onAdvance,
    required this.onDismiss,
    super.key,
  });

  final HomeGuideMessage? message;
  final bool isLoading;
  final bool isUnavailable;
  final bool isRestDay;

  /// Whether the resolved content has another message to move to. Single
  /// message content (the on-device plan read-out) shows everything at once,
  /// so the bubble is not tappable and announces no advance hint.
  final bool canAdvance;
  final String fallbackText;
  final VoidCallback onAdvance;
  final VoidCallback onDismiss;

  String get _bodyText {
    if (isLoading) {
      return 'Preparing your guide...';
    }
    return message?.text ?? fallbackText;
  }

  String get _bodySemanticsLabel {
    if (isLoading) {
      return 'Guide message loading. Please wait.';
    }
    if (isUnavailable) {
      return 'Guide message unavailable.';
    }
    if (isRestDay) {
      return switch (message!.kind) {
        HomeGuideMessageKind.planSummary =>
          'Rest-day cheer. Tap to hear a rest tip.',
        HomeGuideMessageKind.runningTip =>
          'Rest-day tip. Tap to hear why rest matters.',
        HomeGuideMessageKind.progressionCheckIn =>
          'Why rest matters. Tap to return to your rest-day cheer.',
        HomeGuideMessageKind.planBrief => "Today's rest day.",
      };
    }
    return switch (message!.kind) {
      HomeGuideMessageKind.planSummary =>
        'Plan summary. Tap to hear a running tip.',
      HomeGuideMessageKind.runningTip =>
        'Running tip. Tap to hear a progression check-in.',
      HomeGuideMessageKind.progressionCheckIn =>
        'Progression check-in. Tap to return to your plan summary.',
      HomeGuideMessageKind.planBrief => "Today's plan and its steps.",
    };
  }

  bool get _canAdvance => !isLoading && !isUnavailable && canAdvance;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('homeGuideBubble'),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RuniacColors.cardBorder, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: RuniacColors.softCardShadow,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: _canAdvance,
              label: _bodySemanticsLabel,
              child: ExcludeSemantics(
                child: GestureDetector(
                  key: const ValueKey<String>('homeGuideBubbleBody'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _canAdvance ? onAdvance : null,
                  // The plan read-out is a multi-line message (summary line
                  // plus numbered steps) and the bubble sits in the bounded
                  // strip above the character, so the body scrolls rather
                  // than overflowing when a long session is listed.
                  child: SingleChildScrollView(
                    child: Text(
                      _bodyText,
                      style: TextStyle(
                        fontSize: isLoading ? 14 : 13,
                        height: 1.35,
                        fontWeight: isLoading
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: isLoading
                            ? RuniacColors.textSecondary
                            : RuniacColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: Semantics(
              button: true,
              label: 'Close guide message',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: const Tooltip(
                  message: 'Close guide message',
                  child: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: RuniacColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
