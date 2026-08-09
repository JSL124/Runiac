part of 'home_stage_map.dart';

class _HomeActiveChallengeControl extends StatefulWidget {
  const _HomeActiveChallengeControl({
    required this.display,
    required this.onOpen,
    required this.clock,
    required this.ticker,
  });

  final HomeActiveChallengeDisplay display;
  final VoidCallback? onOpen;
  final DateTime Function()? clock;
  final ChallengeTicker? ticker;

  @override
  State<_HomeActiveChallengeControl> createState() =>
      _HomeActiveChallengeControlState();
}

class _HomeActiveChallengeControlState
    extends State<_HomeActiveChallengeControl> {
  late ChallengeCountdownController _countdown;

  @override
  void initState() {
    super.initState();
    _countdown = ChallengeCountdownController(
      clock: widget.clock ?? DateTime.now,
      ticker: widget.ticker,
      scheduledEndsAt: widget.display.scheduledEndsAt,
      isSettling: widget.display.isSettling,
    );
  }

  @override
  void didUpdateWidget(covariant _HomeActiveChallengeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.display != widget.display) {
      _countdown.update(
        scheduledEndsAt: widget.display.scheduledEndsAt,
        isSettling: widget.display.isSettling,
      );
    }
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  /// Minute-granularity remaining phrase so the screen-reader summary never
  /// re-announces on the per-second tick.
  String _remainingPhrase(Duration remaining) {
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    String unit(int value, String noun) =>
        '$value $noun${value == 1 ? '' : 's'}';
    if (days > 0) {
      return '${unit(days, 'day')} ${unit(hours, 'hour')} left';
    }
    if (hours > 0) {
      return '${unit(hours, 'hour')} ${unit(minutes, 'minute')} left';
    }
    return '${unit(minutes, 'minute')} left';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _countdown,
      builder: (context, _) {
        final value = _countdown.value;
        final tierTitle = challengeTierTitle(widget.display.tierId);
        final semanticRemaining = value.isSettling
            ? 'calculating results'
            : _remainingPhrase(value.remaining);
        final semanticLabel =
            'Active $tierTitle challenge, $semanticRemaining. '
            'Opens challenge progress.';
        return Semantics(
          key: const ValueKey<String>('homeActiveChallengeControl'),
          container: true,
          button: true,
          label: semanticLabel,
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpen,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChallengeBadgeImage(
                    tierId: widget.display.tierId,
                    size: 62,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: _homeStageControlDecoration(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      value.isSettling ? ChallengeCopy.calculating : value.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
