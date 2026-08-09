import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/feed_publish/feed_thumbnail_capture.dart';
import 'package:runiac_app/features/feed/data/feed_publish/history_artifact_resolver.dart';
import 'package:runiac_app/features/run/presentation/data/run_completion_demo_snapshots.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_mapbox_snapshot_provider.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_preview.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_snapshot_thumbnail_cache.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_thumbnail_viewport.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'capture keeps the exact provider PNG bytes at capped DPR dimensions',
    () async {
      final bytes = await _solidPngSized(264);
      final capture = FeedThumbnailCapture(provider: _PngProvider(bytes));

      final artifact = await capture.capture(_request(dpr: 4));

      expect(artifact.pngBytes, same(bytes));
      expect(artifact.memoryImage.bytes, same(bytes));
    },
  );

  test('capture accepts the renderer-safe canonical PNG fixture', () async {
    final bytes = _validPngFixture();
    final capture = FeedThumbnailCapture(provider: _PngProvider(bytes));

    final artifact = await capture.capture(_request(dpr: 1));

    expect(artifact.pngBytes, same(bytes));
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    expect(image.width, 88);
    expect(image.height, 88);
    image.dispose();
  });

  test('capture accepts consecutive nonempty IDAT chunks', () async {
    final bytes = _validPngFixture(
      idatChunks: _splitOpaqueRgbaIdatChunks(88, 88),
    );
    final capture = FeedThumbnailCapture(provider: _PngProvider(bytes));

    final artifact = await capture.capture(_request(dpr: 1));

    expect(artifact.pngBytes, same(bytes));
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    expect(image.width, 88);
    expect(image.height, 88);
    image.dispose();
  });

  for (final sample in _invalidPngFixtures) {
    test('capture rejects ${sample.description}', () async {
      final capture = FeedThumbnailCapture(
        provider: _PngProvider(sample.bytes),
      );

      await expectLater(
        capture.capture(_request(dpr: 1)),
        throwsA(isA<FeedThumbnailCaptureException>()),
      );
    });
  }

  test('a History PNG artifact supplies the exact upload bytes', () async {
    final bytes = await _solidPngSized(88);
    final capture = FeedThumbnailCapture(provider: _PngProvider(bytes));

    final artifact = await capture.capture(_request(dpr: 1));

    expect(artifact.pngBytes, same(bytes));
  });

  for (final sample in <(double, int)>[(1, 88), (2, 176), (3, 264), (4, 264)]) {
    test('capture accepts ${sample.$2}px PNG at DPR ${sample.$1}', () async {
      final bytes = await _solidPngSized(sample.$2);
      final capture = FeedThumbnailCapture(provider: _PngProvider(bytes));

      final artifact = await capture.capture(_request(dpr: sample.$1));

      expect(artifact.pngBytes.lengthInBytes, lessThanOrEqualTo(1024 * 1024));
    });
  }

  test('capture accepts the current wide card at canonical DPR', () async {
    final bytes = await _solidPngSized(1032, height: 552);
    final capture = FeedThumbnailCapture(provider: _PngProvider(bytes));

    final artifact = await capture.capture(
      _request(dpr: 2.625, logicalSize: const Size(344, 184)),
    );

    expect(artifact.pngBytes, same(bytes));
  });

  test(
    'capture rejects a fractional-DPR 231px PNG and accepts canonical 264px',
    () async {
      final nonCanonicalCapture = FeedThumbnailCapture(
        provider: _PngProvider(await _solidPngSized(231)),
      );
      final canonicalBytes = await _solidPngSized(264);
      final canonicalCapture = FeedThumbnailCapture(
        provider: _PngProvider(canonicalBytes),
      );

      await expectLater(
        nonCanonicalCapture.capture(_request(dpr: 2.625)),
        throwsA(isA<FeedThumbnailCaptureException>()),
      );
      final artifact = await canonicalCapture.capture(_request(dpr: 2.625));
      expect(artifact.pngBytes, same(canonicalBytes));
    },
  );

  test('capture rejects oversized PNG bytes', () async {
    final bytes = Uint8List(1024 * 1024 + 1)
      ..setAll(0, await _solidPngSized(88));
    final capture = FeedThumbnailCapture(provider: _PngProvider(bytes));

    await expectLater(
      capture.capture(_request(dpr: 1)),
      throwsA(isA<FeedThumbnailCaptureException>()),
    );
  });

  test('unavailable capture cannot produce an upload artifact', () async {
    const capture = FeedThumbnailCapture(provider: _UnavailableProvider());

    await expectLater(
      capture.capture(_request(dpr: 1)),
      throwsA(isA<FeedThumbnailCaptureException>()),
    );
  });

  test(
    'encoder preserves snapshot pixels without endpoint marker masks',
    () async {
      final emptyViewport = ActivityRouteThumbnailViewport.fromRoute(
        RunRouteSnapshot.empty,
        logicalSize: const Size(88, 88),
      );
      final encoded = await encodePrivacyMaskedPng(
        await _solidPng(),
        ActivityRouteSnapshotThumbnailGenerationRequest(
          logicalSize: Size(88, 88),
          devicePixelRatio: 2,
          styleId: 'test',
          camera: const ActivityRouteSnapshotCamera(
            centerLatitude: 0,
            centerLongitude: 0,
            zoom: 1,
          ),
          route: RunRouteSnapshot.empty,
          viewport: emptyViewport,
          projectedStart: const Offset(20, 20),
          projectedEnd: const Offset(60, 60),
        ),
      );
      final codec = await ui.instantiateImageCodec(encoded);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      expect(image.width, 176);
      expect(image.height, 176);
      final values = pixels!.buffer.asUint8List();
      expect(_rgbaAt(values, 176, 40, 40), const <int>[255, 255, 255, 255]);
      expect(_rgbaAt(values, 176, 120, 120), const <int>[255, 255, 255, 255]);
      image.dispose();
    },
  );

  test(
    'metric-only legacy thumbnail artifact uses canonical PNG dimensions',
    () async {
      final artifact = await const MetricHistoryThumbnailGenerator().generate(
        summary: defaultRunSummarySnapshot,
        devicePixelRatio: 2.625,
      );

      final details = _readPngDetailsForTest(artifact.pngBytes);
      expect(details, const Size(264, 264));
      expect(artifact.pngBytes.lengthInBytes, lessThan(1024 * 1024));
    },
  );

  test(
    'route history thumbnail artifact uses current wide card dimensions',
    () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final artifact = await const RouteHistoryThumbnailGenerator().generate(
        request: ActivityRouteThumbnailRequest(
          route: RunRouteSnapshot(
            segments: [
              [
                RunLocationSample(
                  recordedAt: startedAt,
                  latitude: 1.300000,
                  longitude: 103.800000,
                ),
                RunLocationSample(
                  recordedAt: startedAt.add(const Duration(seconds: 60)),
                  latitude: 1.300899,
                  longitude: 103.801250,
                ),
              ],
            ],
          ),
          logicalSize: const Size(344, 184),
          devicePixelRatio: 2.625,
          allowExternalStaticMap: true,
          isDemoRoute: false,
          isCurrentSessionRoute: true,
          activityId: 'activity-a',
        ),
      );

      final details = _readPngDetailsForTest(artifact.pngBytes);
      expect(details, const Size(1032, 552));
      expect(artifact.pngBytes.lengthInBytes, lessThan(1024 * 1024));
    },
  );
}

Future<Uint8List> _solidPng() async {
  return _solidPngSized(88);
}

Future<Uint8List> _solidPngSized(int width, {int? height}) async {
  final resolvedHeight = height ?? width;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), resolvedHeight.toDouble()),
    ui.Paint()..color = const Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(width, resolvedHeight);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

List<int> _rgbaAt(Uint8List values, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return values.sublist(offset, offset + 4);
}

Size _readPngDetailsForTest(Uint8List bytes) {
  expect(bytes.sublist(0, 8), const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  final width = _readU32ForTest(bytes, 16);
  final height = _readU32ForTest(bytes, 20);
  return Size(width.toDouble(), height.toDouble());
}

int _readU32ForTest(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

class _PngProvider implements ActivityRouteThumbnailProvider {
  const _PngProvider(this.bytes);
  final Uint8List bytes;
  @override
  Future<ActivityRouteThumbnailResult> resolve(
    ActivityRouteThumbnailRequest request,
  ) async => ActivityRouteThumbnailResult.readyPng(bytes);
}

class _UnavailableProvider implements ActivityRouteThumbnailProvider {
  const _UnavailableProvider();
  @override
  Future<ActivityRouteThumbnailResult> resolve(
    ActivityRouteThumbnailRequest request,
  ) async => const ActivityRouteThumbnailResult.timedOut();
}

ActivityRouteThumbnailRequest _request({
  required double dpr,
  Size logicalSize = const Size(88, 88),
}) => ActivityRouteThumbnailRequest(
  route: RunRouteSnapshot.empty,
  logicalSize: logicalSize,
  devicePixelRatio: dpr,
  allowExternalStaticMap: true,
  isDemoRoute: true,
  activityId: 'activity-a',
);

class _PngFixtureChunk {
  const _PngFixtureChunk(this.type, this.data);

  final String type;
  final List<int> data;
}

class _InvalidPngFixture {
  const _InvalidPngFixture(this.description, this.bytes);

  final String description;
  final Uint8List bytes;
}

final List<_InvalidPngFixture> _invalidPngFixtures = <_InvalidPngFixture>[
  _InvalidPngFixture('a corrupt chunk CRC', _corruptCrc(_validPngFixture())),
  _InvalidPngFixture(
    'a missing IDAT chunk',
    _validPngFixture(includeIdat: false),
  ),
  _InvalidPngFixture(
    'an empty IDAT chunk',
    _validPngFixture(idatData: const []),
  ),
  _InvalidPngFixture(
    'an empty first IDAT chunk',
    _validPngFixture(idatChunks: <List<int>>[<int>[], _opaqueRgbaIdat(88, 88)]),
  ),
  _InvalidPngFixture(
    'an empty middle IDAT chunk',
    _validPngFixture(idatChunks: _opaqueRgbaIdatChunksWithEmptyMiddle(88, 88)),
  ),
  _InvalidPngFixture(
    'an empty last IDAT chunk',
    _validPngFixture(idatChunks: <List<int>>[_opaqueRgbaIdat(88, 88), <int>[]]),
  ),
  _InvalidPngFixture(
    'a duplicate IHDR chunk',
    _validPngFixture(
      extraBeforeIdat: <_PngFixtureChunk>[_ihdrChunk(width: 88, height: 88)],
    ),
  ),
  _InvalidPngFixture(
    'a duplicate IEND chunk',
    _buildPngWithValidCrc(<_PngFixtureChunk>[
      ..._canonicalPngChunks(),
      const _PngFixtureChunk('IEND', <int>[]),
    ]),
  ),
  _InvalidPngFixture(
    'a duplicate ancillary chunk',
    _validPngFixture(
      extraBeforeIdat: const <_PngFixtureChunk>[
        _PngFixtureChunk('sRGB', <int>[0]),
      ],
    ),
  ),
  _InvalidPngFixture(
    'an unknown critical chunk',
    _validPngFixture(
      extraBeforeIdat: const <_PngFixtureChunk>[
        _PngFixtureChunk('ABCD', <int>[0]),
      ],
    ),
  ),
  _InvalidPngFixture(
    'an unknown ancillary chunk',
    _validPngFixture(
      extraBeforeIdat: const <_PngFixtureChunk>[
        _PngFixtureChunk('vpAg', <int>[0]),
      ],
    ),
  ),
  for (final type in <String>[
    'pHYs',
    'tEXt',
    'zTXt',
    'iTXt',
    'eXIf',
    'iCCP',
    'tIME',
  ])
    _InvalidPngFixture(
      'the prohibited $type ancillary chunk',
      _validPngFixture(
        extraBeforeIdat: <_PngFixtureChunk>[
          _PngFixtureChunk(type, <int>[0]),
        ],
      ),
    ),
  _InvalidPngFixture(
    'an invalid IHDR bit depth',
    _validPngFixture(bitDepth: 16),
  ),
  _InvalidPngFixture(
    'an invalid IHDR color type',
    _validPngFixture(colorType: 7),
  ),
  _InvalidPngFixture(
    'an invalid IHDR compression method',
    _validPngFixture(compressionMethod: 1),
  ),
  _InvalidPngFixture(
    'an invalid IHDR filter method',
    _validPngFixture(filterMethod: 1),
  ),
  _InvalidPngFixture(
    'an invalid IHDR interlace method',
    _validPngFixture(interlaceMethod: 1),
  ),
  _InvalidPngFixture('a zero-width IHDR', _validPngFixture(width: 0)),
  _InvalidPngFixture('a zero-height IHDR', _validPngFixture(height: 0)),
  _InvalidPngFixture(
    'a mismatched square dimension',
    _validPngFixture(width: 87),
  ),
  _InvalidPngFixture(
    'an invalid sBIT value',
    _validPngFixture(sbit: const <int>[8, 8, 8, 7]),
  ),
  _InvalidPngFixture(
    'an invalid sBIT length',
    _validPngFixture(sbit: const <int>[8, 8, 8]),
  ),
  _InvalidPngFixture(
    'an invalid sRGB rendering intent',
    _validPngFixture(srgb: const <int>[1]),
  ),
  _InvalidPngFixture(
    'an invalid sRGB length',
    _validPngFixture(srgb: const <int>[]),
  ),
  _InvalidPngFixture(
    'an invalid gAMA value',
    _validPngFixture(gama: const <int>[0, 0, 181, 142]),
  ),
  _InvalidPngFixture(
    'an invalid gAMA length',
    _validPngFixture(gama: const <int>[0, 0, 177]),
  ),
  _InvalidPngFixture(
    'a noncanonical cHRM value',
    _validPngFixture(
      chrm: const <int>[
        0,
        0,
        122,
        38,
        0,
        0,
        128,
        132,
        0,
        0,
        250,
        0,
        0,
        0,
        128,
        232,
        0,
        0,
        117,
        48,
        0,
        0,
        234,
        96,
        0,
        0,
        58,
        152,
        0,
        0,
        23,
        113,
      ],
    ),
  ),
  _InvalidPngFixture(
    'an ancillary chunk after IDAT',
    _validPngFixture(
      extraAfterIdat: const <_PngFixtureChunk>[
        _PngFixtureChunk('sRGB', <int>[0]),
      ],
    ),
  ),
  _InvalidPngFixture(
    'an invalid cHRM length',
    _validPngFixture(chrm: List<int>.filled(31, 0)),
  ),
  _InvalidPngFixture(
    'noncontiguous IDAT chunks',
    _validPngFixture(
      idatChunks: const <List<int>>[
        <int>[120, 1],
        <int>[0, 0, 0, 255, 255],
      ],
      extraBetweenIdat: const <_PngFixtureChunk>[
        _PngFixtureChunk('sRGB', <int>[0]),
      ],
    ),
  ),
  _InvalidPngFixture(
    'an IEND chunk followed by trailing bytes',
    _validPngFixture(trailingBytes: const <int>[0]),
  ),
  _InvalidPngFixture(
    'a nonterminal IEND chunk',
    _buildPngWithValidCrc(<_PngFixtureChunk>[
      ..._canonicalPngChunks(),
      const _PngFixtureChunk('IDAT', <int>[0]),
    ]),
  ),
  _InvalidPngFixture(
    'a missing IEND chunk',
    _buildPngWithValidCrc(_canonicalPngChunks().take(6).toList()),
  ),
];

Uint8List _validPngFixture({
  int width = 88,
  int? height,
  int bitDepth = 8,
  int colorType = 6,
  int compressionMethod = 0,
  int filterMethod = 0,
  int interlaceMethod = 0,
  List<int> sbit = const <int>[8, 8, 8, 8],
  List<int> srgb = const <int>[0],
  List<int> gama = const <int>[0, 0, 177, 143],
  List<int> chrm = const <int>[
    0,
    0,
    122,
    38,
    0,
    0,
    128,
    132,
    0,
    0,
    250,
    0,
    0,
    0,
    128,
    232,
    0,
    0,
    117,
    48,
    0,
    0,
    234,
    96,
    0,
    0,
    58,
    152,
    0,
    0,
    23,
    112,
  ],
  bool includeIdat = true,
  List<int>? idatData,
  List<List<int>>? idatChunks,
  List<_PngFixtureChunk> extraBeforeIdat = const <_PngFixtureChunk>[],
  List<_PngFixtureChunk> extraBetweenIdat = const <_PngFixtureChunk>[],
  List<_PngFixtureChunk> extraAfterIdat = const <_PngFixtureChunk>[],
  List<int> trailingBytes = const <int>[],
}) {
  final resolvedHeight = height ?? width;
  final chunks = <_PngFixtureChunk>[
    _ihdrChunk(
      width: width,
      height: resolvedHeight,
      bitDepth: bitDepth,
      colorType: colorType,
      compressionMethod: compressionMethod,
      filterMethod: filterMethod,
      interlaceMethod: interlaceMethod,
    ),
    _PngFixtureChunk('sBIT', sbit),
    _PngFixtureChunk('sRGB', srgb),
    _PngFixtureChunk('gAMA', gama),
    _PngFixtureChunk('cHRM', chrm),
    ...extraBeforeIdat,
  ];
  if (includeIdat) {
    final chunksToAdd =
        idatChunks ??
        <List<int>>[idatData ?? _opaqueRgbaIdat(width, resolvedHeight)];
    for (var index = 0; index < chunksToAdd.length; index += 1) {
      chunks.add(_PngFixtureChunk('IDAT', chunksToAdd[index]));
      if (index == 0) chunks.addAll(extraBetweenIdat);
    }
  }
  chunks
    ..addAll(extraAfterIdat)
    ..add(const _PngFixtureChunk('IEND', <int>[]));
  return _buildPngWithValidCrc(chunks, trailingBytes: trailingBytes);
}

List<_PngFixtureChunk> _canonicalPngChunks() => <_PngFixtureChunk>[
  _ihdrChunk(width: 88, height: 88),
  const _PngFixtureChunk('sBIT', <int>[8, 8, 8, 8]),
  const _PngFixtureChunk('sRGB', <int>[0]),
  const _PngFixtureChunk('gAMA', <int>[0, 0, 177, 143]),
  const _PngFixtureChunk('cHRM', <int>[
    0,
    0,
    122,
    38,
    0,
    0,
    128,
    132,
    0,
    0,
    250,
    0,
    0,
    0,
    128,
    232,
    0,
    0,
    117,
    48,
    0,
    0,
    234,
    96,
    0,
    0,
    58,
    152,
    0,
    0,
    23,
    112,
  ]),
  _PngFixtureChunk('IDAT', _opaqueRgbaIdat(88, 88)),
  const _PngFixtureChunk('IEND', <int>[]),
];

_PngFixtureChunk _ihdrChunk({
  required int width,
  required int height,
  int bitDepth = 8,
  int colorType = 6,
  int compressionMethod = 0,
  int filterMethod = 0,
  int interlaceMethod = 0,
}) => _PngFixtureChunk('IHDR', <int>[
  (width >> 24) & 0xff,
  (width >> 16) & 0xff,
  (width >> 8) & 0xff,
  width & 0xff,
  (height >> 24) & 0xff,
  (height >> 16) & 0xff,
  (height >> 8) & 0xff,
  height & 0xff,
  bitDepth,
  colorType,
  compressionMethod,
  filterMethod,
  interlaceMethod,
]);

Uint8List _buildPngWithValidCrc(
  List<_PngFixtureChunk> chunks, {
  List<int> trailingBytes = const <int>[],
}) {
  final bytes = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  for (final chunk in chunks) {
    final length = chunk.data.length;
    bytes.addAll(<int>[
      (length >> 24) & 0xff,
      (length >> 16) & 0xff,
      (length >> 8) & 0xff,
      length & 0xff,
    ]);
    final typeAndData = <int>[...chunk.type.codeUnits, ...chunk.data];
    bytes.addAll(typeAndData);
    final crc = _crc32(typeAndData);
    bytes.addAll(<int>[
      (crc >> 24) & 0xff,
      (crc >> 16) & 0xff,
      (crc >> 8) & 0xff,
      crc & 0xff,
    ]);
  }
  bytes.addAll(trailingBytes);
  return Uint8List.fromList(bytes);
}

Uint8List _corruptCrc(Uint8List bytes) {
  final corrupted = Uint8List.fromList(bytes);
  corrupted[corrupted.length - 1] ^= 1;
  return corrupted;
}

List<int> _opaqueRgbaIdat(int width, int height) {
  final raw = <int>[];
  for (var y = 0; y < height; y += 1) {
    raw.add(0);
    for (var x = 0; x < width; x += 1) {
      raw.addAll(const <int>[255, 255, 255, 255]);
    }
  }
  final zlib = <int>[120, 1];
  var offset = 0;
  while (offset < raw.length) {
    final length = (raw.length - offset).clamp(0, 65535);
    final isFinal = offset + length == raw.length;
    zlib.add(isFinal ? 1 : 0);
    zlib.addAll(<int>[length & 0xff, length >> 8]);
    final complement = 0xffff - length;
    zlib.addAll(<int>[complement & 0xff, complement >> 8]);
    zlib.addAll(raw.sublist(offset, offset + length));
    offset += length;
  }
  var a = 1;
  var b = 0;
  for (final value in raw) {
    a = (a + value) % 65521;
    b = (b + a) % 65521;
  }
  final adler = (b << 16) | a;
  zlib.addAll(<int>[
    (adler >> 24) & 0xff,
    (adler >> 16) & 0xff,
    (adler >> 8) & 0xff,
    adler & 0xff,
  ]);
  return zlib;
}

List<List<int>> _splitOpaqueRgbaIdatChunks(int width, int height) {
  final idat = _opaqueRgbaIdat(width, height);
  final splitOffset = idat.length ~/ 2;
  return <List<int>>[idat.sublist(0, splitOffset), idat.sublist(splitOffset)];
}

List<List<int>> _opaqueRgbaIdatChunksWithEmptyMiddle(int width, int height) {
  final chunks = _splitOpaqueRgbaIdatChunks(width, height);
  return <List<int>>[chunks.first, <int>[], chunks.last];
}

int _crc32(List<int> values) {
  var crc = 0xffffffff;
  for (final value in values) {
    crc ^= value;
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb88320;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
