import 'package:flutter/widgets.dart';

import '../domain/repositories/runner_public_profile_repository.dart';

/// Makes the runner-public-profile backend source reachable from any tap
/// callback in the tree, instead of threading `runnerPublicProfileRepository`
/// through every screen between `app.dart` and the tap that opens a profile.
class RunnerPublicProfileScope extends InheritedWidget {
  const RunnerPublicProfileScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final RunnerPublicProfileRepository repository;

  static RunnerPublicProfileRepository of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RunnerPublicProfileScope>();
    return scope?.repository ??
        const UnavailableRunnerPublicProfileRepository();
  }

  @override
  bool updateShouldNotify(RunnerPublicProfileScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
