import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/legal/runiac_legal_urls.dart';
import 'package:runiac_app/features/profile/presentation/privacy_safety_screen.dart';
import 'package:runiac_app/features/home/domain/guide/home_guide_consent.dart';

import 'support/recording_url_opener.dart';

class _FakeConsentRepository implements HomeGuideConsentRepository {
  _FakeConsentRepository(this._status);

  HomeGuideConsentStatus _status;
  final List<bool> updates = <bool>[];

  @override
  Future<HomeGuideConsentStatus> read() async => _status;

  @override
  Future<HomeGuideConsentStatus> update({required bool granted}) async {
    updates.add(granted);
    _status = granted
        ? HomeGuideConsentStatus.granted
        : HomeGuideConsentStatus.notGranted;
    return _status;
  }
}

const _switchKey = ValueKey<String>('privacySafetyGuideConsentSwitch');

void main() {
  testWidgets('reflects granted consent and lets the user disagree again', (
    tester,
  ) async {
    final repo = _FakeConsentRepository(HomeGuideConsentStatus.granted);

    await tester.pumpWidget(
      MaterialApp(home: PrivacySafetyScreen(consentRepository: repo)),
    );
    await tester.pump(); // resolve read()
    await tester.pump();

    expect(find.byKey(_switchKey), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(_switchKey)).value, isTrue);

    await tester.tap(find.byKey(_switchKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.updates, <bool>[false]);
    expect(tester.widget<Switch>(find.byKey(_switchKey)).value, isFalse);
  });

  testWidgets('lets a user who declined turn the guide back on', (
    tester,
  ) async {
    final repo = _FakeConsentRepository(HomeGuideConsentStatus.notGranted);

    await tester.pumpWidget(
      MaterialApp(home: PrivacySafetyScreen(consentRepository: repo)),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.widget<Switch>(find.byKey(_switchKey)).value, isFalse);

    await tester.tap(find.byKey(_switchKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.updates, <bool>[true]);
    expect(tester.widget<Switch>(find.byKey(_switchKey)).value, isTrue);
  });

  testWidgets('links out to the hosted privacy policy', (tester) async {
    final repo = _FakeConsentRepository(HomeGuideConsentStatus.granted);
    final opener = RecordingUrlOpener();

    await tester.pumpWidget(
      MaterialApp(
        home: PrivacySafetyScreen(
          consentRepository: repo,
          legalUrlOpener: opener,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('privacySafetyPolicyRow')),
    );
    await tester.pump();

    expect(opener.lastUrl, RuniacLegalUrls.privacy);
  });
}
