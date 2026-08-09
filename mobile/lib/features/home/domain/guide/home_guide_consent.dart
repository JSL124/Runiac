const int currentHomeGuideDisclosureVersion = 1;

enum HomeGuideConsentStatus { unknown, notGranted, granted }

abstract interface class HomeGuideConsentRepository {
  Future<HomeGuideConsentStatus> read();

  Future<HomeGuideConsentStatus> update({required bool granted});
}

class AlwaysGrantedHomeGuideConsentRepository
    implements HomeGuideConsentRepository {
  const AlwaysGrantedHomeGuideConsentRepository();

  @override
  Future<HomeGuideConsentStatus> read() async => HomeGuideConsentStatus.granted;

  @override
  Future<HomeGuideConsentStatus> update({required bool granted}) async =>
      granted
      ? HomeGuideConsentStatus.granted
      : HomeGuideConsentStatus.notGranted;
}
