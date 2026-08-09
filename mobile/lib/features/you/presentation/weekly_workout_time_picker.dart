part of 'weekly_workout_detail_screen.dart';

class _TimePickerSheet extends StatefulWidget {
  const _TimePickerSheet({
    required this.selectedTimeLabel,
    required this.onTimeChanged,
  });

  final String? selectedTimeLabel;
  final ValueChanged<String> onTimeChanged;

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  static const _hours = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  static const _periods = ['AM', 'PM'];
  static const _itemExtent = 38.0;

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late final FixedExtentScrollController _periodController;
  late int _selectedHour;
  late int _selectedMinute;
  late String _selectedPeriod;

  @override
  void initState() {
    super.initState();
    final initialTime = _WheelTimeSelection.fromLabel(widget.selectedTimeLabel);
    _selectedHour = initialTime.hour;
    _selectedMinute = initialTime.minute;
    _selectedPeriod = initialTime.period;
    _hourController = FixedExtentScrollController(
      initialItem: _selectedHour - 1,
    );
    _minuteController = FixedExtentScrollController(
      initialItem: _selectedMinute,
    );
    _periodController = FixedExtentScrollController(
      initialItem: _periods.indexOf(_selectedPeriod),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onTimeChanged(_formattedSelection);
    });
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  String get _formattedSelection {
    final minute = _selectedMinute.toString().padLeft(2, '0');
    return '$_selectedHour:$minute $_selectedPeriod';
  }

  void _notifySelectionChanged() {
    widget.onTimeChanged(_formattedSelection);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.62,
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: _EditScheduleDragHandle()),
                const SizedBox(height: 12),
                Text('Select time', style: _sheetTitleStyle),
                const SizedBox(height: 12),
                SizedBox(
                  key: const ValueKey('edit_schedule_time_wheel_picker'),
                  height: 196,
                  child: Row(
                    children: [
                      Expanded(
                        child: _TimeWheelPicker(
                          key: const ValueKey('edit_schedule_time_hour_picker'),
                          controller: _hourController,
                          itemExtent: _itemExtent,
                          children: [
                            for (final hour in _hours)
                              Center(
                                child: Text(
                                  hour.toString(),
                                  style: _timeWheelTextStyle,
                                ),
                              ),
                          ],
                          onSelectedItemChanged: (index) {
                            setState(() => _selectedHour = _hours[index]);
                            _notifySelectionChanged();
                          },
                        ),
                      ),
                      Expanded(
                        child: _TimeWheelPicker(
                          key: const ValueKey(
                            'edit_schedule_time_minute_picker',
                          ),
                          controller: _minuteController,
                          itemExtent: _itemExtent,
                          children: [
                            for (var minute = 0; minute < 60; minute++)
                              Center(
                                child: Text(
                                  minute.toString().padLeft(2, '0'),
                                  style: _timeWheelTextStyle,
                                ),
                              ),
                          ],
                          onSelectedItemChanged: (index) {
                            setState(() => _selectedMinute = index);
                            _notifySelectionChanged();
                          },
                        ),
                      ),
                      Expanded(
                        child: _TimeWheelPicker(
                          key: const ValueKey(
                            'edit_schedule_time_period_picker',
                          ),
                          controller: _periodController,
                          itemExtent: _itemExtent,
                          children: [
                            for (final period in _periods)
                              Center(
                                child: Text(period, style: _timeWheelTextStyle),
                              ),
                          ],
                          onSelectedItemChanged: (index) {
                            setState(() => _selectedPeriod = _periods[index]);
                            _notifySelectionChanged();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
