import 'dart:async';

enum PushNotificationPlatform { android, apple, web }

enum PushNotificationPermissionStatus {
  authorized,
  denied,
  notDetermined,
  provisional,
}

class PushNotificationMessage {
  const PushNotificationMessage({
    required this.id,
    this.title,
    this.body,
    this.data = const {},
  });

  final String id;
  final String? title;
  final String? body;
  final Map<String, Object?> data;
}

abstract interface class PushNotificationClient {
  PushNotificationPlatform get platform;

  Future<PushNotificationPermissionStatus> requestPermission();

  Future<String?> getAppleApnsToken();

  Future<String?> getToken();

  Stream<String> get tokenRefreshes;

  Stream<PushNotificationMessage> get foregroundMessages;

  Stream<PushNotificationMessage> get openedMessages;

  Future<PushNotificationMessage?> getInitialMessage();
}

class RegisterNotificationDeviceRequest {
  const RegisterNotificationDeviceRequest({
    required this.uid,
    required this.token,
    required this.platform,
    this.appInstallationId,
  });

  final String uid;
  final String token;
  final PushNotificationPlatform platform;
  final String? appInstallationId;

  @override
  bool operator ==(Object other) {
    return other is RegisterNotificationDeviceRequest &&
        other.uid == uid &&
        other.token == token &&
        other.platform == platform &&
        other.appInstallationId == appInstallationId;
  }

  @override
  int get hashCode => Object.hash(uid, token, platform, appInstallationId);
}

class UnregisterNotificationDeviceRequest {
  const UnregisterNotificationDeviceRequest({
    required this.uid,
    required this.token,
  });

  final String uid;
  final String token;

  @override
  bool operator ==(Object other) {
    return other is UnregisterNotificationDeviceRequest &&
        other.uid == uid &&
        other.token == token;
  }

  @override
  int get hashCode => Object.hash(uid, token);
}

abstract interface class NotificationDeviceCallable {
  Future<void> registerDevice(RegisterNotificationDeviceRequest request);

  Future<void> unregisterDevice(UnregisterNotificationDeviceRequest request);
}

class NotificationRegistrationService {
  NotificationRegistrationService({
    required this.client,
    required this.callable,
    required this.ownerUidProvider,
    this.applePushRegistrationEnabled = false,
  });

  final PushNotificationClient client;
  final NotificationDeviceCallable callable;
  final String? Function() ownerUidProvider;
  final bool applePushRegistrationEnabled;
  final _messageController =
      StreamController<PushNotificationMessage>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  String? _currentToken;
  String? _currentUid;
  bool _started = false;

  /// Bumped by every teardown. A `start()` already in flight compares the
  /// generation it began with against this before it touches any state, so a
  /// sign-out that lands mid-registration cannot be undone by the slower call
  /// completing afterwards and re-arming `_started` and the previous owner's
  /// message subscriptions.
  int _generation = 0;

  /// The in-flight `_start()` call, if any. `start()` is called from three
  /// places in `app.dart` (initState, didUpdateWidget, the auth gate) and on
  /// a warm start two of them can land before the first `start()` resolves.
  /// `_started` alone can't gate that: it was only ever flipped true at the
  /// END of the sequence, so a second caller would sail through the
  /// `if (_started)` check and re-run permission/token registration and
  /// re-subscribe to every stream while the first call was still awaiting.
  /// Memoizing the future instead means every concurrent caller before the
  /// first completion awaits the SAME `_start()` run.
  Future<void>? _startFuture;

  Stream<PushNotificationMessage> get messages => _messageController.stream;

  Future<void> start() {
    if (_started) {
      return Future.value();
    }
    return _startFuture ??= _start().whenComplete(() {
      // Cleared unconditionally (success, early return, or failure) so a
      // start that didn't succeed can be genuinely retried by the next
      // caller instead of permanently returning the failed attempt's future.
      _startFuture = null;
    });
  }

  Future<void> _start() async {
    final generation = _generation;
    final startingUid = _currentOwnerUid();
    try {
      final registered = await registerCurrentDevice();
      if (!registered) {
        return;
      }
      // Two awaits have elapsed (permission, token, register). If the runner
      // signed out or switched accounts in that window, attaching here would
      // resurrect a torn-down session under the wrong owner.
      if (generation != _generation || _currentOwnerUid() != startingUid) {
        return;
      }

      _subscriptions
        ..add(
          client.tokenRefreshes.listen((token) {
            unawaited(_registerToken(token));
          }),
        )
        ..add(client.foregroundMessages.listen(_messageController.add))
        ..add(client.openedMessages.listen(_messageController.add));

      final initialMessage = await client.getInitialMessage();
      if (generation != _generation) {
        await _cancelSubscriptions();
        return;
      }
      if (initialMessage != null) {
        _messageController.add(initialMessage);
      }
      _started = true;
    } catch (_) {
      await _cancelSubscriptions();
      _started = false;
      rethrow;
    }
  }

  Future<bool> registerCurrentDevice() async {
    if (client.platform == PushNotificationPlatform.apple &&
        !applePushRegistrationEnabled) {
      return false;
    }

    final permission = await client.requestPermission();
    if (!_canRegister(permission)) {
      return false;
    }

    if (client.platform == PushNotificationPlatform.apple) {
      final apnsToken = await client.getAppleApnsToken();
      if (apnsToken == null || apnsToken.isEmpty) {
        return false;
      }
    }

    final token = await client.getToken();
    if (token == null || token.isEmpty) {
      return false;
    }

    await _registerToken(token);
    return _currentToken == token;
  }

  Future<void> unregisterCurrentDevice() async {
    // The uid this service is actually registered under, NOT whoever
    // `ownerUidProvider` names right now: during a sign-out that provider has
    // already dropped to null, and during an account switch it has already
    // moved on to the next runner.
    final previousUid = _currentUid ?? _currentOwnerUid();
    final registeredToken = _currentToken;

    // Local teardown happens first and unconditionally. The remote call is the
    // part that can fail — a sign-out while offline is the ordinary case — and
    // when it threw, the service kept the previous owner's FCM subscriptions
    // alive with `_started` still true. The next sign-in then re-attached the
    // app's listener to that same still-running stream while `start()` no-oped,
    // so a push addressed to the signed-out account was written into the new
    // account's inbox (the inbox repository resolves the owner uid at write
    // time). Isolating the device from the previous owner must not depend on
    // the network.
    //
    // Nothing above this block may await the platform either, for the same
    // reason. Resolving the token used to sit here, and on iOS
    // `FirebaseMessaging.getToken()` throws
    // `[firebase_messaging/apns-token-not-set]` when APNs has not handed the
    // device its token yet — a signed-in-then-signed-out session that never
    // reached that point skipped the whole teardown, and the throw escaped the
    // unawaited call in app.dart as a fatal uncaught error.
    _generation += 1;
    _currentUid = null;
    _started = false;
    _currentToken = null;
    await _cancelSubscriptions();

    if (previousUid == null) {
      return;
    }
    // `unregisterNotificationDevice` carries only the token: the server
    // resolves the owner from `request.auth.uid`. So this call disables the
    // device row of whoever is authenticated WHEN IT ARRIVES, not the runner it
    // was issued for — and an FCM token is per-device, so a runner who has
    // already signed in here shares it. Sending it anyway would silently
    // unregister the NEW runner's device. Skip instead: leaving the previous
    // owner's row enabled is recoverable (their next sign-in re-registers, and
    // the local teardown above already stops their pushes reaching this
    // inbox), whereas disabling the new owner's row is not.
    final ownerNow = _currentOwnerUid();
    if (ownerNow != null && ownerNow != previousUid) {
      return;
    }

    // Only reached when there is a device row worth disabling. A token cached
    // from registration is used as-is; asking the platform for one is
    // best-effort, because failing to tell the server about a sign-out is
    // recoverable (the row is re-registered on the next sign-in, and the
    // teardown above already stopped this device from receiving the previous
    // owner's pushes) while crashing on the way to it is not.
    final token = registeredToken ?? await _platformTokenOrNull();
    if (token == null || token.isEmpty) {
      return;
    }
    await callable.unregisterDevice(
      UnregisterNotificationDeviceRequest(uid: previousUid, token: token),
    );
  }

  Future<void> dispose() async {
    await _cancelSubscriptions();
    await _messageController.close();
  }

  // Deliberately catches everything rather than matching on the APNs error
  // code: this is the sign-out path, every caller of it treats a missing token
  // as "skip the remote call", and there is no failure here worth propagating
  // to a user who has already signed out.
  Future<String?> _platformTokenOrNull() async {
    try {
      return await client.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _cancelSubscriptions() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  bool _canRegister(PushNotificationPermissionStatus permission) {
    return permission == PushNotificationPermissionStatus.authorized ||
        permission == PushNotificationPermissionStatus.provisional;
  }

  Future<void> _registerToken(String token) async {
    final uid = _currentOwnerUid();
    if (uid == null || token.isEmpty) {
      return;
    }

    await callable.registerDevice(
      RegisterNotificationDeviceRequest(
        uid: uid,
        token: token,
        platform: client.platform,
      ),
    );
    _currentToken = token;
    _currentUid = uid;
  }

  String? _currentOwnerUid() {
    final uid = ownerUidProvider();
    if (uid == null || uid.isEmpty) {
      return null;
    }
    return uid;
  }
}
