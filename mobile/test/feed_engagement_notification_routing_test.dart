import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/domain/feed_engagement_notification_routing.dart';

void main() {
  group('feed engagement notification routing', () {
    test('a like notification maps to a target carrying the postId', () {
      final target = feedEngagementNotificationTargetFor(<String, Object?>{
        'kind': 'feed_post_liked',
        'route': 'feedComments',
        'postId': 'post-1',
      });
      expect(target, isNotNull);
      expect(target!.postId, 'post-1');
    });

    test('a comment notification maps to a target carrying the postId', () {
      final target = feedEngagementNotificationTargetFor(<String, Object?>{
        'kind': 'feed_post_commented',
        'route': 'feedComments',
        'postId': 'post-2',
      });
      expect(target, isNotNull);
      expect(target!.postId, 'post-2');
    });

    test('two targets with the same postId are equal', () {
      const first = FeedEngagementNotificationTarget(postId: 'post-1');
      const second = FeedEngagementNotificationTarget(postId: 'post-1');
      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
    });

    test('an unknown kind resolves to null', () {
      expect(
        feedEngagementNotificationTargetFor(<String, Object?>{
          'kind': 'challenge_started',
          'postId': 'post-1',
        }),
        isNull,
      );
    });

    test('a missing kind resolves to null', () {
      expect(
        feedEngagementNotificationTargetFor(<String, Object?>{
          'postId': 'post-1',
        }),
        isNull,
      );
    });

    test('a non-String kind resolves to null', () {
      expect(
        feedEngagementNotificationTargetFor(<String, Object?>{
          'kind': 42,
          'postId': 'post-1',
        }),
        isNull,
      );
    });

    test('a missing postId resolves to null', () {
      expect(
        feedEngagementNotificationTargetFor(<String, Object?>{
          'kind': 'feed_post_liked',
        }),
        isNull,
      );
    });

    test('a non-String postId resolves to null', () {
      expect(
        feedEngagementNotificationTargetFor(<String, Object?>{
          'kind': 'feed_post_liked',
          'postId': 7,
        }),
        isNull,
      );
    });

    test('an empty postId resolves to null', () {
      expect(
        feedEngagementNotificationTargetFor(<String, Object?>{
          'kind': 'feed_post_liked',
          'postId': '',
        }),
        isNull,
      );
    });

    test('an empty payload resolves to null', () {
      expect(feedEngagementNotificationTargetFor(const <String, Object?>{}), isNull);
    });
  });
}
