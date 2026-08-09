import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../domain/services/notification_registration_service.dart';

class FirebaseMessagingPushNotificationClient
    implements PushNotificationClient {
  FirebaseMessagingPushNotificationClient({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  PushNotificationPlatform get platform {
    if (kIsWeb) {
      return PushNotificationPlatform.web;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS => PushNotificationPlatform.apple,
      _ => PushNotificationPlatform.android,
    };
  }

  @override
  Future<String?> getAppleApnsToken() {
    if (platform != PushNotificationPlatform.apple) {
      return Future<String?>.value();
    }
    return _messaging.getAPNSToken();
  }

  @override
  Future<String?> getToken() {
    return _messaging.getToken();
  }

  @override
  Future<PushNotificationMessage?> getInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    if (message == null) {
      return null;
    }
    return _fromRemoteMessage(message);
  }

  @override
  Stream<PushNotificationMessage> get foregroundMessages {
    return FirebaseMessaging.onMessage.map(_fromRemoteMessage);
  }

  @override
  Stream<PushNotificationMessage> get openedMessages {
    return FirebaseMessaging.onMessageOpenedApp.map(_fromRemoteMessage);
  }

  @override
  Future<PushNotificationPermissionStatus> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized =>
        PushNotificationPermissionStatus.authorized,
      AuthorizationStatus.provisional =>
        PushNotificationPermissionStatus.provisional,
      AuthorizationStatus.denied => PushNotificationPermissionStatus.denied,
      AuthorizationStatus.notDetermined =>
        PushNotificationPermissionStatus.notDetermined,
    };
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  PushNotificationMessage _fromRemoteMessage(RemoteMessage message) {
    return PushNotificationMessage(
      id:
          message.messageId ??
          message.sentTime?.millisecondsSinceEpoch.toString() ??
          '',
      title: message.notification?.title,
      body: message.notification?.body,
      data: message.data,
    );
  }
}
