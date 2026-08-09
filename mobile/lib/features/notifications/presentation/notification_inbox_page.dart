import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/haptics/runiac_haptics.dart';
import '../../../core/haptics/runiac_haptics_scope.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_confirm_dialog.dart';
import '../domain/models/notification_inbox_item.dart';
import '../domain/repositories/notification_inbox_repository.dart';

/// How long a single row takes to slide out, fade, and collapse when the whole
/// inbox is being cleared.
const Duration _clearRowDuration = Duration(milliseconds: 260);

/// Delay between consecutive rows starting their exit, which is what turns a
/// bulk delete into a readable top-down cascade instead of a blink.
const Duration _clearRowStagger = Duration(milliseconds: 45);

/// Cap on the staggered position. Without it a long inbox would hold the runner
/// on a progressively slower animation for no extra information.
const int _maxStaggeredRows = 10;

Duration _clearRowDelay(int index) {
  final steps = index < _maxStaggeredRows ? index : _maxStaggeredRows;
  return _clearRowStagger * steps;
}

/// Total time the cascade needs before the list is visually empty.
Duration _clearCascadeDuration(int itemCount) {
  if (itemCount <= 0) {
    return Duration.zero;
  }
  return _clearRowDelay(itemCount - 1) + _clearRowDuration;
}

class NotificationInboxPage extends StatefulWidget {
  const NotificationInboxPage({
    required this.repository,
    this.now,
    this.onOpenItem,
    super.key,
  });

  final NotificationInboxRepository repository;
  final DateTime Function()? now;

  /// Tap routing seam. Invoked (after the item is marked read) when a row is
  /// tapped, so the composition can route challenge notifications to their
  /// destination. `null` keeps the existing mark-read-only behaviour.
  final void Function(NotificationInboxItem item)? onOpenItem;

  @override
  State<NotificationInboxPage> createState() => _NotificationInboxPageState();
}

class _NotificationInboxPageState extends State<NotificationInboxPage> {
  /// The rows frozen on screen while the clear-all cascade plays.
  ///
  /// The repository write starts immediately on confirmation, so the stream
  /// would otherwise drop every row in a single frame and the cascade would
  /// never be seen. Holding the last snapshot here keeps the animation in
  /// charge of the list until it finishes, and restores it untouched if the
  /// write fails.
  List<NotificationInboxItem>? _clearingItems;

  bool get _isClearing => _clearingItems != null;

  DateTime get _currentTime => (widget.now ?? DateTime.now)();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<NotificationInboxItem>>(
          stream: widget.repository.watchInboxItems(),
          builder: (context, snapshot) {
            final streamItems = snapshot.data ?? const <NotificationInboxItem>[];
            final items = _clearingItems ?? streamItems;
            return Column(
              children: [
                RuniacBackHeader(
                  title: 'Notifications',
                  trailingWidth: 96,
                  trailing: _ClearAllAction(
                    // The action leaves as soon as the cascade starts: it has
                    // done its job, and it must not be tappable a second time.
                    visible: streamItems.isNotEmpty && !_isClearing,
                    onPressed: () => _confirmClearAll(streamItems),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.94,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: items.isEmpty
                        ? const _NotificationInboxEmptyState(
                            key: ValueKey<String>('notification-inbox-empty'),
                          )
                        : _NotificationInboxList(
                            key: const ValueKey<String>('notification-inbox-list'),
                            items: items,
                            clearing: _isClearing,
                            currentTime: _currentTime,
                            onRead: (item) async {
                              await widget.repository.markRead(item.id);
                              widget.onOpenItem?.call(item);
                            },
                            onDelete: (item) =>
                                widget.repository.softDelete(item.id),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmClearAll(List<NotificationInboxItem> items) async {
    if (_isClearing || items.isEmpty) {
      return;
    }
    final haptics = RuniacHapticsScope.maybeOf(context);
    final confirmed = await showRuniacConfirmDialog(
      context,
      icon: Icons.notifications_off_rounded,
      title: 'Clear all notifications?',
      body: items.length == 1
          ? 'This removes your notification from the inbox. '
                'You can’t undo this.'
          : 'This removes all ${items.length} notifications from your inbox. '
                'You can’t undo this.',
      confirmLabel: 'Clear all',
      confirmKey: const ValueKey<String>('notification-inbox-clear-confirm'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _clearAll(items, haptics: haptics);
  }

  Future<void> _clearAll(
    List<NotificationInboxItem> items, {
    required RuniacHaptics? haptics,
  }) async {
    haptics?.impactMedium();
    setState(() {
      _clearingItems = List<NotificationInboxItem>.unmodifiable(items);
    });

    // The write is started before the animation is awaited so persistence is
    // never gated on presentation, and the error is captured at completion
    // time rather than being left unhandled until the cascade ends.
    Object? failure;
    final write = widget.repository.clearAll().then<void>(
      (_) {},
      onError: (Object error) {
        failure = error;
      },
    );

    await Future.wait<void>([
      write,
      Future<void>.delayed(_clearCascadeDuration(items.length)),
    ]);

    if (!mounted) {
      return;
    }
    setState(() {
      _clearingItems = null;
    });
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not clear your notifications. Please try again.'),
        ),
      );
    }
  }
}

class _NotificationInboxList extends StatelessWidget {
  const _NotificationInboxList({
    required this.items,
    required this.clearing,
    required this.currentTime,
    required this.onRead,
    required this.onDelete,
    super.key,
  });

  final List<NotificationInboxItem> items;
  final bool clearing;
  final DateTime currentTime;
  final Future<void> Function(NotificationInboxItem item) onRead;
  final Future<void> Function(NotificationInboxItem item) onDelete;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // A row that is on its way out must not accept a tap or a swipe.
      ignoring: clearing,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _ClearCascadeRow(
            key: ValueKey<String>('notification-cascade-${item.id}'),
            dismissing: clearing,
            delay: _clearRowDelay(index),
            child: Padding(
              padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 10),
              child: _NotificationInboxTile(
                item: item,
                relativeTime: _formatRelativeTime(item.createdAt, currentTime),
                onRead: () => onRead(item),
                onDelete: () => onDelete(item),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Plays one row's share of the clear-all cascade: a staggered slide to the
/// right with a fade, followed by a height collapse so the rows below glide up
/// into the gap instead of jumping.
class _ClearCascadeRow extends StatefulWidget {
  const _ClearCascadeRow({
    required this.dismissing,
    required this.delay,
    required this.child,
    super.key,
  });

  final bool dismissing;
  final Duration delay;
  final Widget child;

  @override
  State<_ClearCascadeRow> createState() => _ClearCascadeRowState();
}

class _ClearCascadeRowState extends State<_ClearCascadeRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _clearRowDuration,
  );

  // The row keeps its full height while it slides and fades, then collapses.
  // Overlapping the two phases slightly keeps the cascade tight without the
  // list appearing to shuffle before anything has visibly left.
  late final Animation<double> _exit = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.62, curve: Curves.easeInCubic),
  );
  late final Animation<double> _collapse = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.45, 1, curve: Curves.easeInOutCubic),
  );

  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    if (widget.dismissing) {
      _scheduleExit();
    }
  }

  @override
  void didUpdateWidget(covariant _ClearCascadeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dismissing && !oldWidget.dismissing) {
      _scheduleExit();
      return;
    }
    if (!widget.dismissing && oldWidget.dismissing) {
      // The clear failed and the list was restored; ease the row back in.
      _startTimer?.cancel();
      _startTimer = null;
      _controller.reverse();
    }
  }

  void _scheduleExit() {
    if (widget.delay == Duration.zero) {
      _controller.forward();
      return;
    }
    _startTimer?.cancel();
    _startTimer = Timer(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final exit = _exit.value.clamp(0.0, 1.0);
        final collapse = _collapse.value.clamp(0.0, 1.0);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1 - collapse,
            child: Opacity(
              opacity: 1 - exit,
              child: Transform.translate(
                offset: Offset(exit * 120, 0),
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// The header's clear-all affordance, which fades and slides in only once
/// there is something to clear.
class _ClearAllAction extends StatelessWidget {
  const _ClearAllAction({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.3, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: visible
          ? Semantics(
              button: true,
              label: 'Clear all notifications',
              child: ExcludeSemantics(
                child: TextButton(
                  key: const ValueKey<String>('notification-inbox-clear-all'),
                  onPressed: onPressed,
                  style: TextButton.styleFrom(
                    foregroundColor: RuniacColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Clear all',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(
              key: ValueKey<String>('notification-inbox-clear-all-hidden'),
            ),
    );
  }
}

class _NotificationInboxTile extends StatelessWidget {
  const _NotificationInboxTile({
    required this.item,
    required this.relativeTime,
    required this.onRead,
    required this.onDelete,
  });

  final NotificationInboxItem item;
  final String relativeTime;
  final Future<void> Function() onRead;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey<String>('notification-${item.id}'),
      direction: DismissDirection.endToStart,
      background: const _DeleteBackground(),
      onDismissed: (_) {
        onDelete();
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onRead,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: item.isRead
                  ? RuniacColors.white
                  : RuniacColors.sectionSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: item.isRead
                    ? RuniacColors.border
                    : RuniacColors.cardBorder,
              ),
              boxShadow: const [
                BoxShadow(
                  color: RuniacColors.softCardShadow,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 16,
                  child: item.isRead
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: EdgeInsets.only(top: 7),
                          child: Semantics(
                            container: true,
                            label: 'Unread notification',
                            child: ExcludeSemantics(
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: RuniacColors.primaryBlue,
                                  shape: BoxShape.circle,
                                ),
                                child: SizedBox(width: 8, height: 8),
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                color: RuniacColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            relativeTime,
                            style: const TextStyle(
                              color: RuniacColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.body,
                        style: const TextStyle(
                          color: RuniacColors.textSecondary,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 18),
      decoration: BoxDecoration(
        color: RuniacColors.errorRed,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Semantics(
        container: true,
        label: 'Delete notification',
        button: true,
        child: const ExcludeSemantics(
          child: Icon(Icons.close, color: RuniacColors.white, size: 24),
        ),
      ),
    );
  }
}

class _NotificationInboxEmptyState extends StatelessWidget {
  const _NotificationInboxEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none,
              color: RuniacColors.primaryBlue,
              size: 44,
            ),
            SizedBox(height: 14),
            Text(
              'No notifications yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: RuniacColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Plan reminders and app updates will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRelativeTime(DateTime createdAt, DateTime now) {
  final elapsed = now.difference(createdAt);
  // Inbox items record deliveries, so `createdAt` is never ahead of now in
  // practice; clamping keeps a clock skew from reading as a negative age.
  final difference = elapsed.isNegative ? Duration.zero : elapsed;
  if (difference.inMinutes < 1) {
    return 'Now';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes}m ago';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  }
  if (difference.inHours < 48) {
    return 'Yesterday';
  }
  return '${difference.inDays}d ago';
}
