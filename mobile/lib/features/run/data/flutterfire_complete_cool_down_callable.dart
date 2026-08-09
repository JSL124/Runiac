import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_run_repository.dart';

class FlutterFireCompleteCoolDownCallable implements CompleteCoolDownCallable {
  FlutterFireCompleteCoolDownCallable({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    try {
      final result = await _functions
          .httpsCallable('completeCoolDown')
          .call(request);
      final data = result.data;
      if (data is Map<String, Object?>) {
        return data;
      }
      if (data is Map) {
        return data.map((key, value) => MapEntry(key.toString(), value));
      }
      throw const CompleteRunCallableException(
        code: 'invalid-response',
        message: 'The emulator returned an invalid cool-down bonus response.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw CompleteRunCallableException(
        code: error.code,
        message: error.message ?? 'The emulator rejected the cool-down bonus.',
      );
    }
  }
}
