import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:runiac_app/core/widgets/runiac_buttons.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/presentation/about_runiac_screen.dart';
import 'package:runiac_app/features/profile/presentation/data/account_profile_demo_snapshots.dart';
import 'package:runiac_app/features/profile/presentation/widgets/account_profile_sections.dart';

import 'support/fake_runiac_auth_repository.dart';

void main() {
  setUpAll(() {
    // Avoids a real platform channel round-trip when AboutRuniacScreen is
    // pushed without version overrides, matching how the real routing code
    // constructs it (`const AboutRuniacScreen()`).
    PackageInfo.setMockInitialValues(
      appName: 'Runiac',
      packageName: 'app.runiac',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  // Scrolls like AccountProfileScreen does (the section lives inside that
  // screen's SingleChildScrollView), so the row count is free to grow without
  // overflowing the default test surface.
  Widget buildManageSection({double? width}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: AccountManageSection(
                rows: accountProfileDemoSnapshot.manageRows,
                authRepository: FakeRuniacAuthRepository(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('tapping About Runiac pushes AboutRuniacScreen, no snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(buildManageSection());

    expect(find.byType(AboutRuniacScreen), findsNothing);

    await tester.ensureVisible(find.text('About Runiac'));
    await tester.tap(find.text('About Runiac'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutRuniacScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('About Runiac preview is coming soon.'), findsNothing);
  });

  testWidgets('About Runiac row carries a non-snackBar action', (tester) async {
    final rows = accountProfileDemoSnapshot.manageRows;
    final aboutRow = rows.firstWhere((row) => row.title == 'About Runiac');

    expect(aboutRow.action, UserProfileManageAction.about);
    expect(aboutRow.snackBarMessage, isEmpty);
  });

  testWidgets('Settings is no longer a manage row', (tester) async {
    // It moved to the Profile header's overflow menu; a stray row here would
    // give the app two entry points to the same screen.
    expect(
      accountProfileDemoSnapshot.manageRows.where(
        (row) =>
            row.title == 'Settings' ||
            row.action == UserProfileManageAction.settings,
      ),
      isEmpty,
    );

    await tester.pumpWidget(buildManageSection());
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('every manage card is the same height at phone width', (
    tester,
  ) async {
    // 358 = a 390pt phone minus AccountProfileScreen's 16pt side padding. The
    // default 800pt test surface is too wide to wrap anything, so the width has
    // to be pinned for this to mean anything.
    //
    // This asserts the layout bound, not the copy: the test font draws every
    // glyph as a square of the font size, so on-device line breaks cannot be
    // measured here. Dropping the subtitle's single-line cap fails it.
    await tester.pumpWidget(buildManageSection(width: 358));
    await tester.pumpAndSettle();

    final cards = find.byType(RuniacTappableSurface);
    // Every manage row, plus the sign-out and delete-account rows below them.
    // The delete row is styled apart (red border and label) but is deliberately
    // built to the same metrics, so it belongs in this height assertion rather
    // than being excluded from it.
    expect(
      cards,
      findsNWidgets(accountProfileDemoSnapshot.manageRows.length + 2),
    );

    final heights = <double>{
      for (var i = 0; i < cards.evaluate().length; i++)
        tester.getSize(cards.at(i)).height,
    };
    expect(
      heights,
      hasLength(1),
      reason:
          'A manage subtitle wrapped to a second line. Shorten the copy so the '
          'card keeps the single-line height the rest of the list uses.',
    );
  });
}
