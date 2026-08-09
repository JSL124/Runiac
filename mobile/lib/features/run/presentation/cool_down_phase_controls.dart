part of 'cool_down_guide_screen.dart';

class _TopNav extends StatelessWidget {
  const _TopNav({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            style: IconButton.styleFrom(
              foregroundColor: _navy45,
              minimumSize: const Size(40, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.chevron_left_rounded, size: 30),
          ),
          const Expanded(
            child: Text(
              'Cool down guide',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _navy,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _CoolDownPhaseSelector extends StatelessWidget {
  const _CoolDownPhaseSelector({
    required this.phase,
    required this.completedPhases,
  });

  final CoolDownPhase phase;
  final Set<CoolDownPhase> completedPhases;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _navy06,
        border: Border.all(color: _navy10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: SizedBox(
        height: 42,
        child: Stack(
          children: [
            AnimatedAlign(
              alignment: phase == CoolDownPhase.walk
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: _pureWhite,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _PhasePill(
                  label: 'Walk',
                  number: '1',
                  active: phase == CoolDownPhase.walk,
                  done: completedPhases.contains(CoolDownPhase.walk),
                ),
                const SizedBox(width: 5),
                _PhasePill(
                  label: 'Stretch',
                  number: '2',
                  active: phase == CoolDownPhase.stretch,
                  done: completedPhases.contains(CoolDownPhase.stretch),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PhasePill extends StatelessWidget {
  const _PhasePill({
    required this.label,
    required this.number,
    required this.active,
    required this.done,
  });

  final String label;
  final String number;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? _navy : (done ? _navy18 : _navy12),
                shape: BoxShape.circle,
              ),
              child: done && !active
                  ? const Icon(Icons.check_rounded, color: _navy60, size: 12)
                  : Text(
                      number,
                      style: TextStyle(
                        color: active ? _pureWhite : _navy45,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? _navy : _navy45,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
