import 'dart:convert';

import '../models/workout_briefing_agent.dart';

/// Builds the wire payload for `workoutBriefingAgent` and the local cache key.
///
/// Pure: no Firebase, no I/O, no clock. This is the single place that decides
/// what leaves the device, which is what makes "no identifiers, no timestamps,
/// no location" a property one file can be read to verify.
class WorkoutBriefingPayloadBuilder {
  const WorkoutBriefingPayloadBuilder();

  /// Mirrors the caps in `functions/src/agent/workoutBriefingContractFields.ts`.
  /// Trimming here rather than letting the server reject keeps a plan with an
  /// unusually long breakdown working instead of silently falling back.
  static const maxMetrics = 6;
  static const maxSteps = 6;
  static const maxCoachNotes = 6;
  static const shortTextLimit = 40;
  static const labelTextLimit = 120;
  static const bodyTextLimit = 240;

  Map<String, Object?> build(WorkoutBriefingRequest request) {
    return <String, Object?>{
      'schemaVersion': 1,
      'workout': <String, Object?>{
        'dayLabel': _text(request.dayLabel, shortTextLimit),
        'planTitle': _text(request.planTitle, bodyTextLimit),
        'effortGuide': _text(request.effortGuide, bodyTextLimit),
        if (request.weekNumber != null &&
            request.weekNumber! >= 1 &&
            request.weekNumber! <= 104)
          'weekNumber': request.weekNumber,
        'weekFocus': ?_optionalText(request.weekFocus, bodyTextLimit),
      },
      'metrics': <Map<String, Object?>>[
        for (final metric in request.metrics.take(maxMetrics))
          <String, Object?>{
            'label': _text(metric.label, shortTextLimit),
            'value': _text(metric.value, labelTextLimit),
          },
      ],
      'steps': <Map<String, Object?>>[
        for (final step in request.steps.take(maxSteps))
          <String, Object?>{
            'title': _text(step.title, labelTextLimit),
            'detail': _text(step.detail, bodyTextLimit),
          },
      ],
      'coachNotes': <String>[
        for (final note in request.coachNotes.take(maxCoachNotes))
          _text(note, bodyTextLimit),
      ],
    };
  }

  /// A content fingerprint over the exact wire payload, appended to the caller's
  /// plan address. An edited, regenerated, or rescheduled plan changes the
  /// payload and therefore the key, so a stale briefing can never outlive the
  /// workout it describes; re-opening an unchanged workout still hits cache.
  String? cacheIdentityFor(WorkoutBriefingRequest request) {
    final address = request.cacheIdentity?.trim();
    if (address == null || address.isEmpty) return null;
    return '$address|${_fingerprint(build(request))}';
  }

  String _fingerprint(Map<String, Object?> payload) {
    // FNV-1a 64, computed in two 32-bit halves so it stays exact on the web's
    // double-backed ints as well as on native 64-bit ints.
    const offsetBasisHigh = 0xcbf29ce4;
    const offsetBasisLow = 0x84222325;
    var high = offsetBasisHigh;
    var low = offsetBasisLow;
    for (final byte in utf8.encode(jsonEncode(payload))) {
      low ^= byte;
      // Multiply by the FNV prime 0x100000001b3.
      final lowProduct = low * 0x1b3;
      final carry = lowProduct >>> 32;
      final nextLow = lowProduct & 0xffffffff;
      final nextHigh = (high * 0x1b3 + (low << 8) + carry) & 0xffffffff;
      low = nextLow;
      high = nextHigh;
    }
    return '${high.toRadixString(16).padLeft(8, '0')}'
        '${low.toRadixString(16).padLeft(8, '0')}';
  }

  String _text(String value, int maximumLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    final runes = normalized.runes.toList();
    if (runes.length <= maximumLength) return normalized;
    return String.fromCharCodes(runes.take(maximumLength)).trimRight();
  }

  String? _optionalText(String? value, int maximumLength) {
    if (value == null) return null;
    final normalized = _text(value, maximumLength);
    return normalized.isEmpty ? null : normalized;
  }
}
