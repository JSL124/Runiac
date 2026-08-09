import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/moderation/domain/models/report_user_reason.dart';
import 'package:runiac_app/features/moderation/presentation/widgets/report_user_sheet.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required Future<void> Function(ReportUserReason reason, String description)
    onSubmit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReportUserSheet(
                context,
                targetDisplayName: 'Jamie Tan',
                onSubmit: onSubmit,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'submits the selected reason and description, then shows a terminal state',
    (tester) async {
      ReportUserReason? capturedReason;
      String? capturedDescription;
      final submitGate = Completer<void>();
      await pumpSheet(
        tester,
        onSubmit: (reason, description) async {
          capturedReason = reason;
          capturedDescription = description;
          await submitGate.future;
        },
      );

      expect(find.text('Report Jamie Tan'), findsOneWidget);
      expect(find.text('Report received'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('report-user-reason-unsafeConduct')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('report-user-description-field')),
        'They followed me after a run.',
      );

      await tester.tap(find.text('Report'));
      await tester.pump();
      expect(find.text('Reporting…'), findsOneWidget);
      expect(find.text('Report received'), findsNothing);

      submitGate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Report received'), findsOneWidget);
      expect(capturedReason, ReportUserReason.unsafeConduct);
      expect(capturedDescription, 'They followed me after a run.');
    },
  );

  testWidgets(
    'shows an identical terminal state for a duplicate report as for a fresh one',
    (tester) async {
      // Models report_user_writer.dart swallowing a permission-denied
      // duplicate: onSubmit completes normally, exactly like a fresh report
      // would, so the UI cannot and must not tell the two cases apart.
      await pumpSheet(tester, onSubmit: (_, _) async {});

      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(find.text('Report received'), findsOneWidget);
    },
  );

  testWidgets('surfaces a genuine failure and allows retrying', (
    tester,
  ) async {
    var attempts = 0;
    await pumpSheet(
      tester,
      onSubmit: (_, _) async {
        attempts += 1;
        if (attempts == 1) {
          throw Exception('network down');
        }
      },
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(
      find.text('Report could not be sent. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Report received'), findsNothing);

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(find.text('Report received'), findsOneWidget);
  });

  testWidgets('defaults to the harassment-or-abuse reason', (tester) async {
    ReportUserReason? capturedReason;
    await pumpSheet(
      tester,
      onSubmit: (reason, _) async {
        capturedReason = reason;
      },
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(capturedReason, ReportUserReason.harassmentOrAbuse);
  });
}
