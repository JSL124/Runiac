import 'package:flutter/material.dart';

import '../../domain/models/run_summary_snapshot.dart';
import '../../../feed/data/feed_publish/feed_publish_service.dart';
import '../../../feed/data/feed_publish/feed_thumbnail_artifact.dart';
import '../../../feed/domain/models/feed_display_models.dart';
import 'share_route_feed_preview.dart';

// The sheet for sharing a finished run to the feed: preview, caption, publish.
//
// Publishing is the point of no return, so the sheet shows
// [ShareRouteFeedPostPreview] first and keeps the confirm action distinct from
// dismissing. The actual write goes through `FeedPublishService`; this file
// owns only the composing UI and the thumbnail hand-off.

const _rBlue = Color(0xFF2F51C8);
const _rWhite = Color(0xFFFFFFFF);
const _rBlue60 = Color(0x992F51C8);
const _rBlue30 = Color(0x4D2F51C8);
const _rBlue18 = Color(0x2E2F51C8);
const _rInk = Color(0xFF172033);

class ShareRouteToFeedSheet extends StatefulWidget {
  const ShareRouteToFeedSheet({
    required this.summary,
    required this.onCancel,
    required this.onConfirm,
    required this.authorProfile,
    this.artifact,
    this.postingUnavailableMessage,
    super.key,
  });

  final RunSummarySnapshot summary;
  final VoidCallback onCancel;
  final Future<void> Function() onConfirm;
  final FeedAuthorProfileSnapshot authorProfile;
  final FeedThumbnailArtifact? artifact;
  final String? postingUnavailableMessage;

  @override
  State<ShareRouteToFeedSheet> createState() => _ShareRouteToFeedSheetState();
}

class _ShareRouteToFeedSheetState extends State<ShareRouteToFeedSheet> {
  var _isPosting = false;
  String? _errorMessage;

  Future<void> _confirm() async {
    setState(() {
      _isPosting = true;
      _errorMessage = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _isPosting = false;
          _errorMessage = _messageFor(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPost =
        widget.artifact != null && widget.postingUnavailableMessage == null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FF),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _rBlue18,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: const Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Share Your Achievement',
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _rInk,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ShareRouteFeedPostPreview(
                artifact: widget.artifact,
                summary: widget.summary,
                authorProfile: widget.authorProfile,
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _isPosting ? null : widget.onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _rBlue,
                  side: const BorderSide(color: _rBlue30, width: 1.5),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Cancel'),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (widget.postingUnavailableMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  widget.postingUnavailableMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _rBlue60, fontSize: 13),
                ),
              ] else if (widget.artifact == null) ...[
                const SizedBox(height: 10),
                const Text(
                  'Your private route preview is unavailable. Your run is still saved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _rBlue60, fontSize: 13),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _isPosting || !canPost ? null : _confirm,
                icon: const Icon(Icons.send_outlined, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: _rBlue,
                  foregroundColor: _rWhite,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                label: Text(_isPosting ? 'Posting to Feed…' : 'Post to Feed'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _messageFor(Object error) {
    if (error is FeedPublishException) {
      return error.message;
    }
    if (error is StateError && error.message.isNotEmpty) {
      return error.message;
    }
    final description = error.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
    if (description.isEmpty) {
      return 'Posting failed for an unknown reason. Your run is still saved.';
    }
    const maxLength = 140;
    final compactDescription = description.length <= maxLength
        ? description
        : '${description.substring(0, maxLength - 1)}…';
    return 'Posting failed: $compactDescription. Your run is still saved.';
  }
}
