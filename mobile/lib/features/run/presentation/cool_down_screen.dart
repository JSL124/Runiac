import 'package:flutter/material.dart';

import 'package:runiac_app/core/assets/runiac_assets.dart';
import 'package:runiac_app/core/theme/runiac_colors.dart';

import '../domain/models/complete_run_result.dart';
import '../domain/models/local_run_completion_payload.dart';
import '../domain/repositories/run_repository.dart';
import 'cool_down_guide_screen.dart';
import 'models/stretch_exercise.dart';
import 'view_summary_screen.dart';

const _rBlue = Color(0xFF2F51C8);
const _rOrange = Color(0xFFFB6414);
const _rWhite = Color(0xFFF8FAFF);
const _rBlue75 = Color(0xBF2F51C8);
const _rBlue60 = Color(0x992F51C8);
const _rBlue45 = Color(0x732F51C8);
const _rBlue30 = Color(0x4D2F51C8);
const _rBlue10 = Color(0x1A2F51C8);
const _rBlue06 = Color(0x0F2F51C8);

/// The optional guided cool-down offered between finishing a run and the
/// summary.
///
/// Sits in the flow rather than beside it — a beginner audience is the reason
/// the app suggests a walk and stretches instead of jumping straight to the
/// numbers. Skipping goes directly to [ViewSummaryScreen], so nothing here may
/// be load-bearing for run completion; the run is already saved by the time
/// this screen appears.
class CoolDownScreen extends StatelessWidget {
  const CoolDownScreen({
    super.key,
    this.completionResult,
    this.completionPayload,
    this.repository,
  });

  final CompleteRunResult? completionResult;
  final LocalRunCompletionPayload? completionPayload;
  final RunRepository? repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = _CoolDownLayout.fromHeight(constraints.maxHeight);

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(layout: layout),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          layout.horizontalPadding,
                          0,
                          layout.horizontalPadding,
                          layout.bottomPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Great job! Now let’s cool down and stretch.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _rBlue,
                                fontSize: layout.messageSize,
                                fontWeight: FontWeight.w600,
                                height: 1.32,
                                letterSpacing: -0.3,
                              ),
                            ),
                            _IllustrationSlot(layout: layout),
                            _WhyCoolDownCard(layout: layout),
                            SizedBox(height: layout.activityTopGap),
                            _ActivityListCard(layout: layout),
                            SizedBox(height: layout.actionTopGap),
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) => CoolDownGuideScreen(
                                      completionResult: completionResult,
                                      completionPayload: completionPayload,
                                      repository: repository,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Start Cool-down'),
                              style: FilledButton.styleFrom(
                                backgroundColor: _rOrange,
                                foregroundColor: _rWhite,
                                minimumSize: Size.fromHeight(
                                  layout.primaryHeight,
                                ),
                                elevation: 8,
                                shadowColor: const Color(0x4DFB6414),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: TextStyle(
                                  fontSize: layout.primaryTextSize,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            SizedBox(height: layout.buttonGap),
                            OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) => ViewSummaryScreen(
                                      completionResult: completionResult,
                                      completionPayload: completionPayload,
                                    ),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: _rBlue,
                                side: const BorderSide(
                                  color: _rBlue30,
                                  width: 1.5,
                                ),
                                minimumSize: Size.fromHeight(
                                  layout.secondaryHeight,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: TextStyle(
                                  fontSize: layout.secondaryTextSize,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              child: const Text('Skip to Summary'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CoolDownLayout {
  const _CoolDownLayout({
    required this.horizontalPadding,
    required this.bottomPadding,
    required this.headerHeight,
    required this.titleSize,
    required this.messageSize,
    required this.illustrationVerticalPadding,
    required this.illustrationMaxHeight,
    required this.illustrationMinHeight,
    required this.cardPadding,
    required this.whyTitleSize,
    required this.whyBodySize,
    required this.activityTopGap,
    required this.activityRowPadding,
    required this.activityIconSize,
    required this.activityTitleSize,
    required this.activityMetaSize,
    required this.actionTopGap,
    required this.primaryHeight,
    required this.secondaryHeight,
    required this.buttonGap,
    required this.primaryTextSize,
    required this.secondaryTextSize,
  });

  factory _CoolDownLayout.fromHeight(double height) {
    if (height < 700) {
      return const _CoolDownLayout(
        horizontalPadding: 18,
        bottomPadding: 10,
        headerHeight: 48,
        titleSize: 16,
        messageSize: 15,
        illustrationVerticalPadding: 4,
        illustrationMaxHeight: 126,
        illustrationMinHeight: 78,
        cardPadding: 11,
        whyTitleSize: 13.5,
        whyBodySize: 12,
        activityTopGap: 8,
        activityRowPadding: 8,
        activityIconSize: 34,
        activityTitleSize: 13.5,
        activityMetaSize: 12,
        actionTopGap: 10,
        primaryHeight: 44,
        secondaryHeight: 40,
        buttonGap: 7,
        primaryTextSize: 15,
        secondaryTextSize: 14,
      );
    }

    if (height < 730) {
      return const _CoolDownLayout(
        horizontalPadding: 20,
        bottomPadding: 16,
        headerHeight: 52,
        titleSize: 16.5,
        messageSize: 16.5,
        illustrationVerticalPadding: 5,
        illustrationMaxHeight: 158,
        illustrationMinHeight: 100,
        cardPadding: 14,
        whyTitleSize: 14,
        whyBodySize: 12.5,
        activityTopGap: 10,
        activityRowPadding: 10,
        activityIconSize: 38,
        activityTitleSize: 14.5,
        activityMetaSize: 12.5,
        actionTopGap: 12,
        primaryHeight: 50,
        secondaryHeight: 45,
        buttonGap: 9,
        primaryTextSize: 15.5,
        secondaryTextSize: 14.5,
      );
    }

    return const _CoolDownLayout(
      horizontalPadding: 20,
      bottomPadding: 22,
      headerHeight: 56,
      titleSize: 17,
      messageSize: 18,
      illustrationVerticalPadding: 6,
      illustrationMaxHeight: 200,
      illustrationMinHeight: 120,
      cardPadding: 16,
      whyTitleSize: 14.5,
      whyBodySize: 13,
      activityTopGap: 12,
      activityRowPadding: 12,
      activityIconSize: 40,
      activityTitleSize: 15,
      activityMetaSize: 12.5,
      actionTopGap: 14,
      primaryHeight: 56,
      secondaryHeight: 50,
      buttonGap: 10,
      primaryTextSize: 16,
      secondaryTextSize: 15,
    );
  }

  final double horizontalPadding;
  final double bottomPadding;
  final double headerHeight;
  final double titleSize;
  final double messageSize;
  final double illustrationVerticalPadding;
  final double illustrationMaxHeight;
  final double illustrationMinHeight;
  final double cardPadding;
  final double whyTitleSize;
  final double whyBodySize;
  final double activityTopGap;
  final double activityRowPadding;
  final double activityIconSize;
  final double activityTitleSize;
  final double activityMetaSize;
  final double actionTopGap;
  final double primaryHeight;
  final double secondaryHeight;
  final double buttonGap;
  final double primaryTextSize;
  final double secondaryTextSize;
}

class _Header extends StatelessWidget {
  const _Header({required this.layout});

  final _CoolDownLayout layout;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: layout.headerHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              style: IconButton.styleFrom(
                foregroundColor: _rBlue45,
                minimumSize: const Size(40, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.chevron_left_rounded, size: 30),
            ),
            Expanded(
              child: Text(
                'Cool down',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _rBlue,
                  fontSize: layout.titleSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

class _IllustrationSlot extends StatelessWidget {
  const _IllustrationSlot({required this.layout});

  final _CoolDownLayout layout;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: layout.illustrationVerticalPadding,
        ),
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;
              final height = availableHeight
                  .clamp(0, layout.illustrationMaxHeight)
                  .toDouble();
              final effectiveHeight = height < layout.illustrationMinHeight
                  ? height
                  : height.clamp(
                      layout.illustrationMinHeight,
                      layout.illustrationMaxHeight,
                    );
              final trainerSize = (effectiveHeight * 1.2)
                  .clamp(180, 240)
                  .toDouble();

              return Semantics(
                label: 'Stretching trainer waiting animation',
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: effectiveHeight),
                    child: Center(
                      child: Image(
                        image: const AssetImage(
                          RuniacAssets.stretchingTrainerIdle,
                        ),
                        width: trainerSize,
                        height: trainerSize,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WhyCoolDownCard extends StatelessWidget {
  const _WhyCoolDownCard({required this.layout});

  final _CoolDownLayout layout;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _rBlue06,
        border: Border.all(color: _rBlue10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: EdgeInsets.all(layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _rWhite,
                    border: Border.all(color: _rBlue10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.favorite_border_rounded,
                    color: _rBlue,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  'Why cool-down?',
                  style: TextStyle(
                    color: _rBlue,
                    fontSize: layout.whyTitleSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              'A gentle cool-down helps your heart rate settle and can reduce muscle soreness.',
              style: TextStyle(
                color: _rBlue75,
                fontSize: layout.whyBodySize,
                fontWeight: FontWeight.w500,
                height: 1.5,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityListCard extends StatelessWidget {
  const _ActivityListCard({required this.layout});

  final _CoolDownLayout layout;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _rWhite,
        border: Border.all(color: _rBlue10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            _CoolDownActivityRow(
              icon: Icons.directions_walk_rounded,
              title: 'Slow Walk',
              meta: '3-5 min',
              layout: layout,
            ),
            const Divider(height: 1, color: _rBlue10),
            _CoolDownActivityRow(
              icon: Icons.self_improvement,
              title: 'Stretching',
              meta: '~${(stretchTotalSeconds / 60).ceil()} min · ${stretchExercises.length} exercises',
              layout: layout,
            ),
          ],
        ),
      ),
    );
  }
}

class _CoolDownActivityRow extends StatelessWidget {
  const _CoolDownActivityRow({
    required this.icon,
    required this.title,
    required this.meta,
    required this.layout,
  });

  final IconData icon;
  final String title;
  final String meta;
  final _CoolDownLayout layout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: layout.activityRowPadding,
      ),
      child: Row(
        children: [
          Container(
            width: layout.activityIconSize,
            height: layout.activityIconSize,
            decoration: BoxDecoration(
              color: _rBlue06,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: _rBlue, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _rBlue,
                    fontSize: layout.activityTitleSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _rBlue60,
                    fontSize: layout.activityMetaSize,
                    fontWeight: FontWeight.w600,
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
