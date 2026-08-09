import 'package:flutter/material.dart';

import '../open_runner_profile.dart';

/// Wraps any avatar-shaped widget so tapping it opens the runner's public
/// profile. A single place to get the tap target, semantics label, and
/// minimum hit area right, instead of every surface (feed, friends,
/// challenges) rebuilding its own gesture wiring around the badge it already
/// renders.
///
/// Deliberately a [GestureDetector], not `RuniacTappableSurface`: that
/// widget's `Material(clipBehavior: Clip.antiAlias)` clips the level pill
/// that overhangs `RuniacLevelProfileBadge`'s circular avatar.
class RunnerProfileAvatarLink extends StatelessWidget {
  const RunnerProfileAvatarLink({
    super.key,
    required this.uid,
    required this.displayName,
    required this.child,
    this.avatarInitials = '',
    this.avatarUrl = '',
    this.levelBadgeLabel = '',
    this.enabled = true,
  });

  final String uid;
  final String displayName;
  final Widget child;
  final String avatarInitials;

  /// Raw, not-yet-sanitised avatar photo URL, forwarded to the opened
  /// profile so it renders the photo immediately rather than waiting for a
  /// fresh callable resolve.
  final String avatarUrl;
  final String levelBadgeLabel;

  /// Lets a caller keep the badge on screen without making it tappable — for
  /// example the current user's own row, which has nowhere useful to link to.
  final bool enabled;

  // The row badge this wraps renders at 42px; that is below the platform's
  // 44x44 minimum recommended touch target, so this widget pads the tap area
  // out once here rather than every call site reimplementing it.
  static const double _minimumTapDimension = 44;

  @override
  Widget build(BuildContext context) {
    if (!enabled || uid.isEmpty) {
      // Byte-identical to today's non-tappable rendering: no gesture, no
      // button semantics.
      return ExcludeSemantics(child: child);
    }

    void open() {
      openRunnerProfile(
        context,
        uid: uid,
        displayName: displayName,
        avatarInitials: avatarInitials,
        avatarUrl: avatarUrl,
        levelBadgeLabel: levelBadgeLabel,
      );
    }

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: 'View $displayName profile',
      onTap: open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _minimumTapDimension,
            minHeight: _minimumTapDimension,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
