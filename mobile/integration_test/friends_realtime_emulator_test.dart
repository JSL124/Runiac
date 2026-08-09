import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:runiac_app/core/firebase/runiac_firebase_bootstrap.dart';
import 'package:runiac_app/features/profile/data/firestore_user_profile_persistence_repository.dart';
import 'package:runiac_app/features/run/data/run_repository_factory.dart';
import 'package:runiac_app/features/you/presentation/widgets/you_segmented_control.dart';

import 'support/auth_emulator_flow_helpers.dart';

/// Proves the Friends real-time Firestore snapshot sync (see
/// `FirebaseFriendsRepository.watchFriendsOverview`, consumed by
/// `FriendsScreenController._subscribeToOverview`) actually delivers a live
/// update to an already-rendered screen with no re-navigation involved.
///
/// Two `FirebaseApp` instances share the same running emulator backend in a
/// single test process:
///   * "device B" is the DEFAULT app, driving the real `RuniacApp` widget
///     tree the way a user would see it.
///   * "device A" is a second named app (`deviceA`) that only ever talks to
///     Firebase directly (auth + the trusted `sendFriendRequest` callable),
///     standing in for a remote user's device. Device A never writes
///     Firestore directly for the friend-request mutation itself; the
///     `friendRequests` collections are server-owned and callable-mediated
///     (see `firestore.rules` `match /users/{uid} { allow create, update,
///     delete: if false; }` for the request/friend subcollections).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'incoming friend request from device A syncs live onto device B '
    'without re-navigating, and accepting it live-updates both tabs',
    (tester) async {
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final emailB = 'runiac-friends-b-$timestamp@example.test';
      final emailA = 'runiac-friends-a-$timestamp@example.test';
      const password = 'RuniacPass123!';
      const nicknameB = 'RunnerB';
      const nicknameA = 'RunnerA';

      // --- Device B: default app, real RuniacApp UI ------------------------
      final bootstrap = await RuniacFirebaseBootstrap.initialize(
        config: RuniacFirebaseRuntimeConfig(
          useFirebaseEmulator: true,
          emulatorHost: firebaseEmulatorHost,
        ),
        enableAnonymousEmulatorSignIn: false,
      );
      final authRepository = DiagnosticAuthRepository(bootstrap.authRepository);
      addTearDown(authRepository.signOut);
      await authRepository.signOut();

      final userB = await authRepository.createUserWithEmailAndPassword(
        email: emailB,
        password: password,
      );
      final bUid = userB.uid;

      // The `upsertNickname` callable requires a pre-existing
      // `userProfiles/{uid}` document (see
      // functions/src/friends/friendsNicknameService.ts `PROFILE_REQUIRED`).
      // Every field on that document is optional per `firestore.rules`
      // `validUserProfileCreateData()`, so an empty merge satisfies the
      // existence precondition without needing a full onboarding profile.
      final profileWriterB = FirestoreUserProfileDocumentWriter();
      await profileWriterB.mergeUserProfile(
        uid: bUid,
        data: const <String, Object>{},
      );
      await profileWriterB.upsertNickname(uid: bUid, nickname: nicknameB);

      // showOnboarding:false + showAuth:false skips the 16-step onboarding
      // and the auth gate entirely (RuniacApp._shouldShowOnboarding is false,
      // RuniacAuthGate.build short-circuits to childBuilder when
      // showAuth is false) and lands directly on RuniacShell's Home tab
      // (RuniacShell._selectedIndex defaults to 0 == HomeTab), since B is
      // already signed in above.
      await pumpRuniac(
        tester,
        bootstrap,
        authRepository: authRepository,
        showAuth: false,
        showOnboarding: false,
      );

      // Home -> Menu -> Friends -> Requests tab.
      // (lib/features/home/presentation/stage_map/home_stage_map_menu.dart
      // `_HomeMenuTrigger` renders the plain Text 'Menu'; the opened
      // `_HomeMenuPanel` renders a `_HomeMenuItem` with label 'Friends';
      // `FriendsScreen`'s `YouSegmentedControl` tab renders the plain Text
      // 'Requests' for tab index 2.)
      await tapVisibleText(tester, 'Menu');
      await tapVisibleText(tester, 'Friends');
      await tapVisibleText(tester, 'Requests');

      // Baseline: no incoming request yet.
      // (FriendsRequestsTab renders FriendsEmptyState(title: 'No pending
      // requests') when both incoming and outgoing lists are empty.)
      await waitForText(
        tester,
        'No pending requests',
        reason:
            'device B should reach the Requests tab with zero pending '
            'requests before device A sends anything',
        diagnostics: authRepository.diagnostics,
      );
      expect(find.text('No pending requests'), findsOneWidget);
      expect(find.text(nicknameA), findsNothing);

      // --- Device A: second named app, remote writer via callables only ----
      final deviceA = await Firebase.initializeApp(
        name: 'deviceA',
        options: RuniacFirebaseBootstrap.emulatorFirebaseOptions,
      );
      final authA = FirebaseAuth.instanceFor(app: deviceA);
      await authA.useAuthEmulator(firebaseEmulatorHost, 9099);
      final functionsA = FirebaseFunctions.instanceFor(
        app: deviceA,
        region: 'asia-southeast1',
      );
      functionsA.useFunctionsEmulator(firebaseEmulatorHost, 5001);
      final firestoreA = FirebaseFirestore.instanceFor(app: deviceA);
      firestoreA.useFirestoreEmulator(firebaseEmulatorHost, 8080);

      addTearDown(() async {
        try {
          await authA.signOut();
        } catch (_) {
          // Best-effort teardown; ignore if already signed out.
        }
        await deviceA.delete();
      });

      final credentialA = await authA.createUserWithEmailAndPassword(
        email: emailA,
        password: password,
      );
      final aUid = credentialA.user!.uid;

      final profileWriterA = FirestoreUserProfileDocumentWriter(
        firestore: firestoreA,
        functions: functionsA,
      );
      await profileWriterA.mergeUserProfile(
        uid: aUid,
        data: const <String, Object>{},
      );
      await profileWriterA.upsertNickname(uid: aUid, nickname: nicknameA);

      // Device A must not write `users/{b}/friendRequests/{a}` directly:
      // `firestore.rules` denies client writes to that subcollection
      // (`match /users/{uid} { allow create, update, delete: if false; }`).
      // The trusted `sendFriendRequest` callable is the only legal path; it
      // denormalizes device A's `nickname`/`displayName`/`avatarInitials`
      // onto both the outgoing (`users/A/friendRequests/B`) and incoming
      // (`users/B/friendRequests/A`) documents server-side.
      await functionsA.httpsCallable('sendFriendRequest').call(
        <String, Object?>{'targetUid': bUid},
      );

      // Assertion 1 (core proof): without re-navigating device B's UI at
      // all since the "No pending requests" assertion above, the live
      // `watchFriendsOverview` snapshot subscription should push the new
      // incoming request onto the already-rendered Requests tab.
      await waitForText(
        tester,
        nicknameA,
        reason:
            'device A\'s sendFriendRequest should sync live onto device '
            'B\'s already-rendered Requests tab with no re-navigation',
        diagnostics: authRepository.diagnostics,
      );
      expect(find.text(nicknameA), findsOneWidget);
      expect(find.text('No pending requests'), findsNothing);

      final acceptFinder = find.bySemanticsLabel('Accept $nicknameA');
      expect(
        acceptFinder,
        findsOneWidget,
        reason:
            'FriendRequestRow should render an "Accept $nicknameA" '
            'affordance for the live incoming request',
      );

      // Assertion 2 (accept path): tap the accept affordance on the live
      // request row (FriendRequestRow -> _RequestPill wraps a
      // RuniacTappableSurface with semanticLabel 'Accept ${displayName}').
      // This calls FriendsRepository.respondToFriendRequest, the trusted
      // callable, from device B's own functions instance.
      await tester.ensureVisible(acceptFinder);
      await tester.tap(acceptFinder);

      // Live disappearance from the Requests tab, still with no
      // re-navigation: the accepted request should drop out of both the
      // one-shot post-mutation refresh and the ongoing live subscription.
      await waitForTextGone(
        tester,
        nicknameA,
        reason:
            'accepting the request should live-remove it from device B\'s '
            'Requests tab without re-navigating',
        diagnostics: authRepository.diagnostics,
      );
      expect(find.text('No pending requests'), findsOneWidget);

      // Friend-list assertion: switching to the Friends tab within the same
      // already-open FriendsScreen (not a re-navigation to a new screen) to
      // confirm RunnerA now appears as an accepted friend. FriendsScreen
      // renders the text 'Friends' twice here — the RuniacBackHeader title
      // (friends_screen.dart:114) AND the YouSegmentedControl tab label
      // (index 0 of _kFriendsTabLabels) — so scope the finder to the
      // segmented control to tap the tab unambiguously.
      final friendsTabFinder = find.descendant(
        of: find.byType(YouSegmentedControl),
        matching: find.text('Friends'),
      );
      expect(friendsTabFinder, findsOneWidget);
      await tester.ensureVisible(friendsTabFinder);
      await tester.tap(friendsTabFinder);
      await tester.pumpAndSettle();
      await waitForText(
        tester,
        nicknameA,
        reason:
            'RunnerA should appear in the Friends tab as an accepted '
            'friend after the accept callable resolves',
        diagnostics: authRepository.diagnostics,
      );
      expect(find.text(nicknameA), findsOneWidget);
    },
  );
}
