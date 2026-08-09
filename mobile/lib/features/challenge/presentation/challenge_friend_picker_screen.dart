import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../../../core/widgets/runiac_level_profile_badge.dart';
import '../../profile/presentation/widgets/runner_profile_avatar_link.dart';
import '../domain/challenge_copy.dart';
import 'widgets/challenge_widgets.dart';

/// Loader seam for the reciprocal-friends invite list. Defaults to none until a
/// friends source is wired through; the picker then shows its empty state.
typedef ChallengeInvitableFriendsLoader
    = Future<List<ChallengeInvitableFriend>> Function();

Future<List<ChallengeInvitableFriend>> noChallengeInvitableFriends() async =>
    const <ChallengeInvitableFriend>[];

/// A reciprocal friend the owner may invite to a lobby. Identity is limited to
/// a display name, initials, and backend-owned level label (for the same
/// profile badge Friends renders); no routes, metrics, or activity are
/// exposed.
class ChallengeInvitableFriend {
  const ChallengeInvitableFriend({
    required this.uid,
    required this.displayName,
    required this.initials,
    this.levelLabel = '',
    this.avatarUrl = '',
    this.levelProgressFraction = 0,
  });

  final String uid;
  final String displayName;
  final String initials;

  /// Pre-formatted backend-owned display string, e.g. `'Lv.12'`. Never
  /// computed on the client.
  final String levelLabel;

  /// Raw, not-yet-sanitised avatar photo URL. Empty when the friend has no
  /// photo set.
  final String avatarUrl;

  /// Backend-owned progress toward the next level, 0.0..1.0, painted as the XP
  /// ring around the row's avatar. Carried over from the Friends read model
  /// the caller maps from, which resolves it through `getFriendLevels`.
  /// Never computed on the client.
  final double levelProgressFraction;
}

/// Reciprocal-friends picker with a capacity-capped checkbox selection.
///
/// The cap is the tier's invite cap. Once `alreadyInvited + selected` reaches
/// [cap] the remaining rows disable with an "Invite limit reached" hint. The
/// screen returns the selected uids via `Navigator.pop`; the caller performs
/// the trusted `inviteChallengeFriends` call.
class ChallengeFriendPickerScreen extends StatefulWidget {
  const ChallengeFriendPickerScreen({
    required this.friends,
    required this.cap,
    required this.onBack,
    this.alreadyInvited = 0,
    super.key,
  });

  final List<ChallengeInvitableFriend> friends;
  final int cap;
  final int alreadyInvited;
  final VoidCallback onBack;

  @override
  State<ChallengeFriendPickerScreen> createState() =>
      _ChallengeFriendPickerScreenState();
}

class _ChallengeFriendPickerScreenState
    extends State<ChallengeFriendPickerScreen> {
  final Set<String> _selected = <String>{};

  int get _total => widget.alreadyInvited + _selected.length;

  bool get _atCap => _total >= widget.cap;

  void _toggle(String uid) {
    setState(() {
      if (_selected.contains(uid)) {
        _selected.remove(uid);
      } else if (!_atCap) {
        _selected.add(uid);
      }
    });
  }

  void _confirm() {
    Navigator.of(context).pop<List<String>>(_selected.toList(growable: false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: Column(
          children: [
            RuniacBackHeader(
              title: ChallengeCopy.inviteFriends,
              onBack: widget.onBack,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ChallengeCopy.invitedOf(_total, widget.cap),
                      style: const TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.friends.isEmpty
                  ? const ChallengeEmptyState(
                      title: ChallengeCopy.addFriendsToInvite,
                      icon: Icons.person_add_alt_1_outlined,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: widget.friends.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final friend = widget.friends[index];
                        final selected = _selected.contains(friend.uid);
                        final disabled = !selected && _atCap;
                        return _FriendPickRow(
                          friend: friend,
                          selected: selected,
                          disabled: disabled,
                          onTap: disabled ? null : () => _toggle(friend.uid),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: RuniacButtonStyles.primary(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _selected.isEmpty ? null : _confirm,
                    child: Text(
                      ChallengeCopy.invitedOf(_total, widget.cap),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendPickRow extends StatelessWidget {
  const _FriendPickRow({
    required this.friend,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final ChallengeInvitableFriend friend;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // `explicitChildNodes: true` keeps this row's own button/label semantics
    // separate from the avatar's nested `RunnerProfileAvatarLink` semantics
    // below, instead of the two merging into one node with a garbled,
    // concatenated label. `onTap` is attached here directly (in addition to
    // the real `RuniacTappableSurface.onTap` used for the actual gesture)
    // because `explicitChildNodes` also stops the inner `InkWell`'s tap
    // action from merging upward, so this node needs its own action wired to
    // stay activatable via assistive tech.
    //
    // The label deliberately stays on this outer node rather than moving to
    // `RuniacTappableSurface.semanticLabel`: that parameter forces
    // `excludeSemantics: true` on whatever node it produces (see
    // `RuniacTappableSurface`), which — per `RenderObject
    // .visitChildrenForSemantics` — drops ALL descendant semantics nodes,
    // including the avatar's own explicit "View <name> profile" button node.
    // Since this row is the first place a `RunnerProfileAvatarLink` sits
    // inside a `RuniacTappableSurface` with a competing row-level action,
    // that swallow behaviour is new territory this row must avoid.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      selected: selected,
      enabled: !disabled,
      label: friend.displayName,
      onTap: onTap,
      child: RuniacTappableSurface(
        onTap: onTap,
        semanticsButton: false,
        borderRadius: BorderRadius.circular(18),
        decoration: BoxDecoration(
          color: RuniacColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? RuniacColors.primaryBlue : RuniacColors.cardBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            RunnerProfileAvatarLink(
              uid: friend.uid,
              displayName: friend.displayName,
              avatarInitials: friend.initials,
              avatarUrl: friend.avatarUrl,
              levelBadgeLabel: friend.levelLabel,
              child: ExcludeSemantics(
                child: RuniacLevelProfileBadge.row(
                  initials: friend.initials,
                  levelLabel: friend.levelLabel.trim().isEmpty
                      ? 'Lv.0'
                      : friend.levelLabel,
                  progressFraction: friend.levelProgressFraction,
                  photoUrl: friend.avatarUrl,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: disabled
                          ? RuniacColors.textSecondary
                          : RuniacColors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (disabled) ...[
                    const SizedBox(height: 2),
                    const Text(
                      ChallengeCopy.inviteLimitReached,
                      style: TextStyle(
                        color: RuniacColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              color: selected
                  ? RuniacColors.primaryBlue
                  : (disabled
                        ? RuniacColors.disabledButtonForeground
                        : RuniacColors.textSecondary),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
