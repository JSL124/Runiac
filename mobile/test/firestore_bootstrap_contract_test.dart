import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/firebase/runiac_firestore_gateway.dart';

void main() {
  group('RuniacFirestoreGateway', () {
    test('does not configure emulator when runtime flag is off', () {
      final connector = _RecordingFirestoreConnector();

      final gateway = RuniacFirestoreGateway.configure(
        useFirebaseEmulator: false,
        emulatorHost: '127.0.0.1',
        connector: connector,
      );

      expect(gateway.usesEmulator, isFalse);
      expect(gateway.emulatorHost, isNull);
      expect(gateway.emulatorPort, isNull);
      expect(connector.emulatorRequests, isEmpty);
    });

    test('configures emulator only when runtime flag is enabled', () {
      final connector = _RecordingFirestoreConnector();

      final gateway = RuniacFirestoreGateway.configure(
        useFirebaseEmulator: true,
        emulatorHost: '10.0.2.2',
        connector: connector,
      );

      expect(gateway.usesEmulator, isTrue);
      expect(gateway.emulatorHost, '10.0.2.2');
      expect(gateway.emulatorPort, 8080);
      expect(connector.emulatorRequests, <_EmulatorRequest>[
        const _EmulatorRequest(host: '10.0.2.2', port: 8080),
      ]);
    });

    test('keeps gateway source free of Firestore data access verbs', () {
      final source = File(
        'lib/core/firebase/runiac_firestore_gateway.dart',
      ).readAsStringSync();

      const forbiddenDataAccessTerms = <String>[
        'collection',
        'collectionGroup',
        'doc',
        'get',
        'snapshots',
        'set',
        'update',
        'delete',
        'runTransaction',
        'WriteBatch',
        'batch',
      ];

      for (final term in forbiddenDataAccessTerms) {
        expect(source, isNot(contains(term)), reason: term);
      }
    });
  });
}

class _RecordingFirestoreConnector implements RuniacFirestoreConnector {
  final emulatorRequests = <_EmulatorRequest>[];

  @override
  void useEmulator(String host, int port) {
    emulatorRequests.add(_EmulatorRequest(host: host, port: port));
  }
}

class _EmulatorRequest {
  const _EmulatorRequest({required this.host, required this.port});

  final String host;
  final int port;

  @override
  bool operator ==(Object other) {
    return other is _EmulatorRequest &&
        other.host == host &&
        other.port == port;
  }

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => '_EmulatorRequest(host: $host, port: $port)';
}
