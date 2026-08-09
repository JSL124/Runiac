import 'package:flutter/foundation.dart';

import '../domain/models/notification_inbox_item.dart';
import '../domain/repositories/notification_inbox_repository.dart';

const _debugNotificationInboxWrites = bool.fromEnvironment(
  'RUNIAC_LOCAL_NOTIFICATION_DEBUG_LOGS',
);

class NotificationInboxDocument {
  const NotificationInboxDocument({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.deletedAt,
    this.data = const <String, Object?>{},
    this.clientManaged = false,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? deletedAt;
  final Map<String, Object?> data;
  final bool clientManaged;

  NotificationInboxItem toReadModel() {
    return NotificationInboxItem(
      id: id,
      title: title,
      body: body,
      createdAt: createdAt,
      readAt: readAt,
      deletedAt: deletedAt,
      data: data,
      clientManaged: clientManaged,
    );
  }
}

abstract class NotificationInboxDocumentStore {
  Stream<List<NotificationInboxDocument>> watchInboxItems({
    required String uid,
  });

  Future<void> markRead({
    required String uid,
    required String itemId,
    required DateTime readAt,
  });

  Future<void> saveInboxItem({
    required String uid,
    required NotificationInboxDocument item,
    bool clearReadState,
  });

  Future<void> softDelete({
    required String uid,
    required String itemId,
    required DateTime deletedAt,
  });

  /// Soft-deletes [itemIds] in as few round trips as the backing store allows.
  ///
  /// Deliberately separate from repeated [softDelete] calls: clearing a full
  /// inbox one write at a time would leave the list half-emptied if the
  /// connection dropped midway, and the UI's clear-all animation would then be
  /// telling the runner something untrue.
  Future<void> softDeleteAll({
    required String uid,
    required List<String> itemIds,
    required DateTime deletedAt,
  });
}

class FirestoreNotificationInboxRepository
    implements NotificationInboxRepository {
  FirestoreNotificationInboxRepository({
    String? ownerUid,
    this.ownerUidProvider,
    required this.documentStore,
    DateTime Function()? clock,
  }) : _ownerUid = ownerUid ?? '',
       _clock = clock ?? DateTime.now;

  final String _ownerUid;
  final String? Function()? ownerUidProvider;
  final NotificationInboxDocumentStore documentStore;
  final DateTime Function() _clock;

  String get ownerUid => ownerUidProvider?.call() ?? _ownerUid;

  List<NotificationInboxItem> _visibleSorted(
    List<NotificationInboxDocument> documents,
  ) {
    final items = documents
        .map((document) => document.toReadModel())
        .where((item) => !item.isDeleted)
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<NotificationInboxItem>.unmodifiable(items);
  }

  @override
  Future<List<NotificationInboxItem>> listInboxItems() {
    return watchInboxItems().first;
  }

  @override
  Future<void> recordDelivery(NotificationInboxItem item) {
    return _write(item, clearReadState: true);
  }

  @override
  Future<void> saveInboxItem(NotificationInboxItem item) {
    return _write(item, clearReadState: false);
  }

  Future<void> _write(
    NotificationInboxItem item, {
    required bool clearReadState,
  }) {
    final uid = ownerUid;
    if (uid.isEmpty) {
      if (_debugNotificationInboxWrites) {
        debugPrint(
          '[RuniacLocalNotifications][Dart] '
          'saveInboxItem skipped id=${item.id}: empty owner uid',
        );
      }
      return Future<void>.value();
    }
    if (_debugNotificationInboxWrites) {
      debugPrint(
        '[RuniacLocalNotifications][Dart] '
        'saveInboxItem Firestore uid=$uid id=${item.id}',
      );
    }
    return documentStore.saveInboxItem(
      uid: uid,
      item: NotificationInboxDocument(
        id: item.id,
        title: item.title,
        body: item.body,
        createdAt: item.createdAt,
        readAt: item.readAt,
        deletedAt: item.deletedAt,
        data: item.data,
        clientManaged: true,
      ),
      clearReadState: clearReadState,
    );
  }

  @override
  Future<void> markRead(String itemId) {
    final uid = ownerUid;
    if (uid.isEmpty) {
      return Future<void>.value();
    }
    return documentStore.markRead(uid: uid, itemId: itemId, readAt: _clock());
  }

  @override
  Future<void> softDelete(String itemId) {
    final uid = ownerUid;
    if (uid.isEmpty) {
      return Future<void>.value();
    }
    return documentStore.softDelete(
      uid: uid,
      itemId: itemId,
      deletedAt: _clock(),
    );
  }

  @override
  Future<void> clearAll() async {
    final uid = ownerUid;
    if (uid.isEmpty) {
      return;
    }
    // Read the visible set rather than trusting a caller-supplied list, so an
    // item that arrived while the confirmation dialog was open is cleared too
    // instead of surviving an action the runner read as "clear all".
    final items = await listInboxItems();
    if (items.isEmpty) {
      return;
    }
    await documentStore.softDeleteAll(
      uid: uid,
      itemIds: items.map((item) => item.id).toList(growable: false),
      deletedAt: _clock(),
    );
  }

  @override
  Stream<List<NotificationInboxItem>> watchInboxItems() {
    final uid = ownerUid;
    if (uid.isEmpty) {
      return const Stream<List<NotificationInboxItem>>.empty();
    }
    return documentStore.watchInboxItems(uid: uid).map(_visibleSorted);
  }

  @override
  Stream<int> watchUnreadCount() {
    return watchInboxItems().map(
      (items) => items.where((item) => !item.isRead).length,
    );
  }
}
