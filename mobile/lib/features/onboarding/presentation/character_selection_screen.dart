import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/characters/runner_character.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../paywall/presentation/current_session_character_access.dart';
import '../../paywall/presentation/premium_gate.dart';

const _defaultCharacterSelectionSubtitle =
    "Pick a friendly guide to cheer you on. They'll pop in "
    'with gentle tips while you set things up. You can enjoy '
    'any of them — this is just for fun.';

String _defaultCharacterConfirmLabel(RunnerCharacter character) {
  return "Let's go with ${character.displayName}";
}

/// The least height the two card rows can take while every card still renders
/// its art, its name and — on the premium-locked pair — its "Premium" label
/// without clipping. Below this the area scrolls rather than squeezing the
/// cards past the point where they overflow. Pinned by
/// `character_selection_short_viewport_test.dart`.
const _minCardRowsHeight = 280.0;

/// Warm, playful screen where a user picks one of four guide characters.
///
/// Used twice: as the onboarding step before the question flow (no [header],
/// default copy), and as the "Running buddy" change screen reached from the
/// Account tab, which supplies a back [header], its own copy, and the current
/// choice as [initialSelection].
///
/// The selection is display-only personalization. Confirming calls [onConfirm]
/// with the chosen character; the caller persists it locally. This screen never
/// writes to Firestore and never affects XP, level, rank, streak, or
/// leaderboard values.
class CharacterSelectionScreen extends StatefulWidget {
  const CharacterSelectionScreen({
    required this.onConfirm,
    this.initialSelection,
    this.header,
    this.title = 'Choose your running buddy',
    this.subtitle = _defaultCharacterSelectionSubtitle,
    this.confirmLabelBuilder = _defaultCharacterConfirmLabel,
    super.key,
  });

  final ValueChanged<RunnerCharacter> onConfirm;
  final RunnerCharacter? initialSelection;

  /// Optional chrome above the heading — the change flow passes a
  /// [RuniacBackHeader]. Onboarding leaves it null, since that step has no
  /// route to go back to.
  final Widget? header;
  final String title;
  final String subtitle;

  /// Builds the confirm button label for the pending choice.
  final String Function(RunnerCharacter) confirmLabelBuilder;

  @override
  State<CharacterSelectionScreen> createState() =>
      _CharacterSelectionScreenState();
}

class _CharacterSelectionScreenState extends State<CharacterSelectionScreen>
    with SingleTickerProviderStateMixin {
  RunnerCharacter? _selected;
  late final AnimationController _bobController;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
    // Finite, decaying celebration bob for the chosen character. It runs once
    // per selection and then stops, so the screen always settles when idle
    // (important for pumpAndSettle-based tests passing through this screen).
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void dispose() {
    _bobController.dispose();
    super.dispose();
  }

  void _select(RunnerCharacter character) {
    _bobController.forward(from: 0);
    setState(() {
      _selected = character;
    });
  }

  /// Whether [character] is admin-gated behind Premium. Reads the trusted
  /// `config/characterAccess` relay; absent scope (tests/previews) means no
  /// gating, so every buddy stays selectable.
  bool _isPremiumOnly(RunnerCharacter character) {
    final access = CharacterAccessScope.maybeRead(context)?.characterAccess;
    return access != null && access.isPremiumOnly(character);
  }

  /// Handles a buddy tap. A Premium-only buddy opens the paywall instead of
  /// selecting unless the runner is confirmed Premium — the character is
  /// cosmetic and stored locally, so this client gate is the whole enforcement
  /// (there is no server value to protect). It fails CLOSED via
  /// [interceptWithPaywallIfHardGated]: while the subscription snapshot is still
  /// loading, a premium-only tap is intercepted rather than allowed, so a Basic
  /// runner cannot slip a premium buddy through the load window.
  void _handleTap(RunnerCharacter character) {
    if (_isPremiumOnly(character) && interceptWithPaywallIfHardGated(context)) {
      return;
    }
    _select(character);
  }

  void _confirm() {
    final selected = _selected;
    if (selected == null) {
      return;
    }
    widget.onConfirm(selected);
  }

  Widget _buildCardRow(
    RunnerCharacter? selected,
    RunnerCharacter left,
    RunnerCharacter right,
  ) {
    return Row(
      children: [
        for (final character in [left, right]) ...[
          if (character == right) const SizedBox(width: 16),
          Expanded(
            child: _CharacterCard(
              character: character,
              isSelected: character == selected,
              isDimmed: selected != null && character != selected,
              // Premium-gated: show the lock unless the runner is confirmed
              // Premium. Fails closed while the account is still loading so a
              // premium-only buddy is never briefly selectable.
              locked:
                  _isPremiumOnly(character) &&
                  watchShouldHardGatePremium(context),
              bob: _bobController,
              onTap: () => _handleTap(character),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // One-shot, session-cached read of the admin-published premium-character
    // list. Kicked off lazily here, where the lock UI first needs it.
    CharacterAccessScope.maybeOf(context)?.ensureLoaded();
    final selected = _selected;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEFF3FF), Color(0xFFFDF3EC)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (widget.header != null) widget.header!,
              Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  widget.header == null ? 24 : 4,
                  24,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: RuniacColors.textPrimary,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: RuniacColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  // All four buddies fit on screen at once (no scrolling), so
                  // nothing hides below the fold — on any viewport tall enough
                  // to render a usable card.
                  //
                  // Below that the rows keep [_minCardRowHeight] and the area
                  // scrolls instead. The cards used to absorb the entire
                  // shortfall, because they are the only flexible thing between
                  // a fixed heading and a fixed confirm button: on a short
                  // viewport each cell collapsed under the ~31dp its name (or
                  // ~52dp its name plus "Premium") needs and threw
                  // `A RenderFlex overflowed by 12/33 pixels on the bottom`,
                  // which is a hard failure in debug builds. It reproduces
                  // between roughly 508dp and 548dp of usable height — narrow
                  // enough that CI's Android emulator sat on the boundary and
                  // failed only on the runs where the system-bar insets landed
                  // before the frame was pumped.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final rows = Column(
                        children: [
                          Expanded(
                            child: _buildCardRow(
                              selected,
                              RunnerCharacter.blue,
                              RunnerCharacter.cap,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _buildCardRow(
                              selected,
                              RunnerCharacter.pink,
                              RunnerCharacter.purple,
                            ),
                          ),
                        ],
                      );

                      if (constraints.maxHeight >= _minCardRowsHeight) {
                        return rows;
                      }

                      return SingleChildScrollView(
                        child: SizedBox(height: _minCardRowsHeight, child: rows),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: selected == null ? 0 : 1,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          selected == null
                              ? ''
                              : '${selected.displayName} is ready to run with '
                                    'you!',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: RuniacColors.primaryBlue,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: selected == null ? null : _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: RuniacColors.primaryBlue,
                          disabledBackgroundColor:
                              RuniacColors.disabledButtonBackground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          selected == null
                              ? 'Pick a buddy to continue'
                              : widget.confirmLabelBuilder(selected),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.character,
    required this.isSelected,
    required this.isDimmed,
    required this.locked,
    required this.bob,
    required this.onTap,
  });

  final RunnerCharacter character;
  final bool isSelected;
  final bool isDimmed;

  /// Premium-gated for the current Basic runner: shows a lock badge and a
  /// "Premium" label, and its tap opens the paywall instead of selecting.
  final bool locked;
  final Animation<double> bob;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: locked
          ? '${character.displayName}, Premium — unlock to choose'
          : 'Choose ${character.displayName}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          scale: isSelected ? 1.04 : (isDimmed ? 0.96 : 1),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: isDimmed ? 0.55 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              decoration: BoxDecoration(
                color: RuniacColors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected
                      ? RuniacColors.primaryBlue
                      : RuniacColors.cardBorder,
                  width: isSelected ? 2.4 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? RuniacColors.primaryButtonShadow
                        : RuniacColors.softCardShadow,
                    blurRadius: isSelected ? 22 : 12,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: bob,
                            builder: (context, child) {
                              // Decaying bounce: a few hops that fade out.
                              final t = bob.value;
                              final offset = isSelected && t > 0 && t < 1
                                  ? -math.sin(t * math.pi * 4).abs() *
                                        10 *
                                        (1 - t)
                                  : 0.0;
                              return Transform.translate(
                                offset: Offset(0, offset),
                                child: child,
                              );
                            },
                            child: Opacity(
                              opacity: locked ? 0.45 : 1,
                              child: Image.asset(
                                character.assetPath(
                                  RunnerCharacterFacing.front,
                                ),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: RuniacColors.primaryBlue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: RuniacColors.white,
                              ),
                            ),
                          ),
                        if (locked)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: RuniacColors.primaryBlue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lock_rounded,
                                size: 15,
                                color: RuniacColors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    character.displayName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? RuniacColors.primaryBlue
                          : RuniacColors.textPrimary,
                    ),
                  ),
                  if (locked) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Premium',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: RuniacColors.primaryBlue,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
