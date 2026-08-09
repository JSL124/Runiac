import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/observability/error_report.dart';
import 'package:runiac_app/core/observability/flutterfire_report_app_error_callable.dart';
import 'package:runiac_app/core/observability/local_pending_error_report_store.dart';
import 'package:runiac_app/core/observability/runiac_error_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('RuniacErrorReporter', () {
    test(
      'buffers a report and never calls the callable while signed out',
      () async {
        final store = MemoryLocalPendingErrorReportStore();
        final callable = _FakeReportAppErrorCallable();
        final authSource = _FakeAuthSource(initialUid: null);
        final reporter = _buildReporter(
          store: store,
          callable: callable,
          authSource: authSource,
        );
        addTearDown(reporter.dispose);

        await reporter.reportError(StateError('boom'), StackTrace.current);

        expect(callable.calls, isEmpty);
        expect(await store.load(), hasLength(1));
      },
    );

    test('sends the failing operation in the reported payload', () async {
      final store = MemoryLocalPendingErrorReportStore();
      final callable = _FakeReportAppErrorCallable();
      final authSource = _FakeAuthSource(initialUid: 'uid-1');
      final reporter = _buildReporter(
        store: store,
        callable: callable,
        authSource: authSource,
      );
      addTearDown(reporter.dispose);

      await reporter.reportError(
        StateError('boom'),
        StackTrace.current,
        context: 'completing a run (runSessionId=local-run-7)',
      );

      // Without this the payload would carry only "Bad state: boom", which
      // does not say which stage of the completion flow failed.
      expect(
        callable.calls.single['message'],
        'Bad state: boom | completing a run (runSessionId=local-run-7)',
      );
    });

    test('flushes the buffer once a uid appears', () async {
      final store = MemoryLocalPendingErrorReportStore();
      final callable = _FakeReportAppErrorCallable();
      final authSource = _FakeAuthSource(initialUid: null);
      final reporter = _buildReporter(
        store: store,
        callable: callable,
        authSource: authSource,
      );
      addTearDown(reporter.dispose);

      await reporter.reportError(StateError('boom'), StackTrace.current);
      expect(callable.calls, isEmpty);

      authSource.emitUid('uid-1');
      await _pump();

      expect(callable.calls, hasLength(1));
      expect(callable.calls.single['message'], 'Bad state: boom');
      expect(await store.load(), isEmpty);
    });

    test('reportError returns normally when the callable throws', () async {
      final store = MemoryLocalPendingErrorReportStore();
      final callable = _FakeReportAppErrorCallable(
        error: const ReportAppErrorException(
          code: 'unavailable',
          message: 'down for maintenance',
        ),
      );
      final authSource = _FakeAuthSource(initialUid: 'uid-1');
      final reporter = _buildReporter(
        store: store,
        callable: callable,
        authSource: authSource,
      );
      addTearDown(reporter.dispose);

      await expectLater(
        reporter.reportError(StateError('boom'), StackTrace.current),
        completes,
      );

      expect(callable.calls, hasLength(1));
      // The callable threw before the store was updated, so the report is
      // still buffered for the next flush attempt.
      expect(await store.load(), hasLength(1));
    });

    test(
      'does not propagate when the error object itself fails to sanitise',
      () async {
        final store = MemoryLocalPendingErrorReportStore();
        final callable = _FakeReportAppErrorCallable();
        final authSource = _FakeAuthSource(initialUid: 'uid-1');
        final reporter = _buildReporter(
          store: store,
          callable: callable,
          authSource: authSource,
        );
        addTearDown(reporter.dispose);

        await expectLater(
          reporter.reportError(_ThrowsOnToString(), StackTrace.current),
          completes,
        );

        // Nothing sensible could be built, so nothing was enqueued or sent.
        expect(callable.calls, isEmpty);
        expect(await store.load(), isEmpty);
      },
    );

    test('strips SDK/plugin frames and caps at 8 app frames', () async {
      final store = MemoryLocalPendingErrorReportStore();
      final callable = _FakeReportAppErrorCallable();
      final authSource = _FakeAuthSource(initialUid: 'uid-1');
      final reporter = _buildReporter(
        store: store,
        callable: callable,
        authSource: authSource,
      );
      addTearDown(reporter.dispose);

      final frames = <String>[
        'package:flutter/src/widgets/framework.dart 100:10 build',
        for (var i = 0; i < 10; i++)
          'package:runiac_app/features/run/run_screen.dart $i:1 method$i',
        'dart:async-patch/async_patch.dart 1:1 runZoned',
      ];
      final stackTrace = StackTrace.fromString(frames.join('\n'));

      await reporter.reportError(StateError('mixed'), stackTrace);

      final sentFrames =
          callable.calls.single['stackFrames'] as List<Object?>;
      expect(sentFrames, hasLength(8));
      expect(
        sentFrames.every(
          (frame) => (frame as String).contains('package:runiac_app/'),
        ),
        isTrue,
      );
    });

    test('caps the message at 200 characters', () async {
      final store = MemoryLocalPendingErrorReportStore();
      final callable = _FakeReportAppErrorCallable();
      final authSource = _FakeAuthSource(initialUid: 'uid-1');
      final reporter = _buildReporter(
        store: store,
        callable: callable,
        authSource: authSource,
      );
      addTearDown(reporter.dispose);

      await reporter.reportError(
        StateError('x' * 400),
        StackTrace.current,
      );

      final message = callable.calls.single['message'] as String;
      expect(message.length, 200);
    });

    test('sends exactly the allowlisted payload keys', () async {
      final store = MemoryLocalPendingErrorReportStore();
      final callable = _FakeReportAppErrorCallable();
      final authSource = _FakeAuthSource(initialUid: 'uid-1');
      final reporter = _buildReporter(
        store: store,
        callable: callable,
        authSource: authSource,
      );
      addTearDown(reporter.dispose);

      await reporter.reportError(
        StateError('boom'),
        StackTrace.current,
        screen: 'HomeScreen',
        fatal: true,
      );

      expect(callable.calls.single.keys.toSet(), {
        'errorType',
        'message',
        'stackFrames',
        'screen',
        'appVersion',
        'osVersion',
        'platform',
        'fatal',
        'occurredAt',
      });
      expect(callable.calls.single['screen'], 'HomeScreen');
      expect(callable.calls.single['fatal'], isTrue);
    });

    test(
      'a permanently rejected report is dropped so the report behind it '
      'still delivers',
      () async {
        final store = MemoryLocalPendingErrorReportStore();
        final callable = _SequencedReportAppErrorCallable([
          const ReportAppErrorException(
            code: 'invalid-argument',
            message: 'bad payload',
          ),
          null,
        ]);
        final authSource = _FakeAuthSource(initialUid: null);
        final reporter = _buildReporter(
          store: store,
          callable: callable,
          authSource: authSource,
        );
        addTearDown(reporter.dispose);

        await reporter.reportError(
          StateError('poison'),
          StackTrace.current,
          screen: 'ScreenA',
        );
        await reporter.reportError(
          StateError('behind'),
          StackTrace.current,
          screen: 'ScreenB',
        );
        // Still signed out: both reports are queued, nothing sent yet.
        expect(callable.calls, isEmpty);
        expect(await store.load(), hasLength(2));

        authSource.emitUid('uid-1');
        await _pump();

        expect(callable.calls, hasLength(2));
        // The poison report was dropped and the one behind it delivered, so
        // the buffer is fully drained.
        expect(await store.load(), isEmpty);
      },
    );

    test(
      'a transient failure stops the drain and leaves the queue intact for retry',
      () async {
        final store = MemoryLocalPendingErrorReportStore();
        final callable = _SequencedReportAppErrorCallable([
          const ReportAppErrorException(
            code: 'resource-exhausted',
            message: 'slow down',
          ),
          null,
          null,
        ]);
        final authSource = _FakeAuthSource(initialUid: null);
        final reporter = _buildReporter(
          store: store,
          callable: callable,
          authSource: authSource,
        );
        addTearDown(reporter.dispose);

        await reporter.reportError(
          StateError('first'),
          StackTrace.current,
          screen: 'ScreenA',
        );
        await reporter.reportError(
          StateError('second'),
          StackTrace.current,
          screen: 'ScreenB',
        );
        expect(await store.load(), hasLength(2));

        authSource.emitUid('uid-1');
        await _pump();

        // The transient failure on the first report stopped the drain: both
        // reports are still queued, and only one attempt was made.
        expect(callable.calls, hasLength(1));
        expect(await store.load(), hasLength(2));

        // A later retry succeeds for both, in order, and nothing was lost.
        await reporter.flushPending();

        expect(callable.calls, hasLength(3));
        expect(await store.load(), isEmpty);
      },
    );

    test(
      'two distinct errors raised while a flush is in flight are both enqueued',
      () async {
        final store = MemoryLocalPendingErrorReportStore();
        final callable = _GatedReportAppErrorCallable();
        final authSource = _FakeAuthSource(initialUid: 'uid-1');
        final reporter = _buildReporter(
          store: store,
          callable: callable,
          authSource: authSource,
        );
        addTearDown(reporter.dispose);

        final first = reporter.reportError(
          StateError('first'),
          StackTrace.current,
          screen: 'ScreenA',
        );
        await _pump();
        // The first flush is now blocked inside the (gated) network call.
        expect(callable.calls, hasLength(1));

        final second = reporter.reportError(
          StateError('second'),
          StackTrace.current,
          screen: 'ScreenB',
        );
        await _pump();

        final pendingWhileBlocked = await store.load();
        expect(
          pendingWhileBlocked.map((report) => report.message).toSet(),
          {'Bad state: first', 'Bad state: second'},
        );

        callable.release();
        await Future.wait([first, second]);
        await _pump();

        // The report enqueued while the first send was in flight must not
        // be lost to a stale-snapshot overwrite: both are eventually
        // delivered and the durable buffer ends up empty.
        expect(
          callable.calls.map((call) => call['message']).toSet(),
          {'Bad state: first', 'Bad state: second'},
        );
        expect(await store.load(), isEmpty);
      },
    );

    test(
      'suppresses an identical duplicate error within the window, and '
      're-enables reporting once the window elapses',
      () async {
        final store = MemoryLocalPendingErrorReportStore();
        final callable = _FakeReportAppErrorCallable();
        final authSource = _FakeAuthSource(initialUid: null);
        var now = DateTime.utc(2026, 1, 1);
        final reporter = _buildReporter(
          store: store,
          callable: callable,
          authSource: authSource,
          clock: () => now,
        );
        addTearDown(reporter.dispose);

        for (var i = 0; i < 100; i++) {
          await reporter.reportError(
            StateError('loop-$i'),
            StackTrace.current,
            screen: 'HomeScreen',
          );
        }

        // One hundred reports of the "same" error (same errorType, screen,
        // and — since these traces carry no `package:runiac_app/` frame —
        // the same empty first-frame signature) enqueue exactly once.
        expect(await store.load(), hasLength(1));

        now = now.add(const Duration(seconds: 31));
        await reporter.reportError(
          StateError('loop-after-window'),
          StackTrace.current,
          screen: 'HomeScreen',
        );

        expect(await store.load(), hasLength(2));
      },
    );

    test('a reentrant reportError call while one is in flight is ignored', () async {
      final store = MemoryLocalPendingErrorReportStore();
      final callable = _FakeReportAppErrorCallable();
      final authSource = _FakeAuthSource(initialUid: null);
      final reporter = _buildReporter(
        store: store,
        callable: callable,
        authSource: authSource,
      );
      addTearDown(reporter.dispose);

      final first = reporter.reportError(
        StateError('first'),
        StackTrace.current,
      );
      final second = reporter.reportError(
        StateError('second'),
        StackTrace.current,
      );
      await Future.wait([first, second]);

      final saved = await store.load();
      expect(saved, hasLength(1));
      expect(saved.single.message, contains('first'));
    });

    test(
      'constructing with no injected dependencies and no Firebase app does '
      'not throw, and reportError/flushPending complete and leave the '
      'report buffered',
      () async {
        // The default store (SharedPreferencesLocalPendingErrorReportStore)
        // needs its platform channel mocked to work at all under
        // flutter_test; nothing here mocks Firebase, which is the point —
        // this exercises the exact "no Firebase app exists yet" startup
        // path (e.g. a plain `flutter run` with no dart-defines) that used
        // to crash because `FlutterFireReportAppErrorCallable()` and
        // `FirebaseAuthErrorReporterAuthSource()` were built eagerly in the
        // constructor's initializer list.
        SharedPreferences.setMockInitialValues(<String, Object>{});

        late final RuniacErrorReporter reporter;
        expect(() => reporter = RuniacErrorReporter(), returnsNormally);
        addTearDown(reporter.dispose);

        await expectLater(
          reporter.reportError(StateError('no firebase yet'), StackTrace.current),
          completes,
        );
        await expectLater(reporter.flushPending(), completes);

        const store = SharedPreferencesLocalPendingErrorReportStore();
        final pending = await store.load();
        expect(pending, hasLength(1));
        expect(pending.single.message, contains('no firebase yet'));
      },
    );

    test(
      'a report enqueued while the flush loop is mid remove-step is not '
      'lost and is not resent',
      () async {
        final seed = ErrorReport(
          errorType: 'StateError',
          message: 'seed',
          stackFrames: const <String>[],
          screen: 'unknown',
          appVersion: '1.0.0+1',
          osVersion: 'test-os',
          platform: 'test-platform',
          fatal: false,
          occurredAt: DateTime.utc(2026, 1, 1),
        );
        final store = _RemoveStepGatedStore(<ErrorReport>[seed]);
        final callable = _FakeReportAppErrorCallable();
        final authSource = _FakeAuthSource(initialUid: 'uid-1');
        final reporter = _buildReporter(
          store: store,
          callable: callable,
          authSource: authSource,
        );
        addTearDown(reporter.dispose);

        // Pause right after the *second* `load()` call — the flush loop's
        // re-read immediately before it removes the just-sent head — so a
        // concurrent enqueue can be attempted while that remove step is
        // still in flight.
        store.pauseAfterLoadNumber(2);
        final flushFuture = reporter.flushPending();
        await _pump();

        // The seed was already sent; the remove step's re-read is paused
        // before its save, so the store still shows the seed present.
        expect(callable.calls, hasLength(1));
        expect(store.snapshot, hasLength(1));

        final reportFuture = reporter.reportError(
          StateError('concurrent'),
          StackTrace.current,
          screen: 'ScreenB',
        );
        await _pump();
        // The concurrent enqueue must queue behind the paused remove step
        // rather than racing its load/save pair.
        expect(store.snapshot, hasLength(1));

        store.release();
        await Future.wait([flushFuture, reportFuture]);
        await _pump();

        // Both reports were sent, in order, exactly once each, and nothing
        // was lost or reintroduced.
        expect(
          callable.calls.map((call) => call['message']).toList(),
          <String>['seed', 'Bad state: concurrent'],
        );
        expect(await store.load(), isEmpty);
      },
    );

    test(
      'a report with no named screen and no matching stack frame still '
      'sends "unknown", never null or empty',
      () async {
        final store = MemoryLocalPendingErrorReportStore();
        final callable = _FakeReportAppErrorCallable();
        final authSource = _FakeAuthSource(initialUid: 'uid-1');
        final reporter = _buildReporter(
          store: store,
          callable: callable,
          authSource: authSource,
        );
        addTearDown(reporter.dispose);

        // `StackTrace.current` from inside this test file carries no
        // `package:runiac_app/` frame, and no `screen` is passed — the
        // worst case the tracker can hand the reporter in this app today.
        await reporter.reportError(StateError('boom'), StackTrace.current);

        expect(callable.calls.single['screen'], 'unknown');
      },
    );
  });

  group('composeErrorReportMessage', () {
    test('returns the error text alone when there is no context', () {
      expect(
        composeErrorReportMessage('Bad state: something broke', null),
        'Bad state: something broke',
      );
      expect(
        composeErrorReportMessage('Bad state: something broke', '   '),
        'Bad state: something broke',
      );
    });

    test('appends the failing operation so the stage is identifiable', () {
      expect(
        composeErrorReportMessage(
          'Bad state: remote completeRun refused the run',
          'completing a run (runSessionId=local-run-1-2-3)',
        ),
        'Bad state: remote completeRun refused the run | '
        'completing a run (runSessionId=local-run-1-2-3)',
      );
    });

    test('truncates the error text rather than losing the operation', () {
      final composed = composeErrorReportMessage(
        'E' * 400,
        'completing a run',
        maxLength: 60,
      );

      expect(composed.length, 60);
      // The operation label is the part that says which stage failed, so it
      // must survive a long exception dump intact.
      expect(composed, endsWith(' | completing a run'));
      expect(composed, startsWith('EEE'));
    });

    test('keeps the operation when it alone exceeds the cap', () {
      final composed = composeErrorReportMessage(
        'Bad state: broke',
        'C' * 400,
        maxLength: 60,
      );

      expect(composed.length, 60);
      expect(composed, 'C' * 60);
    });
  });

  group('resolveErrorReportScreen', () {
    test('never returns null or empty', () {
      expect(resolveErrorReportScreen(null, const <String>[]), isNotEmpty);
      expect(resolveErrorReportScreen('', const <String>[]), isNotEmpty);
      expect(resolveErrorReportScreen('   ', const <String>[]), isNotEmpty);
    });

    test('falls back to "unknown" with no tracker name and no frames', () {
      expect(
        resolveErrorReportScreen(null, const <String>[]),
        unknownErrorReportScreen,
      );
    });

    test('prefers a real tracker-provided route name when present', () {
      expect(
        resolveErrorReportScreen('/home', const <String>[
          'package:runiac_app/features/run/run_screen.dart:3:1',
        ]),
        '/home',
      );
    });

    test(
      'derives a path-shaped label from a realistic Dart stack frame',
      () {
        final label = resolveErrorReportScreen(null, const <String>[
          '#0      RunSummaryController.build '
              '(package:runiac_app/features/run/run_summary_controller.dart:42:10)',
        ]);

        expect(label, 'features/run/run_summary_controller');
      },
    );

    test(
      'derives a path-shaped label from the fabricated frame shape used '
      'elsewhere in this suite',
      () {
        final label = resolveErrorReportScreen(null, const <String>[
          'package:runiac_app/features/run/run_screen.dart 3:1 method3',
        ]);

        expect(label, 'features/run/run_screen');
      },
    );

    test(
      'keeps the trailing 60 characters of an over-long derived label and '
      'still matches the server pattern',
      () {
        final longSegment = 'a' * 80;
        final label = resolveErrorReportScreen(null, <String>[
          'package:runiac_app/features/run/$longSegment/controller.dart:1:1)',
        ]);

        expect(label.length, 60);
        expect(
          label,
          'features/run/$longSegment/controller'.substring(
            'features/run/$longSegment/controller'.length - 60,
          ),
        );
        expect(RegExp(r'^[A-Za-z0-9 /_-]{1,60}$').hasMatch(label), isTrue);
      },
    );

    test('strips characters outside the server allowlist', () {
      final label = resolveErrorReportScreen(
        r'weird$screen<name>?',
        const <String>[],
      );

      expect(RegExp(r'^[A-Za-z0-9 /_-]{1,60}$').hasMatch(label), isTrue);
      expect(label, 'weirdscreenname');
    });
  });
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

RuniacErrorReporter _buildReporter({
  required LocalPendingErrorReportStore store,
  required ReportAppErrorCallable callable,
  required _FakeAuthSource authSource,
  DateTime Function()? clock,
}) {
  return RuniacErrorReporter(
    store: store,
    callable: callable,
    authSource: authSource,
    appVersionResolver: () => '1.0.0+1',
    osVersionResolver: () => 'test-os',
    platformResolver: () => 'test-platform',
    clock: clock ?? (() => DateTime.utc(2026, 1, 1)),
  );
}

class _FakeAuthSource implements ErrorReporterAuthSource {
  _FakeAuthSource({String? initialUid}) : _currentUid = initialUid;

  String? _currentUid;
  final StreamController<String?> _controller =
      StreamController<String?>.broadcast();

  @override
  String? get currentUid => _currentUid;

  @override
  Stream<String?> get uidChanges => _controller.stream;

  void emitUid(String? uid) {
    _currentUid = uid;
    _controller.add(uid);
  }
}

class _FakeReportAppErrorCallable implements ReportAppErrorCallable {
  _FakeReportAppErrorCallable({this.error});

  final ReportAppErrorException? error;
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    calls.add(request);
    if (error != null) {
      throw error!;
    }
    return <String, Object?>{'groupId': 'group-1'};
  }
}

class _ThrowsOnToString {
  @override
  String toString() => throw StateError('cannot describe this error');
}

/// Returns a preset sequence of outcomes, one per call: `null` succeeds, a
/// non-null exception is thrown. Once the sequence is exhausted, further
/// calls succeed.
class _SequencedReportAppErrorCallable implements ReportAppErrorCallable {
  _SequencedReportAppErrorCallable(this._outcomes);

  final List<ReportAppErrorException?> _outcomes;
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
  var _index = 0;

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    calls.add(request);
    final outcome = _index < _outcomes.length ? _outcomes[_index] : null;
    _index += 1;
    if (outcome != null) {
      throw outcome;
    }
    return <String, Object?>{'groupId': 'group-1'};
  }
}

/// Records every call, then blocks until [release] is called — used to hold
/// a flush open mid-network-call so a second, concurrent `reportError` can
/// be exercised against it.
class _GatedReportAppErrorCallable implements ReportAppErrorCallable {
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
  final Completer<void> _gate = Completer<void>();

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    calls.add(request);
    await _gate.future;
    return <String, Object?>{'groupId': 'group-1'};
  }

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }
}

/// An in-memory store whose [load] can be paused, once, right after a
/// chosen call number — used to hold `RuniacErrorReporter._flush`'s
/// remove-step load open so a concurrent enqueue can be attempted while it
/// is still in flight, proving the two are serialized rather than racing.
class _RemoveStepGatedStore implements LocalPendingErrorReportStore {
  _RemoveStepGatedStore(List<ErrorReport> initial)
    : _reports = List<ErrorReport>.of(initial);

  List<ErrorReport> _reports;
  int _loadCount = 0;
  int? _pauseAtLoadNumber;
  Completer<void>? _gate;

  @override
  Future<List<ErrorReport>> load() async {
    _loadCount += 1;
    final snapshot = List<ErrorReport>.of(_reports);
    if (_loadCount == _pauseAtLoadNumber) {
      await _gate!.future;
    }
    return snapshot;
  }

  @override
  Future<void> save(List<ErrorReport> reports) async {
    _reports = List<ErrorReport>.of(reports);
  }

  /// Arms a one-shot pause: the [n]th call to [load] blocks (after
  /// capturing its snapshot) until [release] is called.
  void pauseAfterLoadNumber(int n) {
    _pauseAtLoadNumber = n;
    _gate = Completer<void>();
  }

  void release() {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  List<ErrorReport> get snapshot => List<ErrorReport>.unmodifiable(_reports);
}
