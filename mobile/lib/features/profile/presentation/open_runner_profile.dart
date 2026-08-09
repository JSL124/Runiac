import 'package:flutter/material.dart';

import '../../leaderboard/presentation/models/leaderboard_display_models.dart';
import '../../leaderboard/presentation/widgets/runner_achievement_profile_screen.dart';
import 'runner_public_profile_scope.dart';

/// Pushes the shared runner-achievement profile screen for a runner named by
/// uid — the single entry point any tappable identity (feed post, friend row,
/// challenge participant) uses so the leaderboard is not the only surface
/// that can open another runner's profile.
///
/// Reads [RunnerPublicProfileScope] here, in a tap callback, rather than in
/// the profile screen's own `initState` — an `InheritedWidget` read is only
/// legal while a `BuildContext` is still mounted in the tree, and the screen
/// loads before it is ever built.
void openRunnerProfile(
  BuildContext context, {
  required String uid,
  required String displayName,
  String avatarInitials = '',
  String avatarUrl = '',
  String levelBadgeLabel = '',
}) {
  if (uid.isEmpty) {
    // No backing runner to resolve; there is nothing to open.
    return;
  }
  final repository = RunnerPublicProfileScope.of(context);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (routeContext) => RunnerAchievementProfileScreen(
        profile: RunnerAchievementProfileSnapshot.forRunner(
          uid: uid,
          name: displayName,
          initial: avatarInitials,
          photoUrl: avatarUrl,
          levelBadgeLabel: levelBadgeLabel,
        ),
        onBack: () => Navigator.of(routeContext).pop(),
        publicProfileRepository: repository,
      ),
    ),
  );
}
