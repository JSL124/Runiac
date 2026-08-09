import 'package:cloud_functions/cloud_functions.dart';

import '../domain/guide/home_guide_consent.dart';

typedef HomeGuideConsentCallable =
    Future<Object?> Function(Map<String, Object?> payload);

class CloudFunctionHomeGuideConsentRepository
    implements HomeGuideConsentRepository {
  CloudFunctionHomeGuideConsentRepository({
    FirebaseFunctions? functions,
    HomeGuideConsentCallable? callable,
  }) : _callable =
           callable ??
           _firebaseCallable(
             functions ??
                 FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
           );

  final HomeGuideConsentCallable _callable;

  @override
  Future<HomeGuideConsentStatus> read() async {
    try {
      final status = _statusFromResponse(
        await _callable(<String, Object?>{'action': 'read'}),
      );
      return status == HomeGuideConsentStatus.unknown
          ? HomeGuideConsentStatus.notGranted
          : status;
    } catch (_) {
      return HomeGuideConsentStatus.notGranted;
    }
  }

  @override
  Future<HomeGuideConsentStatus> update({required bool granted}) async {
    final status = _statusFromResponse(
      await _callable(<String, Object?>{
        'action': 'update',
        'granted': granted,
        'disclosureVersion': currentHomeGuideDisclosureVersion,
      }),
    );
    if (status == HomeGuideConsentStatus.unknown) {
      throw StateError('Home Guide consent response was invalid.');
    }
    return status;
  }

  static HomeGuideConsentCallable _firebaseCallable(
    FirebaseFunctions functions,
  ) {
    return (payload) async {
      final result = await functions
          .httpsCallable('homeGuideConsent')
          .call(payload);
      return result.data;
    };
  }

  HomeGuideConsentStatus _statusFromResponse(Object? data) {
    if (data is! Map<Object?, Object?> ||
        data['disclosureVersion'] != currentHomeGuideDisclosureVersion ||
        data['granted'] is! bool) {
      return HomeGuideConsentStatus.unknown;
    }
    return data['granted'] as bool
        ? HomeGuideConsentStatus.granted
        : HomeGuideConsentStatus.notGranted;
  }
}
