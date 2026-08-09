import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../../../auth/domain/runiac_auth_service.dart';
import '../../../home/domain/guide/home_guide_consent.dart';
import '../../data/firebase_account_deletion_repository.dart';
import '../../domain/models/user_profile_read_model.dart';
import '../about_runiac_screen.dart';
import '../data/account_profile_demo_snapshots.dart';
import '../feedback_screen.dart';
import '../notification_center_screen.dart';
import '../privacy_safety_screen.dart';
import '../running_buddy_screen.dart';
import 'account_delete_row.dart';
import 'account_sign_out_row.dart';

class AccountSectionLabel extends StatelessWidget {
  const AccountSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: RuniacColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}

class AccountSetupSection extends StatelessWidget {
  const AccountSetupSection({required this.items, this.note = '', super.key});

  final List<AccountProfileInfoItem> items;

  /// Plain-language reason for the values above; empty hides the footer.
  final String note;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _SetupRow(item: items[index]),
            if (index != items.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: RuniacColors.border,
                indent: 58,
              ),
          ],
          if (note.isNotEmpty) AccountSetupNote(note: note),
        ],
      ),
    );
  }
}

/// Explains why the training setup above looks the way it does. Kept as a
/// separate widget so the profile and the edit screen read identically.
class AccountSetupNote extends StatelessWidget {
  const AccountSetupNote({required this.note, super.key});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: RuniacColors.innerTileSurface,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(19)),
        border: Border(top: BorderSide(color: RuniacColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            color: RuniacColors.primaryBlue,
            size: 17,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note,
              softWrap: true,
              style: const TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AccountManageSection extends StatelessWidget {
  const AccountManageSection({
    required this.rows,
    required this.authRepository,
    this.onEditProfile,
    this.onNotificationSettingsChanged,
    this.homeGuideConsentRepository =
        const AlwaysGrantedHomeGuideConsentRepository(),
    this.accountDeletionRepository,
    super.key,
  });

  final List<AccountProfileManageRow> rows;
  final RuniacAuthRepository authRepository;
  final VoidCallback? onEditProfile;
  final VoidCallback? onNotificationSettingsChanged;
  final HomeGuideConsentRepository homeGuideConsentRepository;

  /// Test seam for the delete-account flow. Null in production, where the row
  /// builds the real callable-backed repository on tap.
  final AccountDeletionRepository? accountDeletionRepository;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in rows) ...[
          _ManageRow(
            row: row,
            authRepository: authRepository,
            onEditProfile: onEditProfile,
            onNotificationSettingsChanged: onNotificationSettingsChanged,
            homeGuideConsentRepository: homeGuideConsentRepository,
          ),
          const SizedBox(height: 8),
        ],
        AccountSignOutRow(authRepository: authRepository),
        const SizedBox(height: 8),
        // Last, and visually apart: the only row here whose outcome cannot be
        // undone. Store policy (Apple 5.1.1(v), Google Play data deletion)
        // requires this entry point to exist inside the app.
        AccountDeleteRow(
          authRepository: authRepository,
          deletionRepository: accountDeletionRepository,
        ),
      ],
    );
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({required this.item});

  final AccountProfileInfoItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RowIcon(icon: item.icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: RuniacColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.value,
                  softWrap: true,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({
    required this.row,
    required this.authRepository,
    required this.homeGuideConsentRepository,
    this.onEditProfile,
    this.onNotificationSettingsChanged,
  });

  final AccountProfileManageRow row;
  final RuniacAuthRepository authRepository;
  final VoidCallback? onEditProfile;
  final VoidCallback? onNotificationSettingsChanged;
  final HomeGuideConsentRepository homeGuideConsentRepository;

  @override
  Widget build(BuildContext context) {
    return RuniacTappableSurface(
      semanticLabel: row.title,
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      onTap: () {
        if (row.action == UserProfileManageAction.editProfile) {
          onEditProfile?.call();
          return;
        }
        if (row.action == UserProfileManageAction.runningBuddy) {
          // No paywall intercept on the row itself: the buddy is cosmetic and
          // every runner keeps a free choice (Bolt, Mila). The per-character
          // Premium lock lives inside the picker, driven by the same
          // `config/characterAccess` list onboarding uses.
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  RunningBuddyScreen(authRepository: authRepository),
            ),
          );
          return;
        }
        if (row.action == UserProfileManageAction.notifications) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NotificationCenterScreen(
                onSettingsChanged: (_) {
                  onNotificationSettingsChanged?.call();
                },
              ),
            ),
          );
          return;
        }
        if (row.action == UserProfileManageAction.privacySafety) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PrivacySafetyScreen(
                consentRepository: homeGuideConsentRepository,
              ),
            ),
          );
          return;
        }
        if (row.action == UserProfileManageAction.feedback) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => FeedbackScreen()));
          return;
        }
        // UserProfileManageAction.settings is deliberately unhandled here:
        // Settings moved to the Profile header's overflow menu, so no manage
        // row carries that action any more.
        if (row.action == UserProfileManageAction.about) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AboutRuniacScreen()),
          );
          return;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(row.snackBarMessage)));
      },
      child: Row(
        children: [
          _RowIcon(icon: row.icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  row.subtitle,
                  // One line, always: a wrapping subtitle made its card taller
                  // than its neighbours and broke the even rhythm of the list.
                  // Every manage subtitle is written to fit within this bound.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RuniacColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.chevron_right_rounded,
            color: RuniacColors.textSecondary,
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: RuniacColors.sectionSurfaceStrong,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: RuniacColors.primaryBlue, size: 18),
    );
  }
}
