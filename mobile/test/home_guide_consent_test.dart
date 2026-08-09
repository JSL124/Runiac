import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/home/data/cloud_function_home_guide_consent_repository.dart';
import 'package:runiac_app/features/home/domain/guide/home_guide_consent.dart';

void main() {
  group('CloudFunctionHomeGuideConsentRepository', () {
    test('reads the current versioned server consent state', () async {
      Map<String, Object?>? payload;
      final repository = CloudFunctionHomeGuideConsentRepository(
        callable: (value) async {
          payload = value;
          return <String, Object?>{
            'granted': true,
            'disclosureVersion': currentHomeGuideDisclosureVersion,
          };
        },
      );

      final status = await repository.read();

      expect(status, HomeGuideConsentStatus.granted);
      expect(payload, <String, Object?>{'action': 'read'});
    });

    test('fails closed for missing, stale, or malformed consent', () async {
      for (final response in <Object?>[
        null,
        <String, Object?>{'granted': true},
        <String, Object?>{'granted': true, 'disclosureVersion': 0},
        <String, Object?>{
          'granted': 'yes',
          'disclosureVersion': currentHomeGuideDisclosureVersion,
        },
      ]) {
        final repository = CloudFunctionHomeGuideConsentRepository(
          callable: (_) async => response,
        );
        expect(await repository.read(), HomeGuideConsentStatus.notGranted);
      }
    });

    test(
      'sends an exact versioned update and trusts only server response',
      () async {
        Map<String, Object?>? payload;
        final repository = CloudFunctionHomeGuideConsentRepository(
          callable: (value) async {
            payload = value;
            return <String, Object?>{
              'granted': false,
              'disclosureVersion': currentHomeGuideDisclosureVersion,
            };
          },
        );

        final status = await repository.update(granted: false);

        expect(status, HomeGuideConsentStatus.notGranted);
        expect(payload, <String, Object?>{
          'action': 'update',
          'granted': false,
          'disclosureVersion': currentHomeGuideDisclosureVersion,
        });
      },
    );
  });
}
