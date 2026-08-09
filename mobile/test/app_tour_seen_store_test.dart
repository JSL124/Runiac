import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/tutorial/data/shared_preferences_app_tour_seen_store.dart';
import 'package:runiac_app/features/tutorial/domain/app_tour_seen_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('preference key builders', () {
    test('build a scoped key for a real uid', () {
      expect(appTourArmedPreferenceKey('user-123'), 'app_tour_armed_user-123');
      expect(
        appTourCompletedPreferenceKey('user-123'),
        'app_tour_completed_user-123',
      );
    });

    test('fall back to "anonymous" for null or empty uid', () {
      expect(appTourArmedPreferenceKey(null), 'app_tour_armed_anonymous');
      expect(appTourArmedPreferenceKey(''), 'app_tour_armed_anonymous');
      expect(
        appTourCompletedPreferenceKey(null),
        'app_tour_completed_anonymous',
      );
      expect(
        appTourCompletedPreferenceKey(''),
        'app_tour_completed_anonymous',
      );
    });
  });

  group('InMemoryAppTourSeenStore', () {
    test('armed and completed default to false', () async {
      final store = InMemoryAppTourSeenStore();
      expect(await store.isArmed(uid: 'a'), isFalse);
      expect(await store.isCompleted(uid: 'a'), isFalse);
    });

    test('armed and completed are stored independently', () async {
      final store = InMemoryAppTourSeenStore();
      await store.setArmed(uid: 'a', armed: true);

      expect(await store.isArmed(uid: 'a'), isTrue);
      expect(await store.isCompleted(uid: 'a'), isFalse);

      await store.markCompleted(uid: 'a');

      expect(await store.isArmed(uid: 'a'), isTrue);
      expect(await store.isCompleted(uid: 'a'), isTrue);
    });

    test('flags are scoped per-uid', () async {
      final store = InMemoryAppTourSeenStore();
      await store.setArmed(uid: 'user-a', armed: true);
      await store.markCompleted(uid: 'user-a');

      expect(await store.isArmed(uid: 'user-b'), isFalse);
      expect(await store.isCompleted(uid: 'user-b'), isFalse);
      expect(await store.isArmed(uid: 'user-a'), isTrue);
      expect(await store.isCompleted(uid: 'user-a'), isTrue);
    });

    test('null and empty uid share the anonymous scope', () async {
      final store = InMemoryAppTourSeenStore();
      await store.setArmed(uid: null, armed: true);

      expect(await store.isArmed(uid: ''), isTrue);
    });

    test('setArmed(false) after setArmed(true) reads back false', () async {
      final store = InMemoryAppTourSeenStore();
      await store.setArmed(uid: 'a', armed: true);
      expect(await store.isArmed(uid: 'a'), isTrue);

      await store.setArmed(uid: 'a', armed: false);
      expect(await store.isArmed(uid: 'a'), isFalse);
    });
  });

  group('SharedPreferencesAppTourSeenStore', () {
    // Deliberately does not call SharedPreferences.setMockInitialValues
    // anywhere in this file, so the platform channel has no mock handler
    // registered and every call below exercises the MissingPluginException
    // fallback path rather than throwing.
    const store = SharedPreferencesAppTourSeenStore();

    test('isArmed returns false when the platform plugin is unavailable', () async {
      expect(await store.isArmed(uid: 'a'), isFalse);
    });

    test(
      'isCompleted returns false when the platform plugin is unavailable',
      () async {
        expect(await store.isCompleted(uid: 'a'), isFalse);
      },
    );

    test('setArmed no-ops when the platform plugin is unavailable', () async {
      await store.setArmed(uid: 'a', armed: true);
      expect(await store.isArmed(uid: 'a'), isFalse);
    });

    test(
      'markCompleted no-ops when the platform plugin is unavailable',
      () async {
        await store.markCompleted(uid: 'a');
        expect(await store.isCompleted(uid: 'a'), isFalse);
      },
    );
  });
}
