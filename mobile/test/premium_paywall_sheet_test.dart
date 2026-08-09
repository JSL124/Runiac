import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/core/legal/runiac_legal_urls.dart';
import 'package:runiac_app/features/paywall/domain/models/paywall_config_read_model.dart';
import 'package:runiac_app/features/paywall/presentation/premium_paywall_sheet.dart';

import 'support/recording_url_opener.dart';

Future<void> _pumpSheet(
  WidgetTester tester, {
  bool disableAnimations = false,
  RunnerCharacter character = RunnerCharacter.pink,
  RecordingUrlOpener? legalUrlOpener,
}) async {
  final originalSize = tester.view.physicalSize;
  final originalDevicePixelRatio = tester.view.devicePixelRatio;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.physicalSize = originalSize;
    tester.view.devicePixelRatio = originalDevicePixelRatio;
  });

  final characterStore = SelectedRunnerCharacterStore()..select(character);
  addTearDown(characterStore.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            disableAnimations: disableAnimations,
          ),
          child: SelectedRunnerCharacterScope(
            store: characterStore,
            child: PremiumPaywallSheet(
              legalUrlOpener: legalUrlOpener ?? RecordingUrlOpener(),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Disposes the pumped tree so repeating animations and periodic timers are
/// cancelled before the test ends.
Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  final defaults = PaywallConfigReadModel.defaults;

  testWidgets('renders the default admin copy without any scope', (
    tester,
  ) async {
    await _pumpSheet(tester);
    await tester.pump();

    expect(find.byKey(const Key('paywall-title')), findsOneWidget);
    expect(find.text(defaults.title), findsOneWidget);
    expect(find.text(defaults.badge), findsOneWidget);
    for (final feature in defaults.features) {
      expect(find.text(feature.title), findsOneWidget);
    }
    expect(find.text(defaults.monthly.price), findsOneWidget);
    expect(find.text(defaults.yearly.price), findsOneWidget);
    // Yearly is preselected, so its note and CTA price show.
    expect(find.text(defaults.yearly.note), findsOneWidget);
    expect(
      find.text(
        '${defaults.ctaLabel} · ${defaults.yearly.price} '
        '${defaults.yearly.period}',
      ),
      findsOneWidget,
    );
    expect(find.text(defaults.footer.termsLabel), findsOneWidget);
    expect(find.text(defaults.footer.privacyLabel), findsOneWidget);

    await _teardownTree(tester);
  });

  testWidgets('switching the plan selection updates the CTA', (tester) async {
    await _pumpSheet(tester);
    await tester.pump();

    await tester.tap(find.byKey(const Key('paywall-plan-monthly')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.text(
        '${defaults.ctaLabel} · ${defaults.monthly.price} '
        '${defaults.monthly.period}',
      ),
      findsOneWidget,
    );
    // Monthly has no savings note.
    expect(find.text(defaults.yearly.note), findsNothing);

    await _teardownTree(tester);
  });

  testWidgets('CTA tap plays the coming-soon note and then reverts', (
    tester,
  ) async {
    await _pumpSheet(tester);
    await tester.pump();

    await tester.tap(find.byKey(const Key('paywall-subscribe-button')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.byKey(const Key('paywall-coming-soon-note')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Coming soon'), findsNothing);
    expect(find.byKey(const Key('paywall-coming-soon-note')), findsNothing);

    await _teardownTree(tester);
  });

  testWidgets('the selected character sprite is shown beside the card', (
    tester,
  ) async {
    await _pumpSheet(tester, character: RunnerCharacter.purple);
    await tester.pump();

    final sprite = tester.widget<Image>(
      find.byKey(const Key('paywall-character-sprite')),
    );
    expect(
      (sprite.image as AssetImage).assetName,
      RunnerCharacter.purple.idleAnimationAssetPath,
    );

    await _teardownTree(tester);
  });

  testWidgets('reduced motion renders statically and fully settles', (
    tester,
  ) async {
    // The selected character would normally play its idle GIF; reduced motion
    // must fall back to
    // the static front sprite, schedule no highlight timer, and settle.
    await _pumpSheet(
      tester,
      disableAnimations: true,
      character: RunnerCharacter.blue,
    );
    await tester.pumpAndSettle();

    final sprite = tester.widget<Image>(
      find.byKey(const Key('paywall-character-sprite')),
    );
    expect(
      (sprite.image as AssetImage).assetName,
      RunnerCharacter.blue.assetPath(RunnerCharacterFacing.front),
    );
    expect(find.byKey(const Key('paywall-title')), findsOneWidget);
  });

  testWidgets('footer links open the hosted terms and privacy documents', (
    tester,
  ) async {
    // App Store Guideline 3.1.2: both links must be functional on the
    // subscription surface, not decorative labels.
    final opener = RecordingUrlOpener();
    await _pumpSheet(tester, disableAnimations: true, legalUrlOpener: opener);
    await tester.pumpAndSettle();

    await tester.tap(find.text(defaults.footer.termsLabel));
    await tester.pump();
    expect(opener.lastUrl, RuniacLegalUrls.terms);

    await tester.tap(find.text(defaults.footer.privacyLabel));
    await tester.pump();
    expect(opener.lastUrl, RuniacLegalUrls.privacy);
  });
}
