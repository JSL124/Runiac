import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_tour_seen_store.dart';

/// [SharedPreferences]-backed implementation of [AppTourSeenStore].
///
/// A missing platform plugin (common in pure unit tests) is treated as "not
/// armed" / "not completed" rather than an error, and writes become no-ops.
class SharedPreferencesAppTourSeenStore implements AppTourSeenStore {
  const SharedPreferencesAppTourSeenStore();

  @override
  Future<bool> isArmed({required String? uid}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(appTourArmedPreferenceKey(uid)) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> setArmed({required String? uid, required bool armed}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(appTourArmedPreferenceKey(uid), armed);
    } on MissingPluginException {
      // Local tour-arming flag; ignore when unavailable.
    }
  }

  @override
  Future<bool> isCompleted({required String? uid}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(appTourCompletedPreferenceKey(uid)) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> markCompleted({required String? uid}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(appTourCompletedPreferenceKey(uid), true);
    } on MissingPluginException {
      // Local tour-completion flag; ignore when unavailable.
    }
  }
}
