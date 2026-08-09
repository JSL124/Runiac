import 'package:flutter/widgets.dart';

/// Runiac guide character chosen by the user after profile setup and
/// before onboarding.
///
/// The character is display-only personalization. It must never affect or
/// write XP, level, rank, streak, leaderboard score, subscription privilege
/// state, or any other backend-owned value.
enum RunnerCharacter { blue, cap, pink, purple }

enum RunnerCharacterFacing { front, back, left, right }

extension RunnerCharacterDisplay on RunnerCharacter {
  /// Stable identifier used for local persistence keys.
  String get id => name;

  String get displayName {
    return switch (this) {
      RunnerCharacter.blue => 'Bolt',
      RunnerCharacter.cap => 'Cap',
      RunnerCharacter.pink => 'Mila',
      RunnerCharacter.purple => 'Ivy',
    };
  }

  /// Asset path for one of the four facing sprites of this character.
  String assetPath(RunnerCharacterFacing facing) {
    return 'assets/images/characters/${name}_runner_${facing.name}.png';
  }

  /// Idle animation used anywhere the selected guide is waiting in place.
  String get idleAnimationAssetPath {
    return switch (this) {
      RunnerCharacter.blue =>
        'assets/images/characters/blue_idle/blue_runner_idle.gif',
      _ => 'assets/images/characters/${name}_runner_idle.gif',
    };
  }

  /// Directional running animation when one exists for this character.
  ///
  /// The supplied run GIFs are horizontal only. Callers must retain the
  /// directional PNG as their fallback when this returns null.
  String? runAnimationAssetPath(RunnerCharacterFacing facing) {
    if (facing != RunnerCharacterFacing.left &&
        facing != RunnerCharacterFacing.right) {
      return null;
    }
    return 'assets/images/characters/${name}_runner_run_${facing.name}.gif';
  }

  bool get hasRunAnimation => true;

  /// Bolt's animation footprint is the shared display size for every guide.
  double animationHeightForWidth(double width) {
    return width * 289 / 193;
  }
}

RunnerCharacter? runnerCharacterFromId(String? id) {
  if (id == null) {
    return null;
  }
  for (final character in RunnerCharacter.values) {
    if (character.id == id) {
      return character;
    }
  }
  return null;
}

/// Session-local holder for the user's selected guide character.
///
/// Persistence (local preference storage) is layered on top by the feature
/// that owns character selection; consumers read the selection through
/// [SelectedRunnerCharacterScope] and fall back to [selectedOrDefault] when
/// no selection has been made yet.
class SelectedRunnerCharacterStore extends ChangeNotifier {
  RunnerCharacter? _selected;

  RunnerCharacter? get selected => _selected;

  bool get hasSelection => _selected != null;

  RunnerCharacter get selectedOrDefault => _selected ?? RunnerCharacter.blue;

  void select(RunnerCharacter character) {
    if (_selected == character) {
      return;
    }
    _selected = character;
    notifyListeners();
  }

  void clear() {
    if (_selected == null) {
      return;
    }
    _selected = null;
    notifyListeners();
  }
}

class SelectedRunnerCharacterScope
    extends InheritedNotifier<SelectedRunnerCharacterStore> {
  const SelectedRunnerCharacterScope({
    required SelectedRunnerCharacterStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static SelectedRunnerCharacterStore? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SelectedRunnerCharacterScope>()
        ?.notifier;
  }

  static SelectedRunnerCharacterStore of(BuildContext context) {
    final store = maybeOf(context);
    assert(store != null, 'No SelectedRunnerCharacterScope found.');
    return store!;
  }
}
