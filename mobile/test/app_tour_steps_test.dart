import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/features/tutorial/domain/app_tour_steps.dart';
import 'package:runiac_app/features/tutorial/domain/models/tutorial_step.dart';

void main() {
  group('runiacAppTourSteps', () {
    test('has exactly 12 unique ids in the documented order', () {
      expect(runiacAppTourSteps.length, 12);
      expect(runiacAppTourSteps.map((step) => step.id).toList(), <String>[
        'welcome',
        'home-today-stone',
        'home-stone-days',
        'home-rest-streak',
        'home-stone-detail',
        'home-level-avatar',
        'home-menu',
        'run-button',
        'feed',
        'leaderboard',
        'you',
        'finish',
      ]);
      final uniqueIds = runiacAppTourSteps.map((step) => step.id).toSet();
      expect(uniqueIds.length, runiacAppTourSteps.length);
    });

    test(
      'every step targets a real bottom-nav tab, never the Run route (2)',
      () {
        for (final step in runiacAppTourSteps) {
          expect(
            <int>[0, 1, 3, 4],
            contains(step.tabIndex),
            reason: 'Step "${step.id}" has tabIndex ${step.tabIndex}',
          );
        }
      },
    );

    test('every message is non-empty and at most 140 characters', () {
      for (final step in runiacAppTourSteps) {
        expect(step.message.isNotEmpty, isTrue, reason: step.id);
        expect(
          step.message.length,
          lessThanOrEqualTo(140),
          reason: '${step.id}: ${step.message.length} chars',
        );
      }
    });

    test('no two steps share the same message', () {
      final messages = runiacAppTourSteps.map((step) => step.message).toList();
      expect(messages.toSet().length, messages.length);
    });

    test(
      'no two steps share the same message across message/fallbackMessage/'
      'restDayMessage combined',
      () {
        final allCopy = <String>[
          for (final step in runiacAppTourSteps) ...[
            step.message,
            if (step.fallbackMessage.isNotEmpty) step.fallbackMessage,
            if (step.restDayMessage.isNotEmpty) step.restDayMessage,
          ],
        ];
        expect(allCopy.toSet().length, allCopy.length);
      },
    );

    test(
      'exactly the four stone steps define a non-empty restDayMessage, each '
      'at most 140 characters',
      () {
        const expectedRestDayStepIds = <String>{
          'home-today-stone',
          'home-stone-days',
          'home-rest-streak',
          'home-stone-detail',
        };
        final actualRestDayStepIds = runiacAppTourSteps
            .where((step) => step.restDayMessage.isNotEmpty)
            .map((step) => step.id)
            .toSet();
        expect(actualRestDayStepIds, expectedRestDayStepIds);
        for (final step in runiacAppTourSteps) {
          if (step.restDayMessage.isEmpty) {
            continue;
          }
          expect(
            step.restDayMessage.length,
            lessThanOrEqualTo(140),
            reason: '${step.id}: ${step.restDayMessage.length} chars',
          );
        }
      },
    );

    test(
      'restDayMessage never claims a running-and-rest mix (the historical '
      'copy-vs-screen mismatch this field exists to fix)',
      () {
        for (final step in runiacAppTourSteps) {
          if (step.restDayMessage.isEmpty) {
            continue;
          }
          expect(
            step.restDayMessage.contains('running days and rest days'),
            isFalse,
            reason: step.id,
          );
        }
      },
    );

    test(
      "home-stone-detail never claims arbitrary stones are tappable — only "
      "today's own stone opens anything, and only when it is a running day",
      () {
        final step = runiacAppTourSteps.firstWhere(
          (step) => step.id == 'home-stone-detail',
        );
        for (final copy in <String>[
          step.message,
          step.fallbackMessage,
          step.restDayMessage,
        ]) {
          expect(copy.contains('any stone'), isFalse, reason: copy);
          expect(copy.contains('a stone'), isFalse, reason: copy);
        }
      },
    );

    test(
      'effectiveMessage(isRestDay: true) returns restDayMessage when set, '
      'else falls back to message unchanged',
      () {
        for (final step in runiacAppTourSteps) {
          final expected = step.restDayMessage.isEmpty
              ? step.message
              : step.restDayMessage;
          expect(
            step.effectiveMessage(isRestDay: true),
            expected,
            reason: step.id,
          );
        }
      },
    );

    test(
      'effectiveMessage(isRestDay: false) always returns message, even for '
      'steps that define a restDayMessage',
      () {
        for (final step in runiacAppTourSteps) {
          expect(
            step.effectiveMessage(isRestDay: false),
            step.message,
            reason: step.id,
          );
        }
      },
    );

    test(
      'every step with anchor candidates has a usable effective fallback',
      () {
        for (final step in runiacAppTourSteps) {
          if (step.anchorCandidates.isNotEmpty) {
            expect(
              step.effectiveFallbackMessage.isNotEmpty,
              isTrue,
              reason: step.id,
            );
          }
        }
      },
    );

    test('only run-button carries a bottomNavItemIndex, and it is 2', () {
      final withBottomNavIndex = runiacAppTourSteps
          .where((step) => step.bottomNavItemIndex != null)
          .toList();
      expect(withBottomNavIndex.length, 1);
      expect(withBottomNavIndex.single.id, 'run-button');
      expect(withBottomNavIndex.single.bottomNavItemIndex, 2);
    });

    test('anchor ordering is preserved for multi-anchor steps', () {
      final leaderboard = runiacAppTourSteps.firstWhere(
        (step) => step.id == 'leaderboard',
      );
      expect(leaderboard.anchorCandidates, <TutorialAnchorId>[
        TutorialAnchorId.leaderboardMap,
        TutorialAnchorId.leaderboardStateMessage,
      ]);
    });

    test(
      'leaderboard step never describes ranking as distance-based — the '
      'server ranks contributions by scoreXp, not distance run '
      '(monthlyLeaderboardPlanner.ts compareContributions)',
      () {
        final leaderboard = runiacAppTourSteps.firstWhere(
          (step) => step.id == 'leaderboard',
        );
        for (final copy in <String>[
          leaderboard.message,
          leaderboard.fallbackMessage,
        ]) {
          expect(copy.contains('by distance'), isFalse, reason: copy);
        }
      },
    );
  });

  group('resolveTutorialCopy', () {
    final welcome = runiacAppTourSteps.first;

    test('leaves no {guide} token behind for any character', () {
      for (final character in RunnerCharacter.values) {
        final resolved = resolveTutorialCopy(welcome.message, character);
        expect(resolved.contains('{guide}'), isFalse, reason: character.name);
      }
    });

    test('substitutes the correct display name per character', () {
      expect(
        resolveTutorialCopy(welcome.message, RunnerCharacter.blue),
        contains('Bolt'),
      );
      expect(
        resolveTutorialCopy(welcome.message, RunnerCharacter.cap),
        contains('Cap'),
      );
      expect(
        resolveTutorialCopy(welcome.message, RunnerCharacter.pink),
        contains('Mila'),
      );
      expect(
        resolveTutorialCopy(welcome.message, RunnerCharacter.purple),
        contains('Ivy'),
      );
    });
  });
}
