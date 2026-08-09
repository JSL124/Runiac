import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/legal/runiac_legal_link_launcher.dart';
import 'package:runiac_app/core/legal/runiac_legal_urls.dart';
import 'package:runiac_app/core/widgets/runiac_legal_links_text.dart';

import 'support/recording_url_opener.dart';

Future<void> _pumpLinks(WidgetTester tester, RecordingUrlOpener opener) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: RuniacLegalLinksText(opener: opener)),
      ),
    ),
  );
}

void main() {
  testWidgets('tapping Terms opens the hosted terms document', (tester) async {
    final opener = RecordingUrlOpener();
    await _pumpLinks(tester, opener);

    await tester.tapOnText(find.textRange.ofSubstring('Terms'));
    await tester.pump();

    expect(opener.openedUrls, <Uri>[Uri.parse(RuniacLegalUrls.terms)]);
  });

  testWidgets('tapping Privacy Policy opens the hosted privacy document', (
    tester,
  ) async {
    final opener = RecordingUrlOpener();
    await _pumpLinks(tester, opener);

    await tester.tapOnText(find.textRange.ofSubstring('Privacy Policy'));
    await tester.pump();

    expect(opener.openedUrls, <Uri>[Uri.parse(RuniacLegalUrls.privacy)]);
  });

  testWidgets('surfaces a SnackBar when the platform refuses to open', (
    tester,
  ) async {
    final opener = RecordingUrlOpener(result: false);
    await _pumpLinks(tester, opener);

    await tester.tapOnText(find.textRange.ofSubstring('Terms'));
    await tester.pump();
    await tester.pump();

    expect(find.text(runiacLegalLinkFailureMessage), findsOneWidget);
  });

  testWidgets('disposes its recognizers when removed from the tree', (
    tester,
  ) async {
    final opener = RecordingUrlOpener();
    await _pumpLinks(tester, opener);

    await tester.pumpWidget(const SizedBox());

    expect(tester.takeException(), isNull);
  });
}
