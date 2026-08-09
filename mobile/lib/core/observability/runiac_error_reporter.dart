import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import 'error_report.dart';
import 'flutterfire_report_app_error_callable.dart';
import 'local_pending_error_report_store.dart';

/// The client-side app version reported alongside a captured error. There is
/// no `package_info_plus` dependency in this app, so this mirrors the
/// `pubspec.yaml` version rather than reading it at runtime.
const String _runiacClientAppVersion = '1.0.0+1';

/// Caps how many stack frames survive client-side pre-strip, and how long a
/// message can be before it is sent. The server re-sanitises and re-caps
/// authoritatively; these are defence in depth only.
const int errorReportMaxStackFrames = 8;
const int errorReportMaxMessageLength = 200;

/// A client-side, session-only (never persisted) window for suppressing
/// duplicate reports of the same error. Without this, a single throwing
/// `build()` method fires every frame, which would evict the entire durable
/// buffer with copies of one error and burn the server's rate-limit budget
/// in under a second.
const Duration errorReportDuplicateSuppressionWindow = Duration(seconds: 30);

/// Bounds the in-memory duplicate-suppression map so a long session with
/// many distinct errors cannot grow it without limit.
const int errorReportDuplicateSignatureCap = 50;

/// `reportAppError` failure codes that mean the payload itself is bad and
/// retrying it will never succeed. Any other code (including throttling,
/// unavailability, or a non-[ReportAppErrorException] failure) is treated as
/// transient and retried later.
const Set<String> _permanentReportAppErrorCodes = <String>{
  'invalid-argument',
  'permission-denied',
  'failed-precondition',
  'invalid-response',
};

/// Keeps only frames that belong to this app's own code
/// (`package:runiac_app/`), dropping Flutter/plugin/SDK frames, and caps the
/// result at [errorReportMaxStackFrames].
List<String> stripToRuniacAppFrames(
  StackTrace? stackTrace, {
  int maxFrames = errorReportMaxStackFrames,
}) {
  if (stackTrace == null) {
    return const <String>[];
  }
  final matched = <String>[];
  for (final line in stackTrace.toString().split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.contains('package:runiac_app/')) {
      continue;
    }
    matched.add(trimmed);
    if (matched.length >= maxFrames) {
      break;
    }
  }
  return List<String>.unmodifiable(matched);
}

/// Caps a message at [maxLength] characters, defence in depth ahead of the
/// server's authoritative redaction and cap.
String capErrorMessage(
  String message, {
  int maxLength = errorReportMaxMessageLength,
}) {
  final trimmed = message.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return trimmed.substring(0, maxLength);
}

/// Composes the reported `message` from the error's own text and the optional
/// `context` a [FlutterErrorDetails] carried — the operation that failed, plus
/// the run's correlation key.
///
/// The context is appended, and it is the error text (not the context) that
/// gets truncated when the two together exceed [maxLength]: the operation
/// label is what says *which stage* failed, and it is far shorter than a long
/// exception dump.
///
/// Note what does and does not survive to the server. `sanitizeMessage` in
/// `functions/src/errors/sanitize.ts` redacts any run of 5+ digits, and every
/// `clientRunSessionId` embeds microsecond timestamps — so the correlation id
/// reaches `errorGroups` as `[redacted]`, by design. The operation label has
/// no digits and does survive, which is what makes the failing stage
/// identifiable in production. The full context, id included, is still
/// printed locally by Flutter's default error handler, which is where
/// run-level correlation is read today. Carrying the id itself into
/// `errorGroups` would need a new allowlisted payload field server-side and is
/// deliberately out of scope here.
String composeErrorReportMessage(
  String errorText,
  String? context, {
  int maxLength = errorReportMaxMessageLength,
}) {
  final trimmedContext = context?.trim() ?? '';
  if (trimmedContext.isEmpty) {
    return capErrorMessage(errorText, maxLength: maxLength);
  }
  final suffix = ' | $trimmedContext';
  if (suffix.length >= maxLength) {
    return capErrorMessage(trimmedContext, maxLength: maxLength);
  }
  final head = capErrorMessage(errorText, maxLength: maxLength - suffix.length);
  return '$head$suffix';
}

/// The label used when no real screen can be derived at all. Never sent as
/// `null` or empty — the server's `optionalScreen` validation only
/// special-cases `undefined`, so a literal `null` is rejected outright.
const String unknownErrorReportScreen = 'unknown';

/// Everything outside the server's `^[A-Za-z0-9 /_-]{1,60}$` pattern is
/// stripped from a derived screen label so a malformed label can never
/// cause an otherwise good report to be rejected.
final RegExp _disallowedScreenLabelCharacters = RegExp(r'[^A-Za-z0-9 /_-]');
const int _screenLabelMaxLength = 60;
const String _runiacAppPackagePrefix = 'package:runiac_app/';

/// Resolves the `screen` field: prefers [trackerScreen] (the active named
/// route, when one exists), otherwise falls back to a label derived from
/// the first retained app stack frame in [stackFrames]. This app currently
/// has zero named routes, so the fallback is the common case, not an edge
/// case — see the `ErrorScreenTracker` doc for why. Always returns a
/// non-empty string matching the server's allowlist pattern; falls back to
/// [unknownErrorReportScreen] when nothing usable can be derived.
String resolveErrorReportScreen(
  String? trackerScreen,
  List<String> stackFrames,
) {
  final candidate = (trackerScreen != null && trackerScreen.trim().isNotEmpty)
      ? trackerScreen
      : _screenLabelFromStackFrames(stackFrames);
  final sanitized = _sanitizeScreenLabel(candidate);
  return sanitized.isEmpty ? unknownErrorReportScreen : sanitized;
}

/// Turns a retained stack frame such as
/// `package:runiac_app/features/run/run_summary_controller.dart:42:10)`
/// into `features/run/run_summary_controller` — a real, if approximate,
/// location, rather than a constant placeholder.
String _screenLabelFromStackFrames(List<String> stackFrames) {
  if (stackFrames.isEmpty) {
    return '';
  }
  final firstFrame = stackFrames.first;
  final prefixIndex = firstFrame.indexOf(_runiacAppPackagePrefix);
  if (prefixIndex == -1) {
    return '';
  }
  final afterPrefix = firstFrame.substring(
    prefixIndex + _runiacAppPackagePrefix.length,
  );
  // Cut at the first character that cannot be part of the file path itself
  // (the `:line:column)` suffix in a real frame, or whitespace in any other
  // format), so only the path survives.
  final delimiterIndex = afterPrefix.indexOf(RegExp(r'[\s:)]'));
  final pathOnly = delimiterIndex == -1
      ? afterPrefix
      : afterPrefix.substring(0, delimiterIndex);
  return pathOnly.endsWith('.dart')
      ? pathOnly.substring(0, pathOnly.length - '.dart'.length)
      : pathOnly;
}

/// Strips any character outside the server's allowlist and, if what
/// remains still exceeds [_screenLabelMaxLength], keeps the trailing
/// characters — the tail (closest to the actual file/symbol) is more
/// informative than the leading directories.
String _sanitizeScreenLabel(String candidate) {
  final stripped = candidate.replaceAll(_disallowedScreenLabelCharacters, '');
  if (stripped.length <= _screenLabelMaxLength) {
    return stripped;
  }
  return stripped.substring(stripped.length - _screenLabelMaxLength);
}

/// Injectable seam over the signed-in uid, so `RuniacErrorReporter` never
/// needs a real Firebase project to be tested.
abstract interface class ErrorReporterAuthSource {
  /// The current uid, or `null` when signed out.
  String? get currentUid;

  /// Emits the uid on every auth state transition, `null` when signed out.
  Stream<String?> get uidChanges;
}

class FirebaseAuthErrorReporterAuthSource implements ErrorReporterAuthSource {
  FirebaseAuthErrorReporterAuthSource({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  @override
  String? get currentUid => _firebaseAuth.currentUser?.uid;

  @override
  Stream<String?> get uidChanges =>
      _firebaseAuth.authStateChanges().map((user) => user?.uid);
}

/// Captures unhandled and explicitly reported errors, buffers them durably
/// until a signed-in user exists, and flushes them through the
/// `reportAppError` callable.
///
/// This type must never throw and must never recurse: it is wired directly
/// into `FlutterError.onError`, `PlatformDispatcher.instance.onError`, and
/// `runZonedGuarded`, so a reporter that itself crashes is strictly worse
/// than no reporter at all. Every failure path — local storage, JSON
/// encoding, auth access, or the network call — is caught and swallowed.
class RuniacErrorReporter {
  RuniacErrorReporter({
    LocalPendingErrorReportStore? store,
    ReportAppErrorCallable? callable,
    ErrorReporterAuthSource? authSource,
    String Function()? appVersionResolver,
    String Function()? osVersionResolver,
    String Function()? platformResolver,
    DateTime Function()? clock,
  }) : _store = store ?? const SharedPreferencesLocalPendingErrorReportStore(),
       _injectedCallable = callable,
       _injectedAuthSource = authSource,
       _appVersionResolver = appVersionResolver ?? (() => _runiacClientAppVersion),
       _osVersionResolver = osVersionResolver ?? _defaultOsVersion,
       _platformResolver = platformResolver ?? _defaultPlatform,
       _clock = clock ?? DateTime.now {
    try {
      _uidSubscription = _authSource.uidChanges.listen(
        _onUidChanged,
        onError: (Object _, StackTrace _) {},
      );
    } catch (_) {
      _uidSubscription = null;
    }
  }

  final LocalPendingErrorReportStore _store;

  /// The caller-supplied callable, if any. When `null`, [_callable] builds
  /// the real [FlutterFireReportAppErrorCallable] lazily, on first use,
  /// instead of here in the constructor's initializer list. The initializer
  /// list runs before the constructor body's `try`/`catch`, so an eager
  /// default here would throw uncaught (`FirebaseFunctions.instanceFor`
  /// needs a Firebase app) whenever this reporter is constructed before any
  /// Firebase app exists — e.g. a plain `flutter run` with no dart-defines.
  final ReportAppErrorCallable? _injectedCallable;
  ReportAppErrorCallable? _lazyCallable;

  /// Same lazy-resolution reasoning as [_injectedCallable]: eagerly building
  /// [FirebaseAuthErrorReporterAuthSource] here would touch `FirebaseAuth
  /// .instance` before any guard can apply.
  final ErrorReporterAuthSource? _injectedAuthSource;
  ErrorReporterAuthSource? _lazyAuthSource;

  ReportAppErrorCallable get _callable =>
      _injectedCallable ??
      (_lazyCallable ??= FlutterFireReportAppErrorCallable());

  ErrorReporterAuthSource get _authSource =>
      _injectedAuthSource ??
      (_lazyAuthSource ??= FirebaseAuthErrorReporterAuthSource());

  final String Function() _appVersionResolver;
  final String Function() _osVersionResolver;
  final String Function() _platformResolver;
  final DateTime Function() _clock;

  StreamSubscription<String?>? _uidSubscription;
  String? _lastKnownUid;
  bool _isReporting = false;
  bool _isFlushing = false;

  /// Serializes every queue-mutating operation (enqueue, and flush's own
  /// peek/remove steps) so no two load-then-save round trips to [_store]
  /// can interleave. Each call to [_runExclusive] chains its action onto
  /// this future; the network call to [_callable] in [_flush] deliberately
  /// stays outside any [_runExclusive] block so a concurrent enqueue is
  /// never blocked behind a slow or hanging send.
  Future<void> _queueTail = Future<void>.value();

  /// Session-only record of the last time each `(errorType, screen, first
  /// stack frame)` signature was accepted. Never persisted — a fresh app
  /// launch always starts with a clean slate.
  final Map<String, DateTime> _recentSignatures = <String, DateTime>{};

  /// Records [error] (with optional [stack]), then attempts to flush the
  /// durable buffer. Never throws.
  /// [context] is the failing operation as described by the reporting call
  /// site (a `FlutterErrorDetails.context`), e.g.
  /// `completing a run (runSessionId=...)`. Without it the payload carries
  /// only the raw exception text, which frequently does not say which stage
  /// of a multi-step flow failed.
  Future<void> reportError(
    Object error,
    StackTrace? stack, {
    String? screen,
    bool fatal = false,
    String? context,
  }) async {
    if (_isReporting) {
      // A failure raised while building or enqueuing a report must never
      // trigger another call into this method — that is the recursion this
      // guard exists to stop. It is released before the network flush below
      // (see `_flush`'s own `_isFlushing` guard) so a second, distinct error
      // arriving while the first is still flushing is still recorded.
      return;
    }
    _isReporting = true;
    var didEnqueue = false;
    try {
      final report = _buildReport(
        error,
        stack,
        screen: screen,
        fatal: fatal,
        context: context,
      );
      if (!_shouldSuppressDuplicate(report)) {
        await _enqueue(report);
        didEnqueue = true;
      }
    } catch (_) {
      // Every failure path is swallowed by design; see class doc.
    } finally {
      _isReporting = false;
    }
    if (!didEnqueue) {
      return;
    }
    try {
      await _flush();
    } catch (_) {
      // Never propagate; see class doc.
    }
  }

  /// Attempts to drain the durable buffer. Safe to call speculatively (at
  /// startup, on auth transitions); never throws.
  Future<void> flushPending() async {
    try {
      await _flush();
    } catch (_) {
      // Never propagate; see class doc.
    }
  }

  void dispose() {
    unawaited(_uidSubscription?.cancel());
  }

  void _onUidChanged(String? uid) {
    final wasSignedOut = _lastKnownUid == null;
    _lastKnownUid = uid;
    if (wasSignedOut && uid != null) {
      unawaited(flushPending());
    }
  }

  ErrorReport _buildReport(
    Object error,
    StackTrace? stack, {
    required String? screen,
    required bool fatal,
    String? context,
  }) {
    final stackFrames = stripToRuniacAppFrames(stack);
    return ErrorReport(
      errorType: error.runtimeType.toString(),
      message: composeErrorReportMessage(error.toString(), context),
      stackFrames: stackFrames,
      screen: resolveErrorReportScreen(screen, stackFrames),
      appVersion: _safeResolve(_appVersionResolver, 'unknown'),
      osVersion: _safeResolve(_osVersionResolver, 'unknown'),
      platform: _safeResolve(_platformResolver, 'unknown'),
      fatal: fatal,
      occurredAt: _clock(),
    );
  }

  String _safeResolve(String Function() resolver, String fallback) {
    try {
      return resolver();
    } catch (_) {
      return fallback;
    }
  }

  /// Drops an error identical (by errorType, screen, and first stack frame)
  /// to one already recorded within
  /// [errorReportDuplicateSuppressionWindow]. This is a client-side, in-
  /// memory-only loop guard: a throwing `build()` method can otherwise fire
  /// every frame and evict the entire durable buffer with copies of one
  /// error while burning the server's rate-limit budget in under a second.
  bool _shouldSuppressDuplicate(ErrorReport report) {
    final signature = _duplicateSignatureFor(report);
    final now = _clock();
    final lastAccepted = _recentSignatures[signature];
    if (lastAccepted != null &&
        now.difference(lastAccepted) < errorReportDuplicateSuppressionWindow) {
      return true;
    }
    _recentSignatures[signature] = now;
    if (_recentSignatures.length > errorReportDuplicateSignatureCap) {
      final oldestEntry = _recentSignatures.entries.reduce(
        (a, b) => a.value.isBefore(b.value) ? a : b,
      );
      _recentSignatures.remove(oldestEntry.key);
    }
    return false;
  }

  String _duplicateSignatureFor(ErrorReport report) {
    final firstFrame = report.stackFrames.isEmpty
        ? ''
        : report.stackFrames.first;
    return '${report.errorType} ${report.screen} $firstFrame';
  }

  /// Chains [action] onto [_queueTail] so it only starts once every
  /// previously-chained action has fully settled, then advances
  /// [_queueTail] to a tracking future that always resolves normally
  /// (regardless of whether [action] succeeded) — otherwise one failed
  /// operation would permanently wedge every later one behind it. The
  /// returned future still carries [action]'s own result/error to its
  /// caller.
  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final resultFuture = _queueTail.then((_) => action());
    _queueTail = resultFuture.then((_) {}, onError: (_) {});
    return resultFuture;
  }

  Future<void> _enqueue(ErrorReport report) {
    return _runExclusive(() async {
      final pending = await _store.load();
      final updated = List<ErrorReport>.of(pending)..add(report);
      await _store.save(updated);
    });
  }

  /// Drains the durable buffer oldest-first. A permanently-rejected report
  /// (a bad payload the server will never accept) is dropped so it cannot
  /// block everything behind it forever; any other failure — throttling,
  /// unavailability, or anything that is not a [ReportAppErrorException] —
  /// is treated as transient and stops the drain with the queue (including
  /// the failed report) left intact for a later retry.
  ///
  /// The queue is re-read from the store rather than trusting an in-memory
  /// snapshot, and every read/write pair — here and in [_enqueue] — runs
  /// through [_runExclusive] so a concurrent `reportError` call can never
  /// enqueue behind an in-flight save and get silently dropped, nor land in
  /// a way that reintroduces a report this loop already removed. The
  /// network call to [_callable] deliberately happens outside any
  /// [_runExclusive] block: a slow or hung send must not block a concurrent
  /// enqueue from reaching the durable buffer.
  Future<void> _flush() async {
    if (_isFlushing) {
      return;
    }
    _isFlushing = true;
    try {
      if (_authSource.currentUid == null) {
        return;
      }
      while (true) {
        final next = await _runExclusive(() async {
          final pending = await _store.load();
          return pending.isEmpty ? null : pending.first;
        });
        if (next == null) {
          return;
        }
        try {
          await _callable.call(next.toPayload());
        } catch (error) {
          if (!_isPermanentFailure(error)) {
            // Transient: stop draining and leave the queue, including this
            // report, intact for a later retry.
            return;
          }
          // Permanent: fall through and drop it below, then keep draining.
        }
        await _runExclusive(() async {
          final remaining = await _store.load();
          await _store.save(remaining.skip(1).toList(growable: false));
        });
      }
    } finally {
      _isFlushing = false;
    }
  }

  bool _isPermanentFailure(Object error) {
    return error is ReportAppErrorException &&
        _permanentReportAppErrorCodes.contains(error.code);
  }
}

String _defaultOsVersion() => Platform.operatingSystemVersion;

String _defaultPlatform() => Platform.operatingSystem;
