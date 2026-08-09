import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../domain/models/paywall_config_read_model.dart';

/// The paywall feature list with a looping sequential highlight: item 1 →
/// 2 → … → last → back to 1, one item emphasised per interval tick.
///
/// With reduced motion enabled no timer is scheduled and every row renders
/// statically, so `pumpAndSettle`-based tests always settle.
class PaywallFeatureList extends StatefulWidget {
  const PaywallFeatureList({
    required this.features,
    required this.highlightIntervalMs,
    super.key,
  });

  final List<PaywallFeatureItem> features;
  final int highlightIntervalMs;

  @override
  State<PaywallFeatureList> createState() => _PaywallFeatureListState();
}

class _PaywallFeatureListState extends State<PaywallFeatureList> {
  Timer? _highlightTimer;
  var _highlightIndex = 0;
  var _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion && _highlightTimer != null) {
      return;
    }
    _reduceMotion = reduceMotion;
    _syncHighlightTimer();
  }

  @override
  void didUpdateWidget(covariant PaywallFeatureList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightIntervalMs != widget.highlightIntervalMs ||
        oldWidget.features.length != widget.features.length) {
      _highlightIndex = 0;
      _syncHighlightTimer();
    }
  }

  void _syncHighlightTimer() {
    _highlightTimer?.cancel();
    _highlightTimer = null;
    if (_reduceMotion || widget.features.length < 2) {
      return;
    }
    _highlightTimer = Timer.periodic(
      Duration(milliseconds: widget.highlightIntervalMs),
      (_) {
        setState(() {
          _highlightIndex = (_highlightIndex + 1) % widget.features.length;
        });
      },
    );
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.features.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          _PaywallFeatureRow(
            key: Key('paywall-feature-$i'),
            feature: widget.features[i],
            highlighted: !_reduceMotion && i == _highlightIndex,
          ),
        ],
      ],
    );
  }
}

class _PaywallFeatureRow extends StatelessWidget {
  const _PaywallFeatureRow({
    required this.feature,
    required this.highlighted,
    super.key,
  });

  final PaywallFeatureItem feature;
  final bool highlighted;

  static const _emphasisDuration = Duration(milliseconds: 350);

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: highlighted ? 1.04 : 1.0,
      duration: _emphasisDuration,
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: _emphasisDuration,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: highlighted
              ? RuniacColors.primaryBlue.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: _emphasisDuration,
              curve: Curves.easeOut,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: highlighted
                    ? RuniacColors.primaryBlue
                    : RuniacColors.primaryBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 15,
                color: highlighted
                    ? RuniacColors.white
                    : RuniacColors.primaryBlue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      feature.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: highlighted
                            ? RuniacColors.primaryBlue
                            : RuniacColors.textPrimary,
                      ),
                    ),
                  ),
                  if (feature.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      feature.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: RuniacColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
