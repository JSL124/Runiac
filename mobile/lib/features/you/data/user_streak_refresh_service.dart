import 'package:cloud_functions/cloud_functions.dart';

abstract interface class UserStreakRefreshService {
  Future<void> refreshStreakStatus();
}

class NoopUserStreakRefreshService implements UserStreakRefreshService {
  const NoopUserStreakRefreshService();

  @override
  Future<void> refreshStreakStatus() async {}
}

class CloudFunctionUserStreakRefreshService
    implements UserStreakRefreshService {
  CloudFunctionUserStreakRefreshService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  @override
  Future<void> refreshStreakStatus() async {
    await _functions.httpsCallable('refreshStreakStatus').call<void>();
  }
}
