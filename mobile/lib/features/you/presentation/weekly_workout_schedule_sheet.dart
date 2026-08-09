part of 'weekly_workout_detail_screen.dart';

class _EditScheduleSheet extends StatefulWidget {
  const _EditScheduleSheet({
    required this.snapshot,
    required this.onScheduleChanged,
  });

  final WeeklyWorkoutDetailSnapshot snapshot;
  final ValueChanged<WorkoutScheduleEditSelection>? onScheduleChanged;

  @override
  State<_EditScheduleSheet> createState() => _EditScheduleSheetState();
}

class _EditScheduleSheetState extends State<_EditScheduleSheet> {
  int? _selectedWeekdayIndex;
  String? _selectedDayLabel;
  String? _selectedTimeLabel;

  WeeklyWorkoutDetailSnapshot get snapshot => widget.snapshot;

  bool get _canSave {
    final selectedWeekdayIndex = _selectedWeekdayIndex;
    return selectedWeekdayIndex != null &&
        selectedWeekdayIndex != snapshot.scheduleWeekdayIndex &&
        !snapshot.occupiedScheduleWeekdays.contains(selectedWeekdayIndex) &&
        _selectedTimeLabel != null;
  }

  String get _newScheduleLabel {
    final day = _selectedDayLabel;
    final time = _selectedTimeLabel;
    if (day == null || time == null) {
      return 'Select a day and time';
    }
    return '$day · $time';
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.86;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: _NoOverscroll(
          key: const ValueKey('edit_schedule_no_overscroll'),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: _EditScheduleDragHandle()),
                  const SizedBox(height: 12),
                  Text('Edit schedule', style: _sheetTitleStyle),
                  const SizedBox(height: 10),
                  const _EditScheduleBrandAccent(),
                  const SizedBox(height: 16),
                  _ScheduleComparisonCard(
                    currentLabel: snapshot.editScheduleCurrentLabel,
                    newLabel: _newScheduleLabel,
                  ),
                  const SizedBox(height: 16),
                  _ScheduleEditorCard(
                    snapshot: snapshot,
                    selectedWeekdayIndex: _selectedWeekdayIndex,
                    selectedTimeLabel: _selectedTimeLabel,
                    onDaySelected: (day) {
                      if (snapshot.occupiedScheduleWeekdays.contains(
                            day.weekdayIndex,
                          ) ||
                          day.weekdayIndex == snapshot.scheduleWeekdayIndex) {
                        return;
                      }
                      setState(() {
                        _selectedWeekdayIndex = day.weekdayIndex;
                        _selectedDayLabel = day.label;
                      });
                    },
                    onTimePickerRequested: _showTimePicker,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _canSave
                        ? 'This change updates the plan shown in this session.'
                        : 'Choose an open day and a time to save this schedule.',
                    style: _smallBodyStyle,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _canSave
                          ? () {
                              widget.onScheduleChanged?.call(
                                WorkoutScheduleEditSelection(
                                  weekdayIndex: _selectedWeekdayIndex!,
                                  dayLabel: _selectedDayLabel!,
                                  timeLabel: _selectedTimeLabel!,
                                ),
                              );
                              Navigator.of(context).pop(true);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        disabledBackgroundColor:
                            RuniacColors.disabledButtonBackground,
                        disabledForegroundColor:
                            RuniacColors.disabledButtonForeground,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        textStyle: _disabledSaveActionStyle,
                      ),
                      child: const Text('Save New Schedule'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: RuniacColors.textPrimary,
                        side: const BorderSide(color: RuniacColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        textStyle: _closeActionStyle,
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTimePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: RuniacColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => _TimePickerSheet(
        selectedTimeLabel: _selectedTimeLabel,
        onTimeChanged: (time) {
          if (!mounted) {
            return;
          }
          setState(() => _selectedTimeLabel = time);
        },
      ),
    );
  }
}
