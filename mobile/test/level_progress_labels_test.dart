import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/presentation/level_progress_labels.dart';

/// Unit coverage for the level-gauge label resolver shared by the signed-in
/// runner's own account screen and another runner's public profile. Both
/// gauges must read identically, and neither may invent a value the backend
/// has not published.
void main() {
  group('resolveLevelProgressLabels', () {
    test('composes next level, remaining XP, and the XP summary', () {
      final labels = resolveLevelProgressLabels(
        hasProgress: true,
        level: 8,
        isMaxLevel: false,
        totalXp: 780,
        nextLevelXp: 800,
        xpToNextLevel: 20,
      );

      expect(labels.nextLevelBadge, 'Lv.9');
      expect(labels.levelUpCaption, '20 XP to level up');
      expect(labels.levelXpSummary, '780 / 800 XP');
    });

    test('blanks every label while progression is unresolved', () {
      final labels = resolveLevelProgressLabels(
        hasProgress: false,
        level: 8,
        isMaxLevel: false,
        totalXp: 780,
        nextLevelXp: 800,
        xpToNextLevel: 20,
      );

      expect(labels.nextLevelBadge, '');
      expect(labels.levelUpCaption, '');
      expect(labels.levelXpSummary, '');
    });

    test('reports max level without a next-level target', () {
      final labels = resolveLevelProgressLabels(
        hasProgress: true,
        level: 50,
        isMaxLevel: true,
        totalXp: 125000,
        nextLevelXp: null,
        xpToNextLevel: null,
      );

      expect(labels.nextLevelBadge, '');
      expect(labels.levelUpCaption, 'Max level reached');
      expect(labels.levelXpSummary, '125,000 XP');
    });

    test('omits captions the backend has not published', () {
      final labels = resolveLevelProgressLabels(
        hasProgress: true,
        level: 3,
        isMaxLevel: false,
        totalXp: null,
        nextLevelXp: null,
        xpToNextLevel: null,
      );

      expect(labels.nextLevelBadge, 'Lv.4');
      expect(labels.levelUpCaption, '');
      expect(labels.levelXpSummary, '');
    });

    test('omits the XP summary when only the total is published', () {
      final labels = resolveLevelProgressLabels(
        hasProgress: true,
        level: 3,
        isMaxLevel: false,
        totalXp: 240,
        nextLevelXp: null,
        xpToNextLevel: 60,
      );

      expect(labels.levelUpCaption, '60 XP to level up');
      expect(labels.levelXpSummary, '');
    });
  });

  group('formatXpThousands', () {
    test('groups thousands', () {
      expect(formatXpThousands(0), '0');
      expect(formatXpThousands(999), '999');
      expect(formatXpThousands(1000), '1,000');
      expect(formatXpThousands(1234567), '1,234,567');
    });

    test('keeps a negative sign outside the grouping', () {
      expect(formatXpThousands(-1500), '-1,500');
    });
  });
}
