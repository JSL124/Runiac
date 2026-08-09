part of 'cool_down_guide_screen.dart';

class _StretchExerciseView extends StatelessWidget {
  const _StretchExerciseView({required this.step, required this.compact});

  final StretchStep step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Stretch ${step.exerciseIndex + 1} of 8',
              style: const TextStyle(
                color: _navy45,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            if (step.side != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: _navy06,
                  border: Border.all(color: _navy10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  step.side == StretchSide.left ? 'Left' : 'Right',
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: compact ? 3 : 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: compact ? 130 : 190),
          child: Semantics(
            label: '${step.exercise.name} demonstration animation',
            child: Image.asset(
              step.exercise.assetPath,
              gaplessPlayback: true,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
        ),
        SizedBox(height: compact ? 3 : 8),
        Text(
          step.exercise.name,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _navy,
            fontSize: compact ? 18 : 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        SizedBox(height: compact ? 4 : 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            step.exercise.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _navy60,
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w500,
              height: 1.48,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );
  }
}
