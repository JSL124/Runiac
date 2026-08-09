import 'package:cloud_firestore/cloud_firestore.dart';

abstract interface class RuniacFirestoreConnector {
  void useEmulator(String host, int port);
}

class FirebaseRuniacFirestoreConnector implements RuniacFirestoreConnector {
  FirebaseRuniacFirestoreConnector({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  void useEmulator(String host, int port) {
    _firestore.useFirestoreEmulator(host, port);
  }
}

class RuniacFirestoreGateway {
  const RuniacFirestoreGateway._({
    required this.usesEmulator,
    this.emulatorHost,
    this.emulatorPort,
  });

  factory RuniacFirestoreGateway.configure({
    required bool useFirebaseEmulator,
    required String emulatorHost,
    RuniacFirestoreConnector? connector,
  }) {
    if (!useFirebaseEmulator) {
      return const RuniacFirestoreGateway._(usesEmulator: false);
    }

    (connector ?? FirebaseRuniacFirestoreConnector()).useEmulator(
      emulatorHost,
      defaultFirestoreEmulatorPort,
    );
    return RuniacFirestoreGateway._(
      usesEmulator: true,
      emulatorHost: emulatorHost,
      emulatorPort: defaultFirestoreEmulatorPort,
    );
  }

  static const defaultFirestoreEmulatorPort = 8080;

  final bool usesEmulator;
  final String? emulatorHost;
  final int? emulatorPort;
}
