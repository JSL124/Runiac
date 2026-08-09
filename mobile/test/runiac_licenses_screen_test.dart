import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/presentation/runiac_licenses_screen.dart';

void main() {
  setUpAll(() {
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(
        <String>['runiac_qa_fake_pkg'],
        'Runiac QA fake license text.',
      );
    });
  });

  testWidgets('lists aggregated licenses and shows the footer version', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RuniacLicensesScreen(applicationVersion: '1.0.0'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('runiac_qa_fake_pkg'), findsOneWidget);
    expect(find.textContaining('Version 1.0.0'), findsOneWidget);
  });

  testWidgets('tapping a package opens its license detail text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RuniacLicensesScreen(applicationVersion: '1.0.0'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('runiac_qa_fake_pkg'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Runiac QA fake license'), findsWidgets);
  });
}
