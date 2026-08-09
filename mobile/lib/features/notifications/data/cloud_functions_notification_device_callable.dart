import 'package:cloud_functions/cloud_functions.dart';

import '../domain/services/notification_registration_service.dart';

class CloudFunctionsNotificationDeviceCallable
    implements NotificationDeviceCallable {
  CloudFunctionsNotificationDeviceCallable({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  @override
  Future<void> registerDevice(RegisterNotificationDeviceRequest request) async {
    await _functions.httpsCallable('registerNotificationDevice').call({
      'token': request.token,
      'platform': _platformName(request.platform),
      'appInstallationId': request.appInstallationId ?? request.uid,
      'now': _strictUtcInstantNow(),
    });
  }

  @override
  Future<void> unregisterDevice(
    UnregisterNotificationDeviceRequest request,
  ) async {
    await _functions.httpsCallable('unregisterNotificationDevice').call({
      'token': request.token,
      'now': _strictUtcInstantNow(),
    });
  }

  String _platformName(PushNotificationPlatform platform) {
    return switch (platform) {
      PushNotificationPlatform.android => 'android',
      PushNotificationPlatform.apple => 'ios',
      PushNotificationPlatform.web => 'web',
    };
  }

  String _strictUtcInstantNow() {
    final now = DateTime.now().toUtc();
    return DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();
  }
}
