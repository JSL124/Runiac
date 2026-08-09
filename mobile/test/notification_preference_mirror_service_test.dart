import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/domain/models/notification_center_settings.dart';
import 'package:runiac_app/features/notifications/domain/repositories/notification_center_settings_repository.dart';
import 'package:runiac_app/features/notifications/domain/repositories/notification_preference_mirror.dart';
import 'package:runiac_app/features/notifications/domain/services/notification_preference_mirror_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NotificationPreferenceMirrorService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
      'mirrors the AND of the master toggle and the social toggle',
      () async {
        // Given: both the master toggle and the Social toggle are on.
        final settingsRepository = InMemoryNotificationCenterSettingsRepository(
          initialSettings: NotificationCenterSettings.defaults.copyWith(
            notificationsEnabled: true,
            socialActivityEnabled: true,
          ),
        );
        final mirror = _RecordingNotificationPreferenceMirror();
        final service = NotificationPreferenceMirrorService(
          settingsRepository: settingsRepository,
          mirror: mirror,
          ownerUidProvider: () => 'runner-1',
        );

        // When
        await service.syncSocialActivity();

        // Then
        expect(mirror.calls, [
          const _MirrorCall(uid: 'runner-1', socialActivityEnabled: true),
        ]);
      },
    );

    test('the master toggle being off forces the mirrored value to false', () async {
      // Given: the master toggle is off even though Social is individually on.
      final settingsRepository = InMemoryNotificationCenterSettingsRepository(
        initialSettings: NotificationCenterSettings.defaults.copyWith(
          notificationsEnabled: false,
          socialActivityEnabled: true,
        ),
      );
      final mirror = _RecordingNotificationPreferenceMirror();
      final service = NotificationPreferenceMirrorService(
        settingsRepository: settingsRepository,
        mirror: mirror,
        ownerUidProvider: () => 'runner-1',
      );

      // When
      await service.syncSocialActivity();

      // Then
      expect(mirror.calls, [
        const _MirrorCall(uid: 'runner-1', socialActivityEnabled: false),
      ]);
    });

    test('skips the write when the effective value is unchanged', () async {
      // Given: a service that has already mirrored the current effective
      // value once.
      final settingsRepository = InMemoryNotificationCenterSettingsRepository(
        initialSettings: NotificationCenterSettings.defaults.copyWith(
          notificationsEnabled: true,
          socialActivityEnabled: true,
        ),
      );
      final mirror = _RecordingNotificationPreferenceMirror();
      final service = NotificationPreferenceMirrorService(
        settingsRepository: settingsRepository,
        mirror: mirror,
        ownerUidProvider: () => 'runner-1',
      );
      await service.syncSocialActivity();
      expect(mirror.calls, hasLength(1));

      // When: syncing again with no change to the effective value.
      await service.syncSocialActivity();

      // Then: no second write happened.
      expect(mirror.calls, hasLength(1));
    });

    test('no-ops when the owner uid is null or empty', () async {
      // Given
      final settingsRepository = InMemoryNotificationCenterSettingsRepository(
        initialSettings: NotificationCenterSettings.defaults,
      );
      final mirror = _RecordingNotificationPreferenceMirror();
      String? uid;
      final service = NotificationPreferenceMirrorService(
        settingsRepository: settingsRepository,
        mirror: mirror,
        ownerUidProvider: () => uid,
      );

      // When: uid is null.
      await service.syncSocialActivity();
      // Then
      expect(mirror.calls, isEmpty);

      // When: uid is empty.
      uid = '';
      await service.syncSocialActivity();
      // Then
      expect(mirror.calls, isEmpty);
    });

    test('swallows a throwing mirror instead of rethrowing', () async {
      // Given
      final settingsRepository = InMemoryNotificationCenterSettingsRepository(
        initialSettings: NotificationCenterSettings.defaults,
      );
      final mirror = _ThrowingNotificationPreferenceMirror();
      final service = NotificationPreferenceMirrorService(
        settingsRepository: settingsRepository,
        mirror: mirror,
        ownerUidProvider: () => 'runner-1',
      );

      // When / Then: no exception escapes.
      await expectLater(service.syncSocialActivity(), completes);
    });

    test(
      'a failed mirror attempt is retried on the next sync instead of being '
      'remembered as done',
      () async {
        // Given: the mirror throws on the first attempt.
        final settingsRepository = InMemoryNotificationCenterSettingsRepository(
          initialSettings: NotificationCenterSettings.defaults,
        );
        final mirror = _ThrowingNotificationPreferenceMirror();
        final service = NotificationPreferenceMirrorService(
          settingsRepository: settingsRepository,
          mirror: mirror,
          ownerUidProvider: () => 'runner-1',
        );
        await service.syncSocialActivity();
        expect(mirror.attemptCount, 1);

        // When: syncing again with the same effective value.
        await service.syncSocialActivity();

        // Then: the service retried instead of treating the failed attempt
        // as already-mirrored.
        expect(mirror.attemptCount, 2);
      },
    );

    test(
      'the dedupe survives a fresh service instance reading the persisted '
      'last-mirrored key',
      () async {
        // Given: one service instance has already mirrored the effective
        // value for this uid, persisting the dedupe key to shared_preferences.
        final settingsRepository = InMemoryNotificationCenterSettingsRepository(
          initialSettings: NotificationCenterSettings.defaults.copyWith(
            notificationsEnabled: true,
            socialActivityEnabled: true,
          ),
        );
        final firstMirror = _RecordingNotificationPreferenceMirror();
        final firstService = NotificationPreferenceMirrorService(
          settingsRepository: settingsRepository,
          mirror: firstMirror,
          ownerUidProvider: () => 'runner-1',
        );
        await firstService.syncSocialActivity();
        expect(firstMirror.calls, hasLength(1));

        // When: a brand-new service instance (simulating a cold start, with
        // no in-memory dedupe state) syncs the same unchanged value.
        final secondMirror = _RecordingNotificationPreferenceMirror();
        final secondService = NotificationPreferenceMirrorService(
          settingsRepository: settingsRepository,
          mirror: secondMirror,
          ownerUidProvider: () => 'runner-1',
        );
        await secondService.syncSocialActivity();

        // Then: the persisted last-mirrored key prevented a redundant write.
        expect(secondMirror.calls, isEmpty);
      },
    );
  });
}

class _MirrorCall {
  const _MirrorCall({required this.uid, required this.socialActivityEnabled});

  final String uid;
  final bool socialActivityEnabled;

  @override
  bool operator ==(Object other) {
    return other is _MirrorCall &&
        other.uid == uid &&
        other.socialActivityEnabled == socialActivityEnabled;
  }

  @override
  int get hashCode => Object.hash(uid, socialActivityEnabled);

  @override
  String toString() =>
      '_MirrorCall(uid: $uid, socialActivityEnabled: $socialActivityEnabled)';
}

class _RecordingNotificationPreferenceMirror
    implements NotificationPreferenceMirror {
  final List<_MirrorCall> calls = <_MirrorCall>[];

  @override
  Future<void> mirror({
    required String uid,
    required bool socialActivityEnabled,
  }) async {
    calls.add(
      _MirrorCall(uid: uid, socialActivityEnabled: socialActivityEnabled),
    );
  }
}

class _ThrowingNotificationPreferenceMirror
    implements NotificationPreferenceMirror {
  var attemptCount = 0;

  @override
  Future<void> mirror({
    required String uid,
    required bool socialActivityEnabled,
  }) async {
    attemptCount += 1;
    throw StateError('mirror write failed');
  }
}
