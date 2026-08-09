part of 'run_launch_screen.dart';

class _PreRunSheetContent extends StatelessWidget {
  const _PreRunSheetContent({
    this.permissionMessage,
    this.plannedWorkout,
    required this.onStart,
  });

  final String? permissionMessage;
  final PlannedRunContext? plannedWorkout;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final startHeight = compact ? 56.0 : 66.0;
        final planned = plannedWorkout;
        final planLabel = planned == null
            ? _defaultRunLaunchSnapshot.planLabel
            : planned.alreadyCompletedToday
            ? '${planned.title.toUpperCase()} COMPLETE'
            : planned.title.toUpperCase();
        final primaryValue =
            planned?.primaryValueLabel ??
            _defaultRunLaunchSnapshot.distanceValue;
        final primaryUnit =
            planned?.primaryUnitLabel ??
            _defaultRunLaunchSnapshot.distanceUnitLabel;
        final supportLabel =
            planned?.supportLabel ?? _defaultRunLaunchSnapshot.paceLabel;
        final secondarySupportLabel = planned?.secondarySupportLabel;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              planLabel,
              style: const TextStyle(
                color: _sportOrange,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            SizedBox(height: compact ? 16 : 22),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(
                  primaryValue,
                  style: const TextStyle(
                    color: _panelTextBlue,
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    height: 0.95,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: primaryUnit.isEmpty
                      ? const SizedBox.shrink()
                      : Text(
                          primaryUnit,
                          style: const TextStyle(
                            color: _mutedBlue,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              supportLabel,
              style: const TextStyle(
                color: _mutedBlue,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (secondarySupportLabel case final label?) ...[
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: _mutedBlue,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (planned case final workout?
                when !workout.alreadyCompletedToday) ...[
              const SizedBox(height: 8),
              Text(
                workout.supportiveNote,
                style: const TextStyle(
                  color: _mutedBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (permissionMessage case final message?) ...[
              SizedBox(height: compact ? 12 : 14),
              _RunPermissionGuidance(message: message),
            ],
            SizedBox(height: compact ? 18 : 24),
            SizedBox(
              width: double.infinity,
              height: startHeight,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded, size: 32),
                label: Text(_defaultRunLaunchSnapshot.startLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: _sportOrange,
                  foregroundColor: RuniacColors.white,
                  elevation: 8,
                  shadowColor: _orangeShadow,
                  textStyle: TextStyle(
                    fontSize: compact ? 24 : 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RunPermissionGuidance extends StatelessWidget {
  const _RunPermissionGuidance({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('runPermissionGuidance'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: _sportOrange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: _panelTextBlue,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.28,
            ),
          ),
        ),
      ],
    );
  }
}
