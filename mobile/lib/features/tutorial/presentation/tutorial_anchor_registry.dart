import 'package:flutter/material.dart';

import '../domain/models/tutorial_step.dart';

/// Resolves the live on-screen position of tour anchors.
///
/// One [GlobalKey] is created and cached per [TutorialAnchorId], the first
/// time it is requested. Because a [GlobalKey] must be unique across the
/// whole widget tree, callers must guarantee that at most one live widget in
/// the tree is ever wrapped with a given id at a time — this registry has no
/// way to enforce that on its own.
class TutorialAnchorRegistry {
  final Map<TutorialAnchorId, GlobalKey> _keys = <TutorialAnchorId, GlobalKey>{};

  /// Returns the single [GlobalKey] for [id], creating it on first use.
  GlobalKey keyFor(TutorialAnchorId id) {
    return _keys.putIfAbsent(
      id,
      () => GlobalKey(debugLabel: 'tutorialAnchor.${id.name}'),
    );
  }

  /// The [BuildContext] currently mounted under [id]'s key, or null when
  /// nothing wrapped with that id is in the tree right now.
  BuildContext? contextFor(TutorialAnchorId id) {
    return keyFor(id).currentContext;
  }

  /// The resolved global [Rect] of the widget currently wrapped with [id],
  /// or null when the anchor is not mounted, not yet laid out, or has an
  /// empty size.
  Rect? rectFor(TutorialAnchorId id) {
    final renderObject = keyFor(id).currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      return null;
    }
    final box = renderObject;
    if (!box.attached || !box.hasSize || box.size.isEmpty) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// Makes a [TutorialAnchorRegistry] available to descendants so screens can
/// register anchors via [TutorialAnchor] and the tour host can resolve them.
///
/// This widget only defines the plumbing; mounting it above the shell/tabs is
/// the responsibility of the tour host.
class TutorialAnchorScope extends InheritedWidget {
  const TutorialAnchorScope({
    required this.registry,
    required super.child,
    super.key,
  });

  final TutorialAnchorRegistry registry;

  static TutorialAnchorRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TutorialAnchorScope>()
        ?.registry;
  }

  @override
  bool updateShouldNotify(TutorialAnchorScope oldWidget) {
    return !identical(registry, oldWidget.registry);
  }
}

/// Marks [child] as the resolvable location for tour anchor [id].
///
/// When no [TutorialAnchorScope] is above this widget in the tree (i.e. the
/// tour host is not mounted, which is the default in every existing screen
/// and test), this is a pure pass-through: it returns [child] unchanged, with
/// no extra widget and no key attached. Existing screens and their tests are
/// therefore unaffected by wrapping a widget in [TutorialAnchor].
class TutorialAnchor extends StatelessWidget {
  const TutorialAnchor({required this.id, required this.child, super.key});

  final TutorialAnchorId id;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final registry = TutorialAnchorScope.maybeOf(context);
    if (registry == null) {
      return child;
    }
    return KeyedSubtree(key: registry.keyFor(id), child: child);
  }
}

/// The bottom nav bar is a single anchor candidate (see
/// [TutorialAnchorId.bottomNavBar]), but a tour step may want to spotlight one
/// specific item within it (e.g. the Run tab). `BottomNavigationBar` keeps
/// both an `icon` and an `activeIcon` widget for every item mounted in the
/// tree at once, and by default those two are the very same widget instance,
/// so attaching a per-item [GlobalKey] would register that key twice and
/// throw a duplicate-key error. Instead, the tour resolves the whole bar's
/// rect once via [TutorialAnchorId.bottomNavBar] and derives an individual
/// item's rect geometrically with this helper.
///
/// Returns the [index]-th equal horizontal slice of [bar] (out of [count]
/// slices), top-aligned to [bar], with height capped at
/// [kBottomNavigationBarHeight] so a taller bar (extra safe-area padding)
/// does not inflate the highlighted region.
Rect bottomNavItemRect(Rect bar, int index, {int count = 5}) {
  final itemWidth = bar.width / count;
  final height = bar.height < kBottomNavigationBarHeight
      ? bar.height
      : kBottomNavigationBarHeight;
  return Rect.fromLTWH(bar.left + itemWidth * index, bar.top, itemWidth, height);
}
