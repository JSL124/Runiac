import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../data/home_dashboard_demo_snapshots.dart';

const _successGreen = Color(0xFF0F9F52);
const _softOrange = Color(0xFFFFF4DF);
const _starOrange = Color(0xFFF6A800);

/// The progress block on Home: weekly goal, streak and the supporting metric
/// cards.
///
/// This is the runner's at-a-glance answer to "am I on track this week", so the
/// goal bar is the emphasis and everything else supports it. Progress beyond
/// 100% is clamped for the bar but still stated in the label — overshooting a
/// weekly goal should read as a win, not as a full bar with no explanation.
class HomeProgressInsightSection extends StatelessWidget {
  const HomeProgressInsightSection({
    super.key,
    this.snapshot = homeDashboardDemoSnapshot,
  });

  final HomeDashboardDemoSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GoalProgressCard(goal: snapshot.goal),
        const SizedBox(height: 10),
        _MetricCardsRow(streak: snapshot.streak, xp: snapshot.xp),
        const SizedBox(height: 10),
        _AdvancedInsightCard(insight: snapshot.insight),
      ],
    );
  }
}

class _GoalProgressCard extends StatelessWidget {
  const _GoalProgressCard({required this.goal});

  final HomeGoalProgressDemoSnapshot goal;

  @override
  Widget build(BuildContext context) {
    return _HomeDividerSection(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 16),
      child: _GoalProgressBlock(goal: goal),
    );
  }
}

class _GoalProgressBlock extends StatelessWidget {
  const _GoalProgressBlock({required this.goal});

  final HomeGoalProgressDemoSnapshot goal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            goal.title,
            maxLines: 1,
            style: const TextStyle(
              color: RuniacColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.12,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          goal.weekLabel,
          style: const TextStyle(
            color: RuniacColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        _GoalProgressBar(label: goal.progressLabel),
        const SizedBox(height: 18),
        Row(
          children: [
            _IconTile(
              icon: Icons.flag_rounded,
              background: RuniacColors.sectionSurfaceStrong,
              color: RuniacColors.primaryBlue,
              size: 54,
              iconSize: 29,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal.milestoneLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RuniacColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    goal.milestoneValue,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GoalProgressBar extends StatelessWidget {
  const _GoalProgressBar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fillWidth = math.max(64.0, width * 0.76);

        return SizedBox(
          height: 18,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: RuniacColors.sectionSurfaceStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: fillWidth,
                  height: 18,
                  decoration: BoxDecoration(
                    color: RuniacColors.primaryBlue,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: RuniacColors.primaryBlue.withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: math.max(4, width - fillWidth + 6),
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
              const Positioned(
                right: 6,
                top: -1,
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFFB9C8FF),
                  size: 21,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCardsRow extends StatelessWidget {
  const _MetricCardsRow({required this.streak, required this.xp});

  final HomeMetricDemoSnapshot streak;
  final HomeMetricDemoSnapshot xp;

  @override
  Widget build(BuildContext context) {
    return _HomeDividerSection(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 15),
      child: Row(
        children: [
          Expanded(
            child: _MetricBlock(
              metric: streak,
              icon: Icons.local_fire_department_rounded,
              iconColor: RuniacColors.primaryBlue,
              iconBackground: RuniacColors.sectionSurfaceStrong,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: _VerticalDivider(height: 76),
          ),
          Expanded(
            child: _MetricBlock(
              metric: xp,
              icon: Icons.star_rounded,
              iconColor: _starOrange,
              iconBackground: _softOrange,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.metric,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
  });

  final HomeMetricDemoSnapshot metric;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Row(
        children: [
          _IconTile(
            icon: icon,
            background: iconBackground,
            color: iconColor,
            size: 48,
            iconSize: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 18,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      metric.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 25,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      metric.value,
                      maxLines: 1,
                      style: const TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 16,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      metric.caption,
                      maxLines: 1,
                      style: const TextStyle(
                        color: RuniacColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedInsightCard extends StatelessWidget {
  const _AdvancedInsightCard({required this.insight});

  final HomeInsightDemoSnapshot insight;

  @override
  Widget build(BuildContext context) {
    return _HomeDividerSection(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackChart = constraints.maxWidth < 380;
          final rows = _InsightRows(insight: insight);
          final chart = _InsightChart(insight: insight);

          if (stackChart) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                rows,
                const SizedBox(height: 16),
                const Divider(color: RuniacColors.border, height: 1),
                const SizedBox(height: 12),
                chart,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: rows),
              const SizedBox(width: 14),
              const _VerticalDivider(height: 156),
              const SizedBox(width: 14),
              Expanded(flex: 5, child: chart),
            ],
          );
        },
      ),
    );
  }
}

class _InsightRows extends StatelessWidget {
  const _InsightRows({required this.insight});

  final HomeInsightDemoSnapshot insight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: RuniacColors.primaryBlue,
              size: 27,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  insight.title,
                  maxLines: 1,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.08,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        for (final row in insight.rows) _InsightRow(row: row),
      ],
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.row});

  final HomeInsightRowDemoSnapshot row;

  @override
  Widget build(BuildContext context) {
    final isBalanced = row.value == 'Balanced';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          _IconTile(
            icon: row.icon,
            background: RuniacColors.sectionSurfaceStrong,
            color: isBalanced ? const Color(0xFF2563EB) : _successGreen,
            size: 36,
            iconSize: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 5,
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                row.value,
                maxLines: 1,
                style: TextStyle(
                  color: isBalanced ? const Color(0xFF2563EB) : _successGreen,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.circle,
            size: 6,
            color: isBalanced ? const Color(0xFF2563EB) : _successGreen,
          ),
        ],
      ),
    );
  }
}

class _InsightChart extends StatelessWidget {
  const _InsightChart({required this.insight});

  final HomeInsightDemoSnapshot insight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 156,
      child: CustomPaint(
        painter: _InsightLineChartPainter(
          labels: insight.chartLabels,
          values: insight.chartValues,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _HomeDividerSection extends StatelessWidget {
  const _HomeDividerSection({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RuniacColors.white,
        border: Border.symmetric(
          horizontal: BorderSide(color: RuniacColors.border),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.background,
    required this.color,
    required this.size,
    required this.iconSize,
  });

  final IconData icon;
  final Color background;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider({this.height});

  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      color: RuniacColors.border.withValues(alpha: 0.7),
    );
  }
}

class _InsightLineChartPainter extends CustomPainter {
  const _InsightLineChartPainter({required this.labels, required this.values});

  final List<String> labels;
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    const leftInset = 28.0;
    const bottomInset = 22.0;
    const topInset = 8.0;
    const rightInset = 4.0;
    final chartRect = Rect.fromLTWH(
      leftInset,
      topInset,
      math.max(0, size.width - leftInset - rightInset),
      math.max(0, size.height - topInset - bottomInset),
    );
    if (chartRect.width <= 0 || chartRect.height <= 0 || values.isEmpty) {
      return;
    }

    final gridPaint = Paint()
      ..color = RuniacColors.border.withValues(alpha: 0.68)
      ..strokeWidth = 1;
    final axisTextStyle = TextStyle(
      color: RuniacColors.textSecondary.withValues(alpha: 0.66),
      fontSize: 9,
      fontWeight: FontWeight.w700,
    );
    const yLabels = ['8:00', '7:30', '7:00', '6:30'];
    for (var i = 0; i < yLabels.length; i += 1) {
      final y = chartRect.top + chartRect.height * i / (yLabels.length - 1);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
      _paintText(
        canvas,
        yLabels[i],
        Offset(0, y - 6),
        axisTextStyle,
        maxWidth: leftInset - 4,
      );
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i += 1) {
      final x = chartRect.left + chartRect.width * i / (values.length - 1);
      final normalized = values[i].clamp(0.0, 1.0);
      final y = chartRect.bottom - chartRect.height * normalized;
      points.add(Offset(x, y));
    }

    final areaPath = Path()..moveTo(points.first.dx, chartRect.bottom);
    for (final point in points) {
      areaPath.lineTo(point.dx, point.dy);
    }
    areaPath
      ..lineTo(points.last.dx, chartRect.bottom)
      ..close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            RuniacColors.primaryBlue.withValues(alpha: 0.18),
            RuniacColors.primaryBlue.withValues(alpha: 0.04),
          ],
        ).createShader(chartRect),
    );

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i += 1) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = RuniacColors.primaryBlue
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    final last = points.last;
    canvas.drawCircle(last, 8, Paint()..color = RuniacColors.white);
    canvas.drawCircle(
      last,
      7,
      Paint()
        ..color = RuniacColors.primaryBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(last, 3.5, Paint()..color = RuniacColors.primaryBlue);

    for (var i = 0; i < labels.length; i += 1) {
      final x = chartRect.left + chartRect.width * i / (labels.length - 1);
      _paintText(
        canvas,
        labels[i],
        Offset(x - 18, chartRect.bottom + 8),
        axisTextStyle,
        maxWidth: 38,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String value,
    Offset offset,
    TextStyle style, {
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _InsightLineChartPainter oldDelegate) {
    return oldDelegate.labels != labels || oldDelegate.values != values;
  }
}
