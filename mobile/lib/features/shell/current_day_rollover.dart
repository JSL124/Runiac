import 'dart:async';

import 'package:flutter/foundation.dart';

typedef CurrentDateNow = DateTime Function();

Duration nextLocalDayRefreshDelay(DateTime now) {
  final nextDay = DateTime(now.year, now.month, now.day + 1);
  return nextDay.difference(now);
}

class CurrentDayRolloverController extends ChangeNotifier {
  CurrentDayRolloverController({CurrentDateNow? now})
    : _now = now ?? DateTime.now,
      _today = _dateOnly((now ?? DateTime.now)());

  final CurrentDateNow _now;
  DateTime _today;
  Timer? _timer;

  DateTime get today => _today;

  void start() {
    _timer?.cancel();
    _timer = Timer(nextLocalDayRefreshDelay(_now()), _handleDayBoundary);
  }

  void refresh() {
    final nextToday = _dateOnly(_now());
    if (nextToday == _today) {
      return;
    }
    _today = nextToday;
    notifyListeners();
  }

  void _handleDayBoundary() {
    refresh();
    start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}
