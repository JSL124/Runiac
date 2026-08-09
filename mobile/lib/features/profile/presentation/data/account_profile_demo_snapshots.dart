import 'package:flutter/material.dart';

import '../../domain/models/user_profile_read_model.dart';

// Production account/profile/region values must come from approved
// backend/Auth/location read paths later, not this static snapshot.
const accountProfileDemoSnapshot = AccountProfileDemoSnapshot(
  displayName: 'Runiac Runner',
  avatarInitials: 'RR',
  // Fallback display only. Real subscription state comes from the
  // backend-owned subscriptionStatus read path once it is implemented.
  subscriptionStatusLabel: 'Basic',
  regionLabel: 'Jurong East, Singapore',
  // Fallback display only. Real streak/distance totals come from the
  // backend-owned user progress read path.
  maxStreakLabel: '12 days',
  totalDistanceLabel: '148.6 km',
  divisionKey: '',
  divisionLabel: 'Unranked',
  // Fallback display only. Real level/progression values come from the
  // backend-owned user progress read path.
  previewLevelBadge: 'Lv.0',
  previewNote: 'Account changes are not saved in this prototype.',
  setupSectionLabel: 'YOUR TRAINING PROFILE',
  manageSectionLabel: 'MANAGE',
  footerCaption: 'Runiac · Preview build · Built for new runners',
  setupNote: 'Based on how often you run now and the days you can commit to.',
  setupItems: [
    AccountProfileInfoItem(
      icon: Icons.flag_outlined,
      title: 'Current goal',
      value: 'Work toward a 10K',
    ),
    AccountProfileInfoItem(
      icon: Icons.directions_walk,
      title: 'Starting point',
      value: 'Getting started',
    ),
    AccountProfileInfoItem(
      icon: Icons.tune,
      title: 'Plan style',
      value: 'Balanced progression',
    ),
    AccountProfileInfoItem(
      icon: Icons.calendar_today_outlined,
      title: 'Schedule',
      value: '3 sessions / week · Mon · Wed · Sat',
    ),
    AccountProfileInfoItem(
      icon: Icons.timer_outlined,
      title: 'Session length',
      value: '30 min',
    ),
    AccountProfileInfoItem(
      icon: Icons.health_and_safety_outlined,
      title: 'Safety',
      value: 'Cleared to start',
    ),
  ],
  manageRows: [
    AccountProfileManageRow(
      icon: Icons.edit_outlined,
      title: 'Edit profile',
      subtitle: 'Personal details and onboarding',
      snackBarMessage: '',
      action: UserProfileManageAction.editProfile,
    ),
    // Settings is deliberately absent: it lives in the Profile header's
    // overflow menu, not in this list.
    AccountProfileManageRow(
      icon: Icons.directions_run,
      title: 'Running buddy',
      subtitle: 'Change your guide character',
      snackBarMessage: '',
      action: UserProfileManageAction.runningBuddy,
    ),
    AccountProfileManageRow(
      icon: Icons.shield_outlined,
      title: 'Privacy & Safety',
      subtitle: 'Guide data use and sharing',
      snackBarMessage: '',
      action: UserProfileManageAction.privacySafety,
    ),
    AccountProfileManageRow(
      icon: Icons.notifications_none,
      title: 'Notifications',
      subtitle: 'Gentle running nudges and reminders',
      snackBarMessage: 'Notification preferences preview is coming soon.',
      action: UserProfileManageAction.notifications,
    ),
    AccountProfileManageRow(
      icon: Icons.info_outline,
      title: 'About Runiac',
      subtitle: 'App version and project information',
      snackBarMessage: '',
      action: UserProfileManageAction.about,
    ),
    AccountProfileManageRow(
      icon: Icons.feedback_outlined,
      title: 'Feedback',
      subtitle: 'Report a bug or share a suggestion',
      snackBarMessage: '',
      action: UserProfileManageAction.feedback,
    ),
  ],
);

class AccountProfileDemoSnapshot {
  const AccountProfileDemoSnapshot({
    required this.displayName,
    required this.avatarInitials,
    this.avatarUrl = '',
    this.subscriptionStatusLabel = '',
    required this.regionLabel,
    required this.previewLevelBadge,
    required this.previewNote,
    required this.setupSectionLabel,
    required this.manageSectionLabel,
    required this.footerCaption,
    required this.setupItems,
    required this.manageRows,
    this.setupNote = '',
    this.regionalRankLabel = '',
    this.maxStreakLabel = '',
    this.totalDistanceLabel = '',
    this.divisionKey = '',
    this.divisionLabel = 'Unranked',
    this.levelProgressFraction = 0,
    this.nextLevelBadge = '',
    this.levelUpCaption = '',
    this.levelXpSummary = '',
  });

  final String displayName;
  final String avatarInitials;

  /// Raw, not-yet-sanitised avatar photo URL for the current runner. Empty
  /// when no photo is set.
  final String avatarUrl;

  /// Backend-provided Basic/Premium subscription tier label for the current
  /// runner; empty hides the badge. The client only relays this trusted
  /// label, it never computes or grants subscription privilege itself.
  final String subscriptionStatusLabel;
  final String regionLabel;

  /// Backend-provided regional rank label for the current runner (e.g. '#1');
  /// empty when the backend has not published a home-region rank yet.
  final String regionalRankLabel;

  /// Backend-provided longest (max) streak label for the current runner
  /// (e.g. '14 days'); empty when the backend has not published it yet.
  final String maxStreakLabel;

  /// Backend-provided lifetime total distance label for the current runner
  /// (e.g. '148.6 km'); empty when the backend has not published it yet.
  final String totalDistanceLabel;
  final String divisionKey;
  final String divisionLabel;
  final String previewLevelBadge;
  final double levelProgressFraction;

  /// Backend-provided next level badge (e.g. 'Lv.4'); empty when unknown or
  /// at max level.
  final String nextLevelBadge;

  /// Backend-provided XP-to-level-up caption (e.g. '320 XP to level up');
  /// empty when the backend has not published progression data yet.
  final String levelUpCaption;

  /// Backend-provided current/target XP summary (e.g. '520 / 600 XP');
  /// empty when the backend has not published both values yet.
  final String levelXpSummary;
  final String previewNote;
  final String setupSectionLabel;
  final String manageSectionLabel;
  final String footerCaption;

  /// Plain-language reason for the training setup; empty hides the note.
  final String setupNote;
  final List<AccountProfileInfoItem> setupItems;
  final List<AccountProfileManageRow> manageRows;
}

class AccountProfileInfoItem {
  const AccountProfileInfoItem({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;
}

class AccountProfileManageRow {
  const AccountProfileManageRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.snackBarMessage,
    this.action = UserProfileManageAction.snackBar,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String snackBarMessage;
  final UserProfileManageAction action;
}
