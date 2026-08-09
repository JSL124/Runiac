import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_run_repository.dart';

class FlutterFireCompleteRunCallable implements CompleteRunCallable {
  FlutterFireCompleteRunCallable({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    try {
      final result = await _functions
          .httpsCallable('completeRun')
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
        message: 'The emulator returned an invalid run completion response.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw CompleteRunCallableException(
        code: error.code,
        message: error.message ?? 'The emulator rejected the run completion.',
      );
    }
  }
}
