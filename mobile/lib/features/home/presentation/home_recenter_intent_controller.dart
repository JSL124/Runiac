import 'package:flutter/foundation.dart';

/// Fires when the runner asks Home to return to the Runiac character.
///
/// The Home tab stays mounted behind the other tabs, so its scroll offset
/// survives a tab switch and a runner who scrolled up the stage map comes
/// back to exactly where they left it. Tapping Home in the bottom bar is
/// therefore a request rather than a rebuild: the shell fires [request] and
/// the stage map scrolls back to the character.
///
/// There is deliberately no pending state to consume — the notification *is*
/// the request. One fired while the map cannot scroll (not laid out yet, no
/// active plan, no character on screen) is simply dropped, exactly like a
/// second tap on an already-centred map.
class HomeRecenterIntentController extends ChangeNotifier {
  /// Asks the stage map to scroll back to the character.
  void request() {
    notifyListeners();
  }
}
