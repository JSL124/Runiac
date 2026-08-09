part of 'view_summary_screen.dart';

class _HeroDistance extends StatelessWidget {
  const _HeroDistance({required this.distanceKm});

  final String distanceKm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              distanceKm,
              style: const TextStyle(
                color: _rBlue,
                fontSize: 72,
                fontWeight: FontWeight.w800,
                letterSpacing: -2.8,
                height: 0.95,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'km',
              style: TextStyle(
                color: _rBlue75,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricSummary extends StatelessWidget {
  const _MetricSummary({required this.summary});

  final RunSummarySnapshot summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 18, 34, 0),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MetricText(
                      value: summary.avgPace,
                      label: 'Avg Pace',
                    ),
                  ),
                  Expanded(
                    child: _MetricText(value: summary.duration, label: 'Time'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _MetricText(
                      value: _metricValueWithUnit(summary.avgHeartRate, 'bpm'),
                      label: 'Avg Heart Rate',
                    ),
                  ),
                  Expanded(
                    child: _MetricText(
                      value: _metricValueWithUnit(summary.calories, 'kcal'),
                      label: 'Est. calories',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _metricValueWithUnit(String value, String unit) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized == '--') {
    return '--';
  }
  return '$normalized $unit';
}

class _MetricText extends StatelessWidget {
  const _MetricText({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _rBlue,
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _rBlue60,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
