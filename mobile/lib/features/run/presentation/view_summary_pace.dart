part of 'view_summary_screen.dart';

/// The pace graph card on the run summary.
///
/// Split out of `view_summary_screen.dart` as a `part` purely to keep that file
/// readable — these widgets are private to the summary and are not meant to be
/// reused elsewhere.
///
/// The card has a guard state: when the run is too short to say anything about
/// pace, or the graph came back unavailable, it shows the explanation instead
/// of an empty chart frame.
class _PaceSection extends StatelessWidget {
  const _PaceSection({
    required this.hasSufficientData,
    required this.paceGraph,
  });

  final bool hasSufficientData;
  final PaceGraphSnapshot paceGraph;

  @override
  Widget build(BuildContext context) {
    final showGuard = !hasSufficientData || !paceGraph.isAvailable;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel(title: 'Pace Over Time'),
          _CardSurface(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: _GuardedAnalysisPreview(
              showGuard: showGuard,
              clipContent: false,
              child: _PaceChart(graph: paceGraph),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaceChart extends StatelessWidget {
  const _PaceChart({required this.graph});

  final PaceGraphSnapshot graph;

  @override
  Widget build(BuildContext context) {
    final renderedGraph = graph.isAvailable ? graph : _lockedPaceGraphPreview;
    final isLockedPreview = !graph.isAvailable;
    final yAxisLabels = isLockedPreview
        ? _lockedPaceGraphPreview.yAxisLabels
        : graph.yAxisLabels;
    final xAxisLabels = isLockedPreview
        ? _lockedPaceGraphPreview.xAxisLabels
        : graph.xAxisLabels;

    return Column(
      children: [
        SizedBox(
          height: 96,
          child: Row(
            children: [
              SizedBox(
                width: _paceChartYAxisWidth,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: yAxisLabels
                      .map((label) => _YAxisLabel(label))
                      .toList(),
                ),
              ),
              const SizedBox(width: _paceChartAxisGap),
              Expanded(
                child: CustomPaint(
                  painter: _PaceChartPainter(
                    graph: renderedGraph,
                    isLockedPreview: isLockedPreview,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: _paceChartYAxisWidth),
            const SizedBox(width: _paceChartAxisGap),
            Expanded(child: _PaceXAxisLabels(labels: xAxisLabels)),
          ],
        ),
      ],
    );
  }
}

const _lockedPaceGraphPreview = PaceGraphSnapshot(
  isAvailable: true,
  points: [
    PaceGraphPoint(
      elapsedSeconds: 0,
      progressFraction: 0,
      paceSecondsPerKm: 500,
    ),
    PaceGraphPoint(
      elapsedSeconds: 300,
      progressFraction: 0.24,
      paceSecondsPerKm: 472,
    ),
    PaceGraphPoint(
      elapsedSeconds: 600,
      progressFraction: 0.5,
      paceSecondsPerKm: 486,
    ),
    PaceGraphPoint(
      elapsedSeconds: 900,
      progressFraction: 0.76,
      paceSecondsPerKm: 448,
    ),
    PaceGraphPoint(
      elapsedSeconds: 1200,
      progressFraction: 1,
      paceSecondsPerKm: 460,
    ),
  ],
  yAxisLabels: ['6:00', '7:00', '8:00'],
  xAxisLabels: ['0:00', '5:00', '10:00'],
  paceRangeMinSecondsPerKm: 420,
  paceRangeMaxSecondsPerKm: 520,
);

class _PaceXAxisLabels extends StatelessWidget {
  const _PaceXAxisLabels({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (labels.isEmpty) {
            return const SizedBox.shrink();
          }

          final availableWidth = constraints.maxWidth;
          final horizontalInset =
              availableWidth > (_paceChartHorizontalPlotInset * 2)
              ? _paceChartHorizontalPlotInset
              : 0.0;
          final plotLeft = horizontalInset;
          final plotRight = availableWidth - horizontalInset;
          final plotWidth = (plotRight - plotLeft).clamp(0.0, double.infinity);
          final divisor = labels.length == 1 ? 1 : labels.length - 1;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (var index = 0; index < labels.length; index += 1)
                Positioned(
                  key: ValueKey('pace_x_axis_label_$index'),
                  left:
                      (plotLeft +
                              (plotWidth * (index / divisor)) -
                              (_paceChartXAxisLabelWidth / 2))
                          .clamp(
                            0.0,
                            (availableWidth - _paceChartXAxisLabelWidth).clamp(
                              0.0,
                              double.infinity,
                            ),
                          )
                          .toDouble(),
                  width: _paceChartXAxisLabelWidth,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _AxisLabel(labels[index]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      style: const TextStyle(
        color: _rBlue45,
        fontSize: 9,
        fontWeight: FontWeight.w600,
        height: 0.95,
      ),
    );
  }
}

class _YAxisLabel extends StatelessWidget {
  const _YAxisLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _paceChartYAxisWidth,
      child: Align(
        alignment: Alignment.centerRight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: _AxisLabel(text),
        ),
      ),
    );
  }
}
