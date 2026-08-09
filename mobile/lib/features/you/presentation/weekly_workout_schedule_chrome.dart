part of 'weekly_workout_detail_screen.dart';

class _EditScheduleDragHandle extends StatelessWidget {
  const _EditScheduleDragHandle();

  @override
  Widget build(BuildContext context) {
    return const RuniacBottomSheetHandle(
      key: ValueKey('edit_schedule_drag_handle'),
      width: 44,
      height: 4,
      color: Color(0xFFD7DCE3),
    );
  }
}

class _EditScheduleBrandAccent extends StatelessWidget {
  const _EditScheduleBrandAccent();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('edit_schedule_brand_accent'),
      children: [
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: RuniacColors.primaryBlue,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 34,
          height: 4,
          decoration: BoxDecoration(
            color: RuniacColors.accentOrange,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class _ScheduleComparisonCard extends StatelessWidget {
  const _ScheduleComparisonCard({
    required this.currentLabel,
    required this.newLabel,
  });

  final String currentLabel;
  final String newLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ScheduleComparisonItem(
              label: 'Current schedule',
              value: currentLabel,
            ),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.arrow_forward_rounded,
            color: RuniacColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ScheduleComparisonItem(
              label: 'New schedule',
              value: newLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleComparisonItem extends StatelessWidget {
  const _ScheduleComparisonItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _sheetMutedLabelStyle),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1, style: _bodyStrongStyle),
        ),
      ],
    );
  }
}

class _ScheduleEditorCard extends StatelessWidget {
  const _ScheduleEditorCard({
    required this.snapshot,
    required this.selectedWeekdayIndex,
    required this.selectedTimeLabel,
    required this.onDaySelected,
    required this.onTimePickerRequested,
  });

  final WeeklyWorkoutDetailSnapshot snapshot;
  final int? selectedWeekdayIndex;
  final String? selectedTimeLabel;
  final ValueChanged<_ScheduleDayOption> onDaySelected;
  final VoidCallback onTimePickerRequested;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select day', style: _sheetMutedLabelStyle),
          const SizedBox(height: 8),
          _DaySelectionRow(
            snapshot: snapshot,
            selectedWeekdayIndex: selectedWeekdayIndex,
            onDaySelected: onDaySelected,
          ),
          const SizedBox(height: 12),
          const Text('Select time', style: _sheetMutedLabelStyle),
          const SizedBox(height: 8),
          _CustomTimeSelectionRow(
            selectedTimeLabel: selectedTimeLabel,
            onTimePickerRequested: onTimePickerRequested,
          ),
        ],
      ),
    );
  }
}
