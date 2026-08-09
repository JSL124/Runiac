import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../run/domain/models/run_activity_display_model.dart';
import 'data/activity_history_demo_snapshots.dart';
import 'widgets/compact_run_activity_card.dart';
import 'widgets/you_surface_primitives.dart';

/// The full activity history, browsable by month.
///
/// History is paged by month rather than loaded whole — a year of running is a
/// lot of documents, and the month picker is what bounds each read.
///
/// The empty-filter state and the load-failure banner are deliberately
/// different widgets: "you did not run in March" and "we could not load March"
/// must not look the same to the runner.
class ActivityHistoryScreen extends StatefulWidget {
  const ActivityHistoryScreen({
    required this.activityHistoryMonths,
    required this.onBack,
    required this.onActivitySelected,
    this.loadFailed = false,
    this.onRetryLoad,
    super.key,
  });

  final List<ActivityHistoryMonth> activityHistoryMonths;
  final VoidCallback onBack;
  final ValueChanged<RunActivityDisplayModel> onActivitySelected;
  final bool loadFailed;
  final VoidCallback? onRetryLoad;

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  int? _selectedYear;
  int? _selectedMonth;

  static ({int year, int month})? _parseLabel(String label) {
    final parts = label.trim().split(' ');
    if (parts.length != 2) return null;
    final year = int.tryParse(parts[1]);
    final month = _monthNumber(parts[0]);
    if (year == null || month == null) return null;
    return (year: year, month: month);
  }

  static int? _monthNumber(String name) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final lower = name.toLowerCase();
    for (var i = 0; i < names.length; i++) {
      if (names[i].toLowerCase() == lower) return i + 1;
    }
    return null;
  }

  static String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }

  List<int> get _availableYears {
    final years = <int>{};
    for (final m in widget.activityHistoryMonths) {
      final parsed = _parseLabel(m.label);
      if (parsed != null) years.add(parsed.year);
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  List<int> get _availableMonths {
    final months = <int>{};
    for (final m in widget.activityHistoryMonths) {
      final parsed = _parseLabel(m.label);
      if (parsed == null) continue;
      if (_selectedYear != null && parsed.year != _selectedYear) continue;
      months.add(parsed.month);
    }
    return months.toList()..sort((a, b) => b.compareTo(a));
  }

  List<ActivityHistoryMonth> get _filteredMonths {
    if (_selectedYear == null && _selectedMonth == null) {
      return widget.activityHistoryMonths;
    }
    return widget.activityHistoryMonths.where((m) {
      final parsed = _parseLabel(m.label);
      if (parsed == null) {
        return false;
      }
      if (_selectedYear != null && parsed.year != _selectedYear) {
        return false;
      }
      if (_selectedMonth != null && parsed.month != _selectedMonth) {
        return false;
      }
      return true;
    }).toList();
  }

  String get _helperText {
    if (_selectedYear != null && _selectedMonth != null) {
      return 'Showing ${_monthName(_selectedMonth!)} $_selectedYear';
    }
    if (_selectedYear != null) {
      return 'Showing $_selectedYear';
    }
    if (_selectedMonth != null) {
      return 'Showing ${_monthName(_selectedMonth!)}';
    }
    return 'Showing all activities';
  }

  void _selectYear(BuildContext context) {
    final years = _availableYears;
    _showPicker(
      context,
      title: 'Filter by year',
      items: [
        _PickerItem(label: 'All years', value: null),
        for (final y in years) _PickerItem(label: '$y', value: y),
      ],
      selected: _selectedYear,
      onSelected: (value) {
        setState(() {
          _selectedYear = value as int?;
          // reset month if it no longer exists in the new year
          if (_selectedMonth != null &&
              !_availableMonths.contains(_selectedMonth)) {
            _selectedMonth = null;
          }
        });
      },
    );
  }

  void _selectMonth(BuildContext context) {
    final months = _availableMonths;
    _showPicker(
      context,
      title: 'Filter by month',
      items: [
        _PickerItem(label: 'All months', value: null),
        for (final m in months) _PickerItem(label: _monthName(m), value: m),
      ],
      selected: _selectedMonth,
      onSelected: (value) {
        setState(() => _selectedMonth = value as int?);
      },
    );
  }

  void _showPicker(
    BuildContext context, {
    required String title,
    required List<_PickerItem> items,
    required Object? selected,
    required ValueChanged<Object?> onSelected,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RuniacColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(title, style: _pickerTitleStyle),
              ),
              for (final item in items)
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    onSelected(item.value);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(item.label, style: _pickerItemStyle),
                        ),
                        if (item.value == selected)
                          const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: RuniacColors.primaryBlue,
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMonths;

    return ColoredBox(
      color: RuniacColors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'Activity History',
              tooltip: 'Back to You',
              onBack: widget.onBack,
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(overscroll: false),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FilterRow(
                        yearLabel: _selectedYear != null
                            ? '$_selectedYear'
                            : 'All years',
                        monthLabel: _selectedMonth != null
                            ? _monthName(_selectedMonth!)
                            : 'All months',
                        onYearTap: () => _selectYear(context),
                        onMonthTap: () => _selectMonth(context),
                      ),
                      const SizedBox(height: 10),
                      Text(_helperText, style: _helperTextStyle),
                      if (widget.loadFailed) ...[
                        const SizedBox(height: 10),
                        _LoadFailedBanner(onRetryLoad: widget.onRetryLoad),
                      ],
                      const SizedBox(height: 16),
                      if (filtered.isEmpty && !widget.loadFailed)
                        const _EmptyFilterState()
                      else
                        for (final month in filtered) ...[
                          _MonthHeader(month: month),
                          const SizedBox(height: 10),
                          for (final activity in month.activities) ...[
                            CompactRunActivityCard(
                              key: ValueKey(
                                'activity_history_card_${activity.identityKey}',
                              ),
                              activity: activity,
                              onTap: () => widget.onActivitySelected(activity),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 8),
                        ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerItem {
  const _PickerItem({required this.label, required this.value});
  final String label;
  final Object? value;
}

class _LoadFailedBanner extends StatelessWidget {
  const _LoadFailedBanner({this.onRetryLoad});

  final VoidCallback? onRetryLoad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'We could not load your activity history.',
              style: _helperTextStyle,
            ),
          ),
          if (onRetryLoad != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetryLoad,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Try again', style: _retryTextStyle),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyFilterState extends StatelessWidget {
  const _EmptyFilterState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          'No activities found for this filter.',
          style: _helperTextStyle,
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.yearLabel,
    required this.monthLabel,
    required this.onYearTap,
    required this.onMonthTap,
  });

  final String yearLabel;
  final String monthLabel;
  final VoidCallback onYearTap;
  final VoidCallback onMonthTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FilterPill(label: yearLabel, onTap: onYearTap),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FilterPill(label: monthLabel, onTap: onMonthTap),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: youPillDecoration(RuniacColors.white),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text(label, style: _filterTextStyle)),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: RuniacColors.primaryBlue,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month});

  final ActivityHistoryMonth month;

  @override
  Widget build(BuildContext context) {
    final runLabel = month.activities.length == 1 ? 'run' : 'runs';

    return Row(
      children: [
        Expanded(child: Text(month.label, style: _monthTitleStyle)),
        Text('${month.activities.length} $runLabel', style: _helperTextStyle),
      ],
    );
  }
}


const _filterTextStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 13,
  fontWeight: FontWeight.w800,
);
const _helperTextStyle = TextStyle(
  color: RuniacColors.textSecondary,
  fontSize: 12,
  fontWeight: FontWeight.w600,
);
const _retryTextStyle = TextStyle(
  color: RuniacColors.primaryBlue,
  fontSize: 13,
  fontWeight: FontWeight.w800,
);
const _monthTitleStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 16,
  fontWeight: FontWeight.w900,
);
const _pickerTitleStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 15,
  fontWeight: FontWeight.w900,
);
const _pickerItemStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 14,
  fontWeight: FontWeight.w600,
);
