import 'package:runiac_app/core/legal/runiac_url_opener.dart';

/// Test double that records requested URLs instead of launching them.
class RecordingUrlOpener implements RuniacUrlOpener {
  RecordingUrlOpener({this.result = true});

  /// Value returned from [open], so tests can exercise the failure path.
  final bool result;

  /// Every URL passed to [open], in call order.
  final List<Uri> openedUrls = <Uri>[];

  /// The most recently requested URL as a plain string.
  String get lastUrl => openedUrls.last.toString();

  @override
  Future<bool> open(Uri url) async {
    openedUrls.add(url);
    return result;
  }
}
