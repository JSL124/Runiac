class MapboxRuntimeConfig {
  const MapboxRuntimeConfig({
    required this.accessToken,
    this.snapshotThumbnailsEnabled = false,
  });

  factory MapboxRuntimeConfig.fromEnvironment() {
    return MapboxRuntimeConfig.fromRaw(
      accessToken: const String.fromEnvironment('MAPBOX_PUBLIC_ACCESS_TOKEN'),
      snapshotThumbnailsFlag: const String.fromEnvironment(
        'RUNIAC_ENABLE_MAPBOX_SNAPSHOT_THUMBNAILS',
      ),
    );
  }

  factory MapboxRuntimeConfig.fromRaw({
    required String accessToken,
    required String snapshotThumbnailsFlag,
  }) {
    return MapboxRuntimeConfig(
      accessToken: accessToken.trim(),
      snapshotThumbnailsEnabled: _parseEnabledFlag(snapshotThumbnailsFlag),
    );
  }

  final String accessToken;
  final bool snapshotThumbnailsEnabled;

  bool get hasPublicAccessToken {
    return accessToken.startsWith('pk.');
  }

  static bool _parseEnabledFlag(String value) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
        return true;
      default:
        return false;
    }
  }
}
