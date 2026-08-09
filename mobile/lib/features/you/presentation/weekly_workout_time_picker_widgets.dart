part of 'weekly_workout_detail_screen.dart';

/// The wheel pickers for choosing when a planned session happens.
///
/// Split out of `weekly_workout_detail_screen.dart` as a `part` to keep that
/// screen readable; these widgets are private to it. [_WheelTimeSelection] is
/// what keeps the hour, minute and meridiem wheels consistent with each other,
/// so the screen deals in one selection rather than three controllers.
class _TimeWheelPicker extends StatelessWidget {
  const _TimeWheelPicker({
    required this.controller,
    required this.itemExtent,
    required this.children,
    required this.onSelectedItemChanged,
    super.key,
  });

  final FixedExtentScrollController controller;
  final double itemExtent;
  final List<Widget> children;
  final ValueChanged<int> onSelectedItemChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoPicker(
      scrollController: controller,
      itemExtent: itemExtent,
      magnification: 1.08,
      squeeze: 1.08,
      useMagnifier: true,
      selectionOverlay: const _TimePickerSelectionOverlay(),
      onSelectedItemChanged: onSelectedItemChanged,
      children: children,
    );
  }
}

class _TimePickerSelectionOverlay extends StatelessWidget {
  const _TimePickerSelectionOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        children: [
          Container(height: 1, color: RuniacColors.border),
          const Spacer(),
          Container(height: 1, color: RuniacColors.border),
        ],
      ),
    );
  }
}

class _WheelTimeSelection {
  const _WheelTimeSelection({
    required this.hour,
    required this.minute,
    required this.period,
  });

  factory _WheelTimeSelection.fromLabel(String? label) {
    if (label == null) {
      return const _WheelTimeSelection(hour: 7, minute: 0, period: 'PM');
    }
    final match = RegExp(r'^(\d{1,2}):(\d{2}) (AM|PM)$').firstMatch(label);
    if (match == null) {
      return const _WheelTimeSelection(hour: 7, minute: 0, period: 'PM');
    }
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    final period = match.group(3)!;
    if (hour == null ||
        hour < 1 ||
        hour > 12 ||
        minute == null ||
        minute > 59) {
      return const _WheelTimeSelection(hour: 7, minute: 0, period: 'PM');
    }
    return _WheelTimeSelection(hour: hour, minute: minute, period: period);
  }

  final int hour;
  final int minute;
  final String period;
}

class _ScheduleDayOption {
  const _ScheduleDayOption(this.label, this.weekdayIndex);

  final String label;
  final int weekdayIndex;
}

const _scheduleDayOptions = [
  _ScheduleDayOption('Mon', DateTime.monday),
  _ScheduleDayOption('Tue', DateTime.tuesday),
  _ScheduleDayOption('Wed', DateTime.wednesday),
  _ScheduleDayOption('Thu', DateTime.thursday),
  _ScheduleDayOption('Fri', DateTime.friday),
  _ScheduleDayOption('Sat', DateTime.saturday),
  _ScheduleDayOption('Sun', DateTime.sunday),
];

const _headerTitleStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 20,
  fontWeight: FontWeight.w800,
);

const _heroLabelStyle = TextStyle(
  color: RuniacColors.accentOrange,
  fontSize: 12,
  fontWeight: FontWeight.w900,
  letterSpacing: 0,
);

const _planTitleStyle = TextStyle(
  color: RuniacColors.primaryBlue,
  fontSize: 26,
  fontWeight: FontWeight.w900,
  letterSpacing: 0,
);

const _sectionTitleStyle = TextStyle(
  color: RuniacColors.primaryBlue,
  fontSize: 18,
  fontWeight: FontWeight.w800,
);

const _bodyStrongStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 14,
  fontWeight: FontWeight.w800,
);

const _bodyStyle = TextStyle(
  color: RuniacColors.textSecondary,
  fontSize: 14,
  height: 1.35,
  fontWeight: FontWeight.w600,
);

const _smallBodyStyle = TextStyle(
  color: RuniacColors.textSecondary,
  fontSize: 12,
  height: 1.35,
  fontWeight: FontWeight.w600,
);

const _metricLabel = TextStyle(
  color: RuniacColors.textSecondary,
  fontSize: 10,
  fontWeight: FontWeight.w700,
);

const _metricValue = TextStyle(
  color: RuniacColors.primaryBlue,
  fontSize: 15,
  fontWeight: FontWeight.w900,
);

const _startActionStyle = TextStyle(
  color: RuniacColors.white,
  fontSize: 16,
  fontWeight: FontWeight.w900,
);

const _sheetTitleStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 20,
  fontWeight: FontWeight.w900,
);

const _sheetMutedLabelStyle = TextStyle(
  color: RuniacColors.textSecondary,
  fontSize: 11,
  fontWeight: FontWeight.w800,
);

const _previewChipStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 12,
  fontWeight: FontWeight.w700,
);

const _disabledRowStyle = TextStyle(
  color: RuniacColors.textSecondary,
  fontSize: 13,
  fontWeight: FontWeight.w800,
);

const _timeWheelTextStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 24,
  fontWeight: FontWeight.w500,
);

const _disabledSaveActionStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w900,
);

const _closeActionStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w900);

final _softIconDecoration = BoxDecoration(
  color: const Color(0xFFF7FAFF),
  borderRadius: BorderRadius.circular(999),
  border: Border.all(color: RuniacColors.border),
);
