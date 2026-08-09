part of 'weekly_workout_detail_screen.dart';

class _DaySelectionRow extends StatelessWidget {
  const _DaySelectionRow({
    required this.snapshot,
    required this.selectedWeekdayIndex,
    required this.onDaySelected,
  });

  final WeeklyWorkoutDetailSnapshot snapshot;
  final int? selectedWeekdayIndex;
  final ValueChanged<_ScheduleDayOption> onDaySelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < _scheduleDayOptions.length; index++) ...[
          Expanded(
            child: _ScheduleDayChip(
              option: _scheduleDayOptions[index],
              selected:
                  selectedWeekdayIndex ==
                  _scheduleDayOptions[index].weekdayIndex,
              current:
                  snapshot.scheduleWeekdayIndex ==
                  _scheduleDayOptions[index].weekdayIndex,
              disabled: snapshot.occupiedScheduleWeekdays.contains(
                _scheduleDayOptions[index].weekdayIndex,
              ),
              onSelected: onDaySelected,
            ),
          ),
          if (index < _scheduleDayOptions.length - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

class _ScheduleDayChip extends StatelessWidget {
  const _ScheduleDayChip({
    required this.option,
    required this.selected,
    required this.current,
    required this.disabled,
    required this.onSelected,
  });

  final _ScheduleDayOption option;
  final bool selected;
  final bool current;
  final bool disabled;
  final ValueChanged<_ScheduleDayOption> onSelected;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = disabled
        ? RuniacColors.textSecondary.withValues(alpha: 0.48)
        : selected
        ? RuniacColors.white
        : RuniacColors.textPrimary;
    final backgroundColor = selected
        ? RuniacColors.primaryBlue
        : disabled
        ? const Color(0xFFEFF3F8)
        : RuniacColors.white;

    return Semantics(
      key: ValueKey('edit_schedule_day_${option.label}'),
      button: true,
      enabled: !disabled,
      selected: selected || current,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: disabled ? null : () => onSelected(option),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? RuniacColors.primaryBlue
                    : RuniacColors.border,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                option.label,
                maxLines: 1,
                style: _previewChipStyle.copyWith(color: foregroundColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomTimeSelectionRow extends StatelessWidget {
  const _CustomTimeSelectionRow({
    required this.selectedTimeLabel,
    required this.onTimePickerRequested,
  });

  final String? selectedTimeLabel;
  final VoidCallback onTimePickerRequested;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('edit_schedule_time_selector'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTimePickerRequested,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF3F8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: RuniacColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedTimeLabel ?? 'Choose time',
                  style: _disabledRowStyle,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: RuniacColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
