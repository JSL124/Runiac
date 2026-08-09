import 'dart:async';

import 'package:runiac_app/features/notifications/domain/services/notification_registration_service.dart';

class FakePushNotificationClient implements PushNotificationClient {
  FakePushNotificationClient({
    this.platform = PushNotificationPlatform.android,
    required this.permissionStatus,
    this.apnsToken,
    this.token,
    this.initialMessage,
  });

  @override
  final PushNotificationPlatform platform;
  final PushNotificationPermissionStatus permissionStatus;
  String? apnsToken;
  String? token;
  // When set, getToken() throws instead of returning. Models
  // `[firebase_messaging/apns-token-not-set]`, which FirebaseMessaging raises
  // on iOS whenever APNs has not yet handed the device its token.
  Object? tokenError;
  final PushNotificationMessage? initialMessage;
  final _tokenRefreshController = StreamController<String>.broadcast();
  final _foregroundController =
      StreamController<PushNotificationMessage>.broadcast();
  final _openedController =
      StreamController<PushNotificationMessage>.broadcast();
  int permissionRequests = 0;
  int apnsTokenRequests = 0;
  int tokenRequests = 0;

  @override
  Future<PushNotificationPermissionStatus> requestPermission() async {
    permissionRequests += 1;
    return permissionStatus;
  }

  @override
  Future<String?> getAppleApnsToken() async {
    apnsTokenRequests += 1;
    return apnsToken;
  }

  @override
  Future<String?> getToken() async {
    tokenRequests += 1;
    final error = tokenError;
    if (error != null) {
      throw error;
    }
    return token;
  }

  @override
  Stream<String> get tokenRefreshes => _tokenRefreshController.stream;

  @override
  Stream<PushNotificationMessage> get foregroundMessages =>
      _foregroundController.stream;

  @override
  Stream<PushNotificationMessage> get openedMessages =>
      _openedController.stream;

  @override
  Future<PushNotificationMessage?> getInitialMessage() async {
    return initialMessage;
  }

  void emitTokenRefresh(String nextToken) {
    token = nextToken;
    _tokenRefreshController.add(nextToken);
  }

  void emitForegroundMessage(PushNotificationMessage message) {
    _foregroundController.add(message);
  }

  void emitOpenedMessage(PushNotificationMessage message) {
    _openedController.add(message);
  }
}

class FakeNotificationDeviceCallable implements NotificationDeviceCallable {
  FakeNotificationDeviceCallable({this.unregisterFails = false});

  /// Models a sign-out performed while offline: the remote call throws.
  bool unregisterFails;

  final registerCalls = <RegisterNotificationDeviceRequest>[];
  final unregisterCalls = <UnregisterNotificationDeviceRequest>[];

  @override
  Future<void> registerDevice(RegisterNotificationDeviceRequest request) async {
    registerCalls.add(request);
  }

  @override
  Future<void> unregisterDevice(
    UnregisterNotificationDeviceRequest request,
  ) async {
    unregisterCalls.add(request);
    if (unregisterFails) {
      throw StateError('unregisterDevice failed');
    }
  }
}
