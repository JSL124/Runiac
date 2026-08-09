import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/legal/runiac_legal_urls.dart';
import 'package:runiac_app/features/profile/presentation/about_runiac_screen.dart';

import 'support/recording_url_opener.dart';

void main() {
  testWidgets('renders app name, version, and licenses row', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AboutRuniacScreen(
          versionOverride: '1.0.0',
          buildNumberOverride: '1',
        ),
      ),
    );

    expect(find.text('Runiac'), findsOneWidget);
    expect(find.text('Version 1.0.0 (build 1)'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
  });

  testWidgets('opens the hosted legal documents from the legal rows', (
    tester,
  ) async {
    final opener = RecordingUrlOpener();

    await tester.pumpWidget(
      MaterialApp(
        home: AboutRuniacScreen(
          versionOverride: '1.0.0',
          buildNumberOverride: '1',
          legalUrlOpener: opener,
        ),
      ),
    );

    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);

    await tester.tap(find.text('Terms of Service'));
    await tester.pump();
    expect(opener.lastUrl, RuniacLegalUrls.terms);

    await tester.tap(find.text('Privacy Policy'));
    await tester.pump();
    expect(opener.lastUrl, RuniacLegalUrls.privacy);
  });
}
