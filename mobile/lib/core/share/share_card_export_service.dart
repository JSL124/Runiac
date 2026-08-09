import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../imaging/eight_bit_png.dart';

/// Display-only export of a rendered share card (leaderboard rank, run
/// activity, etc.). Rasterizes the card widget and hands the PNG to the
/// gallery / OS share sheet / Instagram Stories / Storage upload. It never
/// reads or writes any backend-owned value — the card only paints trusted
/// labels.
class ShareCardExportService {
  const ShareCardExportService();

  static const MethodChannel _instagramChannel = MethodChannel(
    'runiac/instagram_story',
  );

  /// Rasterizes the [RepaintBoundary] behind [boundaryKey] to PNG bytes.
  /// Returns null if the boundary is not laid out yet, or if the raster/encode
  /// fails — every caller already handles null by showing a "could not render"
  /// message, so a failure here must never escape as an unhandled async error.
  Future<Uint8List?> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 3.0,
  }) async {
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      return null;
    }
    final ui.Image image;
    try {
      image = await renderObject.toImage(pixelRatio: pixelRatio);
    } catch (error, stackTrace) {
      developer.log(
        'RUNIAC_SHARE capture failed',
        name: 'ShareCardExportService',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
    // The `await` is load-bearing, not stylistic: without it the `finally`
    // below disposes the image while `encodeEightBitPng` is still reading it.
    // That only breaks on a wide-gamut (Display P3) device, because the
    // second `toByteData` pass it disposes out from under runs solely when
    // the direct encode came back at depth 16 — which never happens on the
    // simulator or under `flutter_test`. See eight_bit_png.dart.
    try {
      return await encodeEightBitPng(image);
    } finally {
      image.dispose();
    }
  }

  /// Saves [pngBytes] to the device gallery. Returns false when the user
  /// declines the photo-library permission.
  Future<bool> saveToGallery(
    Uint8List pngBytes, {
    required String fileName,
  }) async {
    try {
      // Add-only access (not album access) so we need just the
      // NSPhotoLibraryAddUsageDescription purpose string, not full library
      // access. Saves straight to the camera roll.
      final granted = await Gal.requestAccess();
      if (!granted) {
        return false;
      }
      await Gal.putImageBytes(pngBytes, name: fileName);
      return true;
    } on GalException {
      return false;
    }
  }

  /// Opens the OS share sheet with [pngBytes] as a PNG attachment. Bytes are
  /// written to a temp file so every platform receives a real file path.
  ///
  /// One fixed directory is reused rather than `createTemp`, which minted a
  /// fresh random directory per share and never removed any of them. Deleting
  /// after `share()` returns is not safe — on iOS the completion fires when
  /// the sheet is dismissed, which can precede the receiving extension
  /// finishing with the file — so each share simply overwrites the last.
  Future<void> shareViaSheet(
    Uint8List pngBytes, {
    required String fileName,
    String? text,
  }) async {
    final directory = Directory('${Directory.systemTemp.path}/runiac_share');
    await directory.create(recursive: true);
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(pngBytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: text,
      ),
    );
  }

  /// Uploads the rendered card to the signed-in user's Storage path and returns
  /// a shareable download URL (token-based, so anyone with the link can view).
  /// Returns null when Firebase is unavailable, no user is signed in, or the
  /// upload is rejected. Only trusted display values are rendered into the
  /// image; no backend-owned value is written.
  Future<String?> uploadShareCardLink(
    Uint8List pngBytes, {
    required String storageFileName,
  }) async {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return null;
    }
    try {
      final reference = FirebaseStorage.instance.ref(
        'share-cards/$uid/$storageFileName',
      );
      await reference.putData(
        pngBytes,
        SettableMetadata(contentType: 'image/png'),
      );
      return await reference.getDownloadURL();
    } on FirebaseException {
      return null;
    }
  }

  /// Whether Instagram Stories can be opened (iOS only; Instagram installed).
  Future<bool> isInstagramStoryAvailable() async {
    if (!Platform.isIOS) {
      return false;
    }
    try {
      final available = await _instagramChannel.invokeMethod<bool>(
        'isAvailable',
      );
      return available ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Shares [pngBytes] into Instagram Stories as a sticker over a Runiac
  /// gradient. Returns false when the Facebook App ID is missing, Instagram is
  /// unavailable, or the platform is not iOS. [appId] must be a valid Facebook
  /// App ID registered for Instagram sharing.
  Future<bool> shareToInstagramStory(
    Uint8List pngBytes, {
    required String appId,
  }) async {
    if (!Platform.isIOS || appId.isEmpty) {
      return false;
    }
    try {
      final shared = await _instagramChannel
          .invokeMethod<bool>('shareSticker', {
            'stickerImage': pngBytes,
            'appId': appId,
            'backgroundTopColor': '#0B1B3A',
            'backgroundBottomColor': '#2F50C7',
          });
      return shared ?? false;
    } on PlatformException {
      return false;
    }
  }
}
