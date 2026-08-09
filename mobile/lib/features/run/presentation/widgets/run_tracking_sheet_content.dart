import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../settings/domain/distance_unit_format.dart';
import '../../../settings/domain/models/app_settings.dart';
import '../../domain/models/run_tracking_snapshot.dart';
import '../../domain/models/run_tracking_startup_readiness.dart';
import '../../domain/models/run_tracking_state.dart';
import '../models/planned_run_context.dart';

const _panelTextBlue = Color(0xFF3151C8);
const _sportOrange = Color(0xFFFF7A1A);
const _mutedBlue = Color(0xFF8296E8);
const _blueBorder = Color(0xFFDCE6FF);
const _actionAnimationDuration = Duration(milliseconds: 220);

class RunTrackingSheetContent extends StatelessWidget {
  const RunTrackingSheetContent({
    super.key,
    required this.state,
    required this.onPause,
    required this.onResume,
    required this.onEnd,
    this.plannedWorkout,
    this.isCompletingRun = false,
    this.distanceUnit = DistanceUnit.kilometers,
  });

  final RunTrackingState state;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onEnd;
  final PlannedRunContext? plannedWorkout;
  final bool isCompletingRun;
  final DistanceUnit distanceUnit;

  @override
  Widget build(BuildContext context) {
    final snapshot = RunTrackingSnapshot.fromState(state);
    final progress = _RunPlanProgressDisplay.from(
      state: state,
      snapshot: snapshot,
      plannedWorkout: plannedWorkout,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (progress != null) ...[
              _ProgressSummaryRow(progress: progress),
              const SizedBox(height: 8),
              _RunProgressBar(progress: progress.value),
              SizedBox(height: compact ? 16 : 18),
            ],
            _PrimaryMetricFocus(
              progress: progress,
              snapshot: snapshot,
              distanceUnit: distanceUnit,
            ),
            SizedBox(height: compact ? 14 : 16),
            const Divider(height: 1, color: _blueBorder),
            SizedBox(height: compact ? 12 : 14),
            _SecondaryMetricRow(
              snapshot: snapshot,
              state: state,
              distanceUnit: distanceUnit,
            ),
            if (state.isAbnormalPaused) ...[
              SizedBox(height: compact ? 12 : 14),
              _AbnormalMovementWarning(message: snapshot.guidance),
            ],
            SizedBox(height: compact ? 14 : 18),
            _RunActiveActions(
              isPaused:
                  state.isPaused ||
                  state.isAutoPaused ||
                  state.isAbnormalPaused,
              onPause: onPause,
              onResume: onResume,
              onEnd: onEnd,
              isCompletingRun: isCompletingRun,
            ),
          ],
        );
      },
    );
  }
}

class _RunPlanProgressDisplay {
  const _RunPlanProgressDisplay({
    required this.label,
    required this.percentLabel,
    required this.value,
  });

  factory _RunPlanProgressDisplay.distance({
    required RunTrackingState state,
    required RunTrackingSnapshot snapshot,
    int targetDistanceMeters = 4500,
  }) {
    final progress = (state.distanceMeters / targetDistanceMeters).clamp(
      0.0,
      1.0,
    );
    final targetLabel = _formatDistanceTarget(targetDistanceMeters);
    return _RunPlanProgressDisplay(
      label: '${snapshot.distanceValueLabel} of $targetLabel km',
      percentLabel: '${(progress * 100).round()}%',
      value: progress,
    );
  }

  factory _RunPlanProgressDisplay.duration({
    required RunTrackingState state,
    required RunTrackingSnapshot snapshot,
    required int targetDurationSeconds,
  }) {
    final progress = targetDurationSeconds <= 0
        ? 0.0
        : (state.elapsedSeconds / targetDurationSeconds).clamp(0.0, 1.0);
    return _RunPlanProgressDisplay(
      label:
          '${snapshot.elapsedTimeLabel} of ${_formatDurationTarget(targetDurationSeconds)}',
      percentLabel: '${(progress * 100).round()}%',
      value: progress,
    );
  }

  static _RunPlanProgressDisplay? from({
    required RunTrackingState state,
    required RunTrackingSnapshot snapshot,
    required PlannedRunContext? plannedWorkout,
  }) {
    final planned = plannedWorkout;
    if (planned == null) {
      return _RunPlanProgressDisplay.distance(state: state, snapshot: snapshot);
    }

    return switch (planned.objectiveKind) {
      PlannedRunObjectiveKind.distance => _RunPlanProgressDisplay.distance(
        state: state,
        snapshot: snapshot,
        targetDistanceMeters: planned.targetDistanceMeters ?? 4500,
      ),
      PlannedRunObjectiveKind.duration => _RunPlanProgressDisplay.duration(
        state: state,
        snapshot: snapshot,
        targetDurationSeconds: planned.targetDurationSeconds,
      ),
      PlannedRunObjectiveKind.restDay => null,
    };
  }

  final String label;
  final String percentLabel;
  final double value;
}

class _ProgressSummaryRow extends StatelessWidget {
  const _ProgressSummaryRow({required this.progress});

  final _RunPlanProgressDisplay progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            progress.label,
            style: const TextStyle(
              color: _mutedBlue,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          progress.percentLabel,
          style: const TextStyle(
            color: _panelTextBlue,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _RunProgressBar extends StatelessWidget {
  const _RunProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        key: const Key('run_plan_progress_bar'),
        value: progress,
        minHeight: 8,
        backgroundColor: const Color(0xFFE5EAFF),
        color: _sportOrange,
      ),
    );
  }
}

class _PrimaryMetricFocus extends StatelessWidget {
  const _PrimaryMetricFocus({
    required this.progress,
    required this.snapshot,
    this.distanceUnit = DistanceUnit.kilometers,
  });

  final _RunPlanProgressDisplay? progress;
  final RunTrackingSnapshot snapshot;
  final DistanceUnit distanceUnit;

  @override
  Widget build(BuildContext context) {
    const focusLabel = 'DISTANCE';
    final focusValue = distanceUnit == DistanceUnit.kilometers
        ? snapshot.distanceValueLabel
        : convertKilometers(
            double.parse(snapshot.distanceValueLabel),
            distanceUnit,
          ).toStringAsFixed(2);
    final focusUnit = distanceUnitLabel(distanceUnit);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            focusLabel,
            style: const TextStyle(
              color: _mutedBlue,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                focusValue,
                style: const TextStyle(
                  color: _panelTextBlue,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  height: 0.92,
                ),
              ),
              if (focusUnit.isNotEmpty) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    focusUnit,
                    style: const TextStyle(
                      color: _mutedBlue,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

String _formatDistanceTarget(int meters) {
  return (meters / 1000).toStringAsFixed(2);
}

String _formatDurationTarget(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainder.toString().padLeft(2, '0')}';
}

class _SecondaryMetricRow extends StatelessWidget {
  const _SecondaryMetricRow({
    required this.snapshot,
    required this.state,
    this.distanceUnit = DistanceUnit.kilometers,
  });

  final RunTrackingSnapshot snapshot;
  final RunTrackingState state;
  final DistanceUnit distanceUnit;

  @override
  Widget build(BuildContext context) {
    final currentPaceLabel = distanceUnit == DistanceUnit.kilometers
        ? snapshot.currentPaceLabel
        : _formatPaceForUnit(
            distanceMeters: state.distanceMeters,
            secondsPerKm: state.currentPaceSecondsPerKm,
            unit: distanceUnit,
          );

    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _MetricItem(label: 'TIME', value: snapshot.elapsedTimeLabel),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: _blueBorder),
          Expanded(
            child: _MetricItem(label: 'CURRENT PACE', value: currentPaceLabel),
          ),
        ],
      ),
    );
  }
}

/// Formats a pace-per-km value for the given [unit]. When [unit] is
/// kilometers this reproduces the exact formatting used by
/// [RunTrackingSnapshot] (same threshold, same `mm:ss/km` shape). For miles,
/// the underlying seconds-per-km is converted to seconds-per-mile before
/// formatting so the displayed number, not just the unit suffix, is correct.
String _formatPaceForUnit({
  required int distanceMeters,
  required int secondsPerKm,
  required DistanceUnit unit,
}) {
  final unitSuffix = paceUnitLabel(unit);
  if (distanceMeters < livePaceReadinessThresholdMeters) {
    return '--:--$unitSuffix';
  }
  if (secondsPerKm <= 0) {
    return '--:--$unitSuffix';
  }

  final secondsPerUnit = unit == DistanceUnit.kilometers
      ? secondsPerKm
      : (secondsPerKm / kilometersToMilesFactor).round();
  final minutes = secondsPerUnit ~/ 60;
  final seconds = secondsPerUnit % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}$unitSuffix';
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _mutedBlue,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              color: _panelTextBlue,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 0.95,
            ),
          ),
        ),
      ],
    );
  }
}

class _AbnormalMovementWarning extends StatelessWidget {
  const _AbnormalMovementWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: _panelTextBlue,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        height: 1.25,
        letterSpacing: 0,
      ),
    );
  }
}

class _RunActiveActions extends StatelessWidget {
  const _RunActiveActions({
    required this.isPaused,
    required this.onPause,
    required this.onResume,
    required this.onEnd,
    required this.isCompletingRun,
  });

  final bool isPaused;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onEnd;
  final bool isCompletingRun;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: AnimatedSwitcher(
        duration: _actionAnimationDuration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [...previousChildren, ?currentChild],
          );
        },
        transitionBuilder: (child, animation) {
          final offsetAnimation =
              Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
              );

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offsetAnimation, child: child),
          );
        },
        child: isPaused
            ? _PausedRunActions(
                key: const ValueKey('pausedActions'),
                onResume: onResume,
                onEnd: onEnd,
                isCompletingRun: isCompletingRun,
              )
            : _RunningRunActions(
                key: const ValueKey('runningActions'),
                onPause: onPause,
              ),
      ),
    );
  }
}

class _RunningRunActions extends StatelessWidget {
  const _RunningRunActions({super.key, required this.onPause});

  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FilledButton.icon(
        key: const Key('pauseRunButton'),
        onPressed: onPause,
        icon: const Icon(Icons.pause_rounded),
        label: const Text('Pause'),
        style: FilledButton.styleFrom(
          backgroundColor: _panelTextBlue,
          foregroundColor: RuniacColors.white,
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _PausedRunActions extends StatelessWidget {
  const _PausedRunActions({
    super.key,
    required this.onResume,
    required this.onEnd,
    required this.isCompletingRun,
  });

  final VoidCallback onResume;
  final VoidCallback onEnd;
  final bool isCompletingRun;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: SizedBox.expand(
            child: FilledButton.icon(
              key: const Key('resumeRunButton'),
              onPressed: isCompletingRun ? null : onResume,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Resume'),
              style: FilledButton.styleFrom(
                backgroundColor: _panelTextBlue,
                foregroundColor: RuniacColors.white,
                textStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _HoldToEndButton(
            onEnd: onEnd,
            isCompletingRun: isCompletingRun,
          ),
        ),
      ],
    );
  }
}

class _HoldToEndButton extends StatefulWidget {
  const _HoldToEndButton({required this.onEnd, required this.isCompletingRun});

  final VoidCallback onEnd;
  final bool isCompletingRun;

  @override
  State<_HoldToEndButton> createState() => _HoldToEndButtonState();
}

class _HoldToEndButtonState extends State<_HoldToEndButton>
    with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 1500);

  late final AnimationController _controller;
  Timer? _holdTimer;
  bool _completed = false;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _holdDuration)
      ..addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(covariant _HoldToEndButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_completed && !widget.isCompletingRun) {
      _resetHold();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }

    _completeHold();
  }

  void _completeHold() {
    if (_completed) {
      if (widget.isCompletingRun) {
        return;
      }
      _resetHold();
    }

    _completed = true;
    _holding = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    widget.onEnd();
  }

  void _startHold(TapDownDetails _) {
    if (widget.isCompletingRun) {
      return;
    }
    if (_completed) {
      _resetHold();
    }
    _holdTimer?.cancel();
    setState(() => _holding = true);
    _holdTimer = Timer(_holdDuration, _completeHold);
    _controller.forward(from: 0);
  }

  void _resetHold() {
    _completed = false;
    _holding = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    _controller.reset();
  }

  void _cancelHold([Object? _]) {
    if (_completed || widget.isCompletingRun) {
      return;
    }

    if (_controller.value >= 0.98) {
      _completeHold();
      return;
    }

    _holdTimer?.cancel();
    _holdTimer = null;
    setState(() => _holding = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('hold_to_end_button'),
      onTapDown: widget.isCompletingRun ? null : _startHold,
      onTapUp: widget.isCompletingRun ? null : _cancelHold,
      onTapCancel: widget.isCompletingRun ? null : _cancelHold,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: widget.isCompletingRun ? 'Saving run' : 'Hold to end run',
        hint: widget.isCompletingRun
            ? 'Run completion is in progress'
            : 'Hold for 1.5 seconds to finish your run',
        onLongPress: widget.isCompletingRun ? null : _completeHold,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: RuniacColors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _blueBorder, width: 1.5),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_holding && !_completed)
                        Positioned.fill(
                          child: LinearProgressIndicator(
                            key: const Key('hold_to_end_progress_gauge'),
                            value: _controller.value.clamp(0, 1),
                            backgroundColor: Colors.transparent,
                            color: const Color(0xFFFFE4D1),
                          ),
                        ),
                      Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.isCompletingRun
                                    ? Icons.hourglass_top_rounded
                                    : Icons.flag_rounded,
                                color: _panelTextBlue,
                                size: 23,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                widget.isCompletingRun ? 'Saving' : 'End',
                                style: const TextStyle(
                                  color: _panelTextBlue,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
