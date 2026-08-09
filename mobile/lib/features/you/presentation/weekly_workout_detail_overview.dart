part of 'weekly_workout_detail_screen.dart';

class _NoOverscroll extends StatelessWidget {
  const _NoOverscroll({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: child,
    );
  }
}

class _WorkoutPlanIdentity extends StatelessWidget {
  const _WorkoutPlanIdentity(this.snapshot);

  final WeeklyWorkoutDetailSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_planIdentityLabel(snapshot.dayLabel), style: _heroLabelStyle),
          const SizedBox(height: 6),
          Text(snapshot.planTitle, style: _planTitleStyle),
        ],
      ),
    );
  }
}

String _planIdentityLabel(String label) {
  return switch (label) {
    'THURSDAY · EASY RUN' => 'Thursday · Easy Run',
    'SATURDAY · EASY RUN' => 'Saturday · Easy Run',
    _ => label,
  };
}

class _MetricSummaryCard extends StatelessWidget {
  const _MetricSummaryCard(this.metrics);

  final List<WorkoutMetricDisplay> metrics;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Row(
        children: [
          for (var index = 0; index < metrics.length; index++) ...[
            Expanded(
              flex: metrics[index].label == 'Suggested pace' ? 13 : 10,
              child: _MetricTile(metrics[index]),
            ),
            if (index < metrics.length - 1)
              const SizedBox(
                height: 72,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: RuniacColors.border,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(this.metric);

  final WorkoutMetricDisplay metric;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              metric.label,
              key: metric.label == 'Suggested pace'
                  ? const ValueKey('suggested_pace_metric_label')
                  : null,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: _metricLabel,
            ),
          ),
          const SizedBox(height: 6),
          Text(metric.value, textAlign: TextAlign.center, style: _metricValue),
        ],
      ),
    );
  }
}
