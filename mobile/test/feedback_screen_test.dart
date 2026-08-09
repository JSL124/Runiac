import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/data/flutterfire_submit_feedback_callable.dart';
import 'package:runiac_app/features/profile/presentation/feedback_screen.dart';

void main() {
  testWidgets('Submit is disabled until a category and message are chosen', (
    tester,
  ) async {
    final callable = _FakeSubmitFeedbackCallable();
    await tester.pumpWidget(
      MaterialApp(home: FeedbackScreen(callable: callable)),
    );

    Finder submitButton() =>
        find.byKey(const ValueKey<String>('feedbackSubmitButton'));

    expect(
      tester.widget<FilledButton>(submitButton()).onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('feedbackCategoryChip_bug')),
    );
    await tester.pump();

    expect(
      tester.widget<FilledButton>(submitButton()).onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('feedbackMessageField')),
      'The map crashes when I start a run.',
    );
    await tester.pump();

    expect(
      tester.widget<FilledButton>(submitButton()).onPressed,
      isNotNull,
    );
    expect(callable.calls, isEmpty);
  });

  testWidgets(
    'Submitting sends the exact category/message payload, shows a success '
    'SnackBar, and pops',
    (tester) async {
      final callable = _FakeSubmitFeedbackCallable();
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => FeedbackScreen(callable: callable),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('feedbackCategoryChip_planIssue')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('feedbackMessageField')),
        'My week 3 plan is missing a rest day.',
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('feedbackSubmitButton')),
      );
      await tester.pumpAndSettle();

      expect(callable.calls, hasLength(1));
      expect(callable.calls.single, <String, Object?>{
        'category': 'plan issue',
        'message': 'My week 3 plan is missing a rest day.',
      });
      expect(find.text('Thanks for your feedback!'), findsOneWidget);
      expect(find.byType(FeedbackScreen), findsNothing);
    },
  );

  testWidgets(
    'A failed submission shows the typed error message and stays on screen',
    (tester) async {
      final callable = _FakeSubmitFeedbackCallable(
        error: const SubmitFeedbackException(
          code: 'resource-exhausted',
          userMessage:
              "You've sent several reports recently. Please try again later.",
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: FeedbackScreen(callable: callable)),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('feedbackCategoryChip_other')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('feedbackMessageField')),
        'Just a suggestion.',
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('feedbackSubmitButton')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          "You've sent several reports recently. Please try again later.",
        ),
        findsOneWidget,
      );
      expect(find.byType(FeedbackScreen), findsOneWidget);
      expect(callable.calls, hasLength(1));
    },
  );
}

class _FakeSubmitFeedbackCallable implements SubmitFeedbackCallable {
  _FakeSubmitFeedbackCallable({this.error});

  final SubmitFeedbackException? error;
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    calls.add(request);
    if (error != null) {
      throw error!;
    }
    return <String, Object?>{'feedbackId': 'feedback-1'};
  }
}
