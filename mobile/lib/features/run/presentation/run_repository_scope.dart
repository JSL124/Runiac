import 'package:flutter/widgets.dart';

import '../data/static_run_repository.dart';
import '../domain/repositories/run_repository.dart';

class RunRepositoryScope extends InheritedWidget {
  const RunRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final RunRepository repository;

  static RunRepository of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RunRepositoryScope>();
    return scope?.repository ?? const StaticRunRepository();
  }

  @override
  bool updateShouldNotify(RunRepositoryScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
