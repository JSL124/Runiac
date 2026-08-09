import 'challenge_parse_exception.dart';

/// Primitive strict-parse helpers shared by the Challenge read models.
///
/// Every helper raises [ChallengeParseException] on malformed or missing input.
/// Distances and durations are integer metres / milliseconds: numeric parsing
/// preserves integers exactly and rejects fractional values rather than
/// rounding, so the client never fabricates a metre it was not given.
abstract final class ChallengeParse {
  /// Normalizes an untyped callable/document map into `Map<String, Object?>`.
  static Map<String, Object?> asMap(Object? value, {String? field}) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    throw ChallengeParseException('expected_map', field: field);
  }

  /// Normalizes an untyped list into `List<Object?>`.
  static List<Object?> asList(Object? value, {String? field}) {
    if (value is List) {
      return List<Object?>.from(value);
    }
    throw ChallengeParseException('expected_list', field: field);
  }

  static String string(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw ChallengeParseException('expected_non_empty_string', field: field);
  }

  static String? optionalString(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value == null) {
      return null;
    }
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw ChallengeParseException('expected_string_or_absent', field: field);
  }

  /// Reads a strictly integral value. A whole-number double (`62400.0`) is
  /// accepted as the integer it represents; a fractional double is rejected.
  static int integer(Map<String, Object?> map, String field) {
    final value = map[field];
    final parsed = _integerOrNull(value);
    if (parsed == null) {
      throw ChallengeParseException('expected_integer', field: field);
    }
    return parsed;
  }

  /// Reads an integral value that may be explicitly `null` or absent (used for
  /// optional server timestamps such as `startsAtMs`).
  static int? optionalInteger(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value == null) {
      return null;
    }
    final parsed = _integerOrNull(value);
    if (parsed == null) {
      throw ChallengeParseException('expected_integer_or_absent', field: field);
    }
    return parsed;
  }

  static bool boolean(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is bool) {
      return value;
    }
    throw ChallengeParseException('expected_bool', field: field);
  }

  static bool optionalBoolean(
    Map<String, Object?> map,
    String field, {
    required bool orElse,
  }) {
    final value = map[field];
    if (value == null) {
      return orElse;
    }
    if (value is bool) {
      return value;
    }
    throw ChallengeParseException('expected_bool_or_absent', field: field);
  }

  static int? _integerOrNull(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }
}
