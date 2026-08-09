import 'package:flutter/material.dart';

import '../../data/advanced_analysis_demo_snapshots.dart';
import 'advanced_analysis_theme.dart';

/// The reusable building blocks of the Advanced Analysis screen — stat grid,
/// section headings, chart panel and interpretation row.
///
/// Every section on that screen is assembled from these, which is what keeps
/// pace, elevation and cadence looking like one screen rather than three. A
/// stat tile renders its own unavailable state, so a section never has to
/// decide whether it has enough data to draw a tile at all.
class AdvancedAnalysisStatGrid extends StatelessWidget {
  const AdvancedAnalysisStatGrid({
    super.key,
    required this.stats,
    this.plain = false,
  });

  final List<AdvancedAnalysisStatData> stats;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    if (plain) {
      return Column(
        children: [
          for (var i = 0; i < stats.length; i += 2) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _AdvancedAnalysisStatTile(stat: stats[i], plain: true),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: i + 1 < stats.length
                      ? _AdvancedAnalysisStatTile(
                          stat: stats[i + 1],
                          plain: true,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            if (i + 2 < stats.length) const SizedBox(height: 18),
          ],
        ],
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.72,
      crossAxisSpacing: 9,
      mainAxisSpacing: 9,
      children: [
        for (final stat in stats)
          _AdvancedAnalysisStatTile(stat: stat, plain: plain),
      ],
    );
  }
}

class AdvancedAnalysisSubhead extends StatelessWidget {
  const AdvancedAnalysisSubhead(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: advancedAnalysisBlue45,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }
}

class AdvancedAnalysisChartPanel extends StatelessWidget {
  const AdvancedAnalysisChartPanel({
    super.key,
    required this.height,
    required this.painter,
    this.plain = false,
  });

  final double height;
  final CustomPainter painter;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    if (plain) {
      return SizedBox(
        height: height,
        child: CustomPaint(painter: painter, child: const SizedBox.expand()),
      );
    }

    return Container(
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: advancedAnalysisSurface,
        border: Border.all(color: advancedAnalysisBlue10, width: 1.2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: CustomPaint(painter: painter, child: const SizedBox.expand()),
    );
  }
}

class AdvancedAnalysisInterpretationRow extends StatelessWidget {
  const AdvancedAnalysisInterpretationRow({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: advancedAnalysisBlue10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.chat_bubble_outline_rounded,
            color: advancedAnalysisBlue45,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: advancedAnalysisBlue75,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedAnalysisStatTile extends StatelessWidget {
  const _AdvancedAnalysisStatTile({required this.stat, required this.plain});

  final AdvancedAnalysisStatData stat;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final color = stat.hot ? advancedAnalysisOrange : advancedAnalysisInk;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          stat.label.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: advancedAnalysisBlue45,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                stat.value,
                style: TextStyle(
                  color: color,
                  fontSize: stat.value.length > 8 ? 18 : 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              if (stat.unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  stat.unit,
                  style: TextStyle(
                    color: stat.hot
                        ? advancedAnalysisOrange
                        : advancedAnalysisBlue45,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    if (plain) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: content,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 10, 10),
      decoration: BoxDecoration(
        color: stat.hot ? advancedAnalysisOrange08 : advancedAnalysisSurface,
        border: Border.all(
          color: stat.hot ? advancedAnalysisOrange16 : advancedAnalysisBlue10,
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: content,
    );
  }
}
