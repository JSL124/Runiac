class FeedTimelineLifecycle {
  Future<void> _tail = Future<void>.value();
  var _disposed = false;

  bool get isDisposed => _disposed;

  Future<T> enqueue<T>(Future<T> Function() operation) {
    final scheduled = _tail.then((_) => operation());
    _tail = scheduled.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return scheduled;
  }

  void dispose() {
    _disposed = true;
  }
}
