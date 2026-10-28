import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player/video_ultra_player_method_channel.dart';
import 'package:video_ultra_player/video_ultra_player_platform_interface.dart';

class MockVideoUltraPlayerPlatform
    with MockPlatformInterfaceMixin
    implements VideoUltraPlayerPlatform {
  final calls = <String>[];
  List<Map<String, dynamic>>? loadedClips;
  Map<String, dynamic>? lastConfig;
  int? lastTextureId;
  Duration? lastSeekPosition;
  double? lastVolume;
  int? lastClipIndex;
  double? lastAlignmentX;
  double? lastAlignmentY;
  int? lastTrimStartMs;
  int? lastTrimEndMs;
  int? lastAtLocalPositionMs;
  int? lastAtIndex;
  Map<String, dynamic>? lastClipPayload;
  int? lastFromIndex;
  int? lastToIndex;
  double? lastSpeed;
  String? lastGenerateThumbnailsPath;
  List<int>? lastGenerateThumbnailsTimestampsMs;
  int? lastGenerateThumbnailsWidth;
  Map<String, dynamic>? lastAudioTrackPayload;
  Map<String, dynamic>? lastTextOverlayPayload;
  String? lastRemovedTextOverlayId;
  List<Map<String, dynamic>>? lastCaptionsCues;
  Map<String, dynamic>? lastCaptionsStyle;
  String? lastExtractAudioOutputPath;
  Map<String, dynamic>? lastGridPayload;
  String? lastGridOutputPath;
  final stateController = StreamController<TimelinePlayerState>.broadcast();
  final exportProgressController =
      StreamController<TimelineExportProgress>.broadcast();
  Completer<String>? exportCompleter;

  @override
  Future<int> load(
    List<Map<String, dynamic>> clips, {
    Map<String, dynamic>? config,
  }) async {
    calls.add('load');
    loadedClips = clips;
    lastConfig = config;
    return 42;
  }

  @override
  Future<String> exportTimeline(
    List<Map<String, dynamic>> clips, {
    String? outputPath,
    Map<String, dynamic>? config,
  }) async {
    calls.add('exportTimeline');
    loadedClips = clips;
    lastConfig = config;
    if (exportCompleter != null) {
      return exportCompleter!.future;
    }
    return outputPath ?? '/tmp/exported.mp4';
  }

  @override
  Future<String> renderGrid(
    Map<String, dynamic> grid, {
    required String outputPath,
  }) async {
    calls.add('renderGrid');
    lastGridPayload = grid;
    lastGridOutputPath = outputPath;
    if (exportCompleter != null) {
      return exportCompleter!.future;
    }
    return outputPath;
  }

  @override
  Future<void> play(int textureId) async {
    calls.add('play');
    lastTextureId = textureId;
  }

  @override
  Future<void> pause(int textureId) async {
    calls.add('pause');
    lastTextureId = textureId;
  }

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    calls.add('seekTo');
    lastTextureId = textureId;
    lastSeekPosition = position;
  }

  @override
  Future<void> seekToClip(int textureId, int clipIndex) async {
    calls.add('seekToClip');
    lastTextureId = textureId;
    lastClipIndex = clipIndex;
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    calls.add('setVolume');
    lastTextureId = textureId;
    lastVolume = volume;
  }

  @override
  Future<void> setClipAlignment(
    int textureId,
    int clipIndex,
    double x,
    double y,
  ) async {
    calls.add('setClipAlignment');
    lastTextureId = textureId;
    lastClipIndex = clipIndex;
    lastAlignmentX = x;
    lastAlignmentY = y;
  }

  @override
  Future<void> setCompositionConfig(
    int textureId,
    Map<String, dynamic> config,
  ) async {
    calls.add('setCompositionConfig');
    lastTextureId = textureId;
    lastConfig = config;
  }

  @override
  Future<void> dispose(int textureId) async {
    calls.add('dispose');
    lastTextureId = textureId;
  }

  @override
  Stream<TimelinePlayerState> stateStream(int textureId) {
    calls.add('stateStream');
    lastTextureId = textureId;
    return stateController.stream;
  }

  @override
  Stream<TimelineExportProgress> exportProgress() {
    calls.add('exportProgress');
    return exportProgressController.stream;
  }

  @override
  Future<String> exportCurrentTimeline(
    int textureId, {
    String? outputPath,
  }) async {
    calls.add('exportCurrentTimeline');
    lastTextureId = textureId;
    if (exportCompleter != null) {
      return exportCompleter!.future;
    }
    return outputPath ?? '/tmp/exported_current.mp4';
  }

  @override
  Future<void> trimClip(
    int textureId,
    int clipIndex, {
    int? trimStartMs,
    int? trimEndMs,
  }) async {
    calls.add('trimClip');
    lastTextureId = textureId;
    lastClipIndex = clipIndex;
    lastTrimStartMs = trimStartMs;
    lastTrimEndMs = trimEndMs;
  }

  @override
  Future<void> splitClip(
    int textureId,
    int clipIndex,
    int atLocalPositionMs,
  ) async {
    calls.add('splitClip');
    lastTextureId = textureId;
    lastClipIndex = clipIndex;
    lastAtLocalPositionMs = atLocalPositionMs;
  }

  @override
  Future<void> insertClip(
    int textureId,
    int atIndex,
    Map<String, dynamic> clip,
  ) async {
    calls.add('insertClip');
    lastTextureId = textureId;
    lastAtIndex = atIndex;
    lastClipPayload = clip;
  }

  @override
  Future<void> removeClip(int textureId, int clipIndex) async {
    calls.add('removeClip');
    lastTextureId = textureId;
    lastClipIndex = clipIndex;
  }

  @override
  Future<void> moveClip(int textureId, int fromIndex, int toIndex) async {
    calls.add('moveClip');
    lastTextureId = textureId;
    lastFromIndex = fromIndex;
    lastToIndex = toIndex;
  }

  @override
  Future<void> replaceClip(
    int textureId,
    int clipIndex,
    Map<String, dynamic> clip,
  ) async {
    calls.add('replaceClip');
    lastTextureId = textureId;
    lastClipIndex = clipIndex;
    lastClipPayload = clip;
  }

  @override
  Future<void> setClipSpeed(int textureId, int clipIndex, double speed) async {
    calls.add('setClipSpeed');
    lastTextureId = textureId;
    lastClipIndex = clipIndex;
    lastSpeed = speed;
  }

  @override
  Future<void> undo(int textureId) async {
    calls.add('undo');
    lastTextureId = textureId;
  }

  @override
  Future<void> redo(int textureId) async {
    calls.add('redo');
    lastTextureId = textureId;
  }

  @override
  Future<List<String>> generateThumbnails(
    String videoPath,
    List<int> timestampsMs, {
    int width = 120,
  }) async {
    calls.add('generateThumbnails');
    lastGenerateThumbnailsPath = videoPath;
    lastGenerateThumbnailsTimestampsMs = timestampsMs;
    lastGenerateThumbnailsWidth = width;
    return timestampsMs.map((ts) => '/tmp/thumb_${ts}_$width.jpg').toList();
  }

  @override
  Future<void> setAudioTrack(int textureId, Map<String, dynamic> track) async {
    calls.add('setAudioTrack');
    lastTextureId = textureId;
    lastAudioTrackPayload = track;
  }

  @override
  Future<void> removeAudioTrack(int textureId) async {
    calls.add('removeAudioTrack');
    lastTextureId = textureId;
  }

  Map<String, dynamic>? lastVideoLayerPayload;
  String? lastRemovedVideoLayerId;
  Object? addVideoLayerError;

  @override
  Future<Map<String, dynamic>> addVideoLayer(
    int textureId,
    Map<String, dynamic> layer,
  ) async {
    calls.add('addVideoLayer');
    lastTextureId = textureId;
    lastVideoLayerPayload = layer;
    final error = addVideoLayerError;
    if (error != null) throw error;
    return <String, dynamic>{
      ...layer,
      'trimEndMs': 5000,
      'sourceWidth': 1080,
      'sourceHeight': 1920,
    };
  }

  @override
  Future<void> updateVideoLayer(
    int textureId,
    Map<String, dynamic> layer,
  ) async {
    calls.add('updateVideoLayer');
    lastTextureId = textureId;
    lastVideoLayerPayload = layer;
  }

  @override
  Future<void> removeVideoLayer(int textureId, String layerId) async {
    calls.add('removeVideoLayer');
    lastTextureId = textureId;
    lastRemovedVideoLayerId = layerId;
  }

  @override
  Future<void> addTextOverlay(
    int textureId,
    Map<String, dynamic> overlay,
  ) async {
    calls.add('addTextOverlay');
    lastTextureId = textureId;
    lastTextOverlayPayload = overlay;
  }

  @override
  Future<void> updateTextOverlay(
    int textureId,
    Map<String, dynamic> overlay,
  ) async {
    calls.add('updateTextOverlay');
    lastTextureId = textureId;
    lastTextOverlayPayload = overlay;
  }

  @override
  Future<void> removeTextOverlay(int textureId, String overlayId) async {
    calls.add('removeTextOverlay');
    lastTextureId = textureId;
    lastRemovedTextOverlayId = overlayId;
  }

  @override
  Future<void> setCaptions(
    int textureId,
    List<Map<String, dynamic>> cues,
    Map<String, dynamic> style,
  ) async {
    calls.add('setCaptions');
    lastTextureId = textureId;
    lastCaptionsCues = cues;
    lastCaptionsStyle = style;
  }

  @override
  Future<void> removeCaptions(int textureId) async {
    calls.add('removeCaptions');
    lastTextureId = textureId;
  }

  @override
  Future<String> extractAudio(
    int textureId, {
    required String outputPath,
    int sampleRate = 16000,
  }) async {
    calls.add('extractAudio');
    lastTextureId = textureId;
    lastExtractAudioOutputPath = outputPath;
    return outputPath;
  }
}

void main() {
  late VideoUltraPlayerPlatform initialPlatform;
  late MockVideoUltraPlayerPlatform fakePlatform;

  setUp(() {
    initialPlatform = VideoUltraPlayerPlatform.instance;
    fakePlatform = MockVideoUltraPlayerPlatform();
    VideoUltraPlayerPlatform.instance = fakePlatform;
  });

  tearDown(() async {
    await fakePlatform.stateController.close();
    await fakePlatform.exportProgressController.close();
    VideoUltraPlayerPlatform.instance = initialPlatform;
  });

  test('$MethodChannelVideoUltraPlayer is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelVideoUltraPlayer>());
  });

  test('load forwards serialized clips and stores texture id', () async {
    final player = NativeTimelinePlayer();

    final textureId = await player.load(const [
      TimelineClip(
        path: '/tmp/a.mp4',
        type: MediaType.video,
        duration: Duration(seconds: 2),
        alignment: Alignment.topLeft,
        scale: 1.25,
      ),
    ]);

    expect(textureId, 42);
    expect(player.textureId, 42);
    expect(fakePlatform.loadedClips, [
      <String, dynamic>{
        'path': '/tmp/a.mp4',
        'type': 'video',
        'durationMs': 2000,
        'alignment': <String, double>{'x': -1, 'y': -1},
        'scale': 1.25,
        'speed': 1.0,
      },
    ]);
    expect(fakePlatform.lastConfig, {
      'aspectRatio': 'original',
      'baseWidth': 1080,
      'hdrMode': 'keepHdr',
      'preserveSourceQuality': false,
      'enablePreview': true,
    });
  });

  test('load forwards serialized composition config', () async {
    final player = NativeTimelinePlayer();

    await player.load(
      const [TimelineClip(path: '/tmp/a.mp4', type: MediaType.video)],
      config: TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.ratio16x9,
        baseWidth: 1920,
        hdrMode: TimelineHdrMode.toneMapToSdrUsingMediaCodec,
        preserveSourceQuality: true,
      ),
    );

    expect(fakePlatform.lastConfig, {
      'aspectRatio': 'ratio16x9',
      'baseWidth': 1920,
      'hdrMode': 'toneMapToSdrUsingMediaCodec',
      'preserveSourceQuality': true,
      'enablePreview': true,
    });
  });

  test(
    'exportTimeline forwards serialized clips without requiring load',
    () async {
      final player = NativeTimelinePlayer();

      final outputPath = await player.exportTimeline(const [
        TimelineClip(
          path: '/tmp/a.mp4',
          type: MediaType.video,
          duration: Duration(seconds: 2),
          alignment: Alignment.bottomRight,
          scale: 1.5,
        ),
      ], outputPath: '/tmp/final.mp4');

      expect(outputPath, '/tmp/final.mp4');
      expect(fakePlatform.calls, ['exportTimeline']);
      expect(fakePlatform.loadedClips, [
        <String, dynamic>{
          'path': '/tmp/a.mp4',
          'type': 'video',
          'durationMs': 2000,
          'alignment': <String, double>{'x': 1, 'y': 1},
          'scale': 1.5,
          'speed': 1.0,
        },
      ]);
      expect(fakePlatform.lastConfig, {
        'aspectRatio': 'original',
        'baseWidth': 1080,
        'hdrMode': 'keepHdr',
        'preserveSourceQuality': false,
        'enablePreview': true,
      });
    },
  );

  test('exportTimeline forwards serialized composition config', () async {
    final player = NativeTimelinePlayer();

    await player.exportTimeline(
      const [TimelineClip(path: '/tmp/a.mp4', type: MediaType.video)],
      config: TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.ratio1x1,
        baseWidth: 1200,
      ),
    );

    expect(fakePlatform.lastConfig, {
      'aspectRatio': 'ratio1x1',
      'baseWidth': 1200,
      'hdrMode': 'keepHdr',
      'preserveSourceQuality': false,
      'enablePreview': true,
    });
  });

  test('exportProgress requires export in progress', () async {
    final player = NativeTimelinePlayer();

    expect(() => player.exportProgress, throwsStateError);

    fakePlatform.exportCompleter = Completer<String>();
    final exportFuture = player.exportTimeline(const [
      TimelineClip(path: '/tmp/a.mp4', type: MediaType.video),
    ]);
    final expectation = expectLater(
      player.exportProgress,
      emits(
        const TimelineExportProgress(
          progress: 0.5,
          state: TimelineExportState.exporting,
        ),
      ),
    );

    fakePlatform.exportProgressController.add(
      const TimelineExportProgress(
        progress: 0.5,
        state: TimelineExportState.exporting,
      ),
    );
    fakePlatform.exportCompleter!.complete('/tmp/final.mp4');

    await expectation;
    await exportFuture;
    expect(() => player.exportProgress, throwsStateError);
  });

  test('exportTimeline rejects empty clip list', () {
    final player = NativeTimelinePlayer();

    expect(() => player.exportTimeline(const []), throwsArgumentError);
  });

  test('setCompositionConfig forwards the new config in place', () async {
    final player = NativeTimelinePlayer();
    await player.load(
      const [TimelineClip(path: '/tmp/a.mp4', type: MediaType.video)],
      config: TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.ratio9x16,
      ),
    );

    await player.setCompositionConfig(
      TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.ratio1x1,
        baseWidth: 720,
      ),
    );

    expect(fakePlatform.calls, ['load', 'setCompositionConfig']);
    expect(fakePlatform.lastTextureId, 42);
    expect(fakePlatform.lastConfig, {
      'aspectRatio': 'ratio1x1',
      'baseWidth': 720,
      'hdrMode': 'keepHdr',
      'preserveSourceQuality': false,
      'enablePreview': true,
    });
    // The texture survives — no dispose/load cycle.
    expect(player.textureId, 42);
  });

  test('setCompositionConfig skips the channel when nothing changed', () async {
    final config = TimelineCompositionConfig(
      aspectRatio: OutputAspectRatio.ratio16x9,
    );
    final player = NativeTimelinePlayer();
    await player.load(const [
      TimelineClip(path: '/tmp/a.mp4', type: MediaType.video),
    ], config: config);

    await player.setCompositionConfig(config);
    await player.setCompositionConfig(
      TimelineCompositionConfig(aspectRatio: OutputAspectRatio.ratio16x9),
    );

    expect(fakePlatform.calls, ['load']);
    expect(player.compositionConfig, config);
  });

  test('setCompositionConfig requires a loaded timeline', () {
    final player = NativeTimelinePlayer();

    expect(
      () => player.setCompositionConfig(TimelineCompositionConfig()),
      throwsStateError,
    );
  });

  test('commands forward texture id and arguments', () async {
    final player = NativeTimelinePlayer();
    await player.load(const [
      TimelineClip(path: '/tmp/a.mp4', type: MediaType.video),
    ]);

    await player.play();
    await player.pause();
    await player.seekTo(const Duration(milliseconds: 1200));
    await player.seekToClip(2);
    await player.setVolume(0.7);
    await player.setClipAlignment(1, -0.25, 0.5);
    await player.dispose();

    expect(fakePlatform.calls, [
      'load',
      'play',
      'pause',
      'seekTo',
      'seekToClip',
      'setVolume',
      'setClipAlignment',
      'dispose',
    ]);
    expect(fakePlatform.lastTextureId, 42);
    expect(fakePlatform.lastSeekPosition, const Duration(milliseconds: 1200));
    expect(fakePlatform.lastVolume, 0.7);
    expect(fakePlatform.lastClipIndex, 1);
    expect(fakePlatform.lastAlignmentX, -0.25);
    expect(fakePlatform.lastAlignmentY, 0.5);
    expect(player.textureId, isNull);
  });

  test('setVolume validates accepted range', () async {
    final player = NativeTimelinePlayer();
    await player.load(const [
      TimelineClip(path: '/tmp/a.mp4', type: MediaType.video),
    ]);

    expect(() => player.setVolume(-0.1), throwsRangeError);
    expect(() => player.setVolume(1.1), throwsRangeError);
  });

  test('stateStream emits TimelinePlayerState from platform stream', () async {
    final player = NativeTimelinePlayer();
    await player.load(const [
      TimelineClip(path: '/tmp/a.mp4', type: MediaType.video),
    ]);

    final expectation = expectLater(
      player.stateStream,
      emits(
        const TimelinePlayerState(
          globalPosition: Duration(milliseconds: 900),
          clipIndex: 1,
          localPosition: Duration(milliseconds: 150),
          isPlaying: true,
          totalDuration: Duration(milliseconds: 2400),
        ),
      ),
    );

    fakePlatform.stateController.add(
      const TimelinePlayerState(
        globalPosition: Duration(milliseconds: 900),
        clipIndex: 1,
        localPosition: Duration(milliseconds: 150),
        isPlaying: true,
        totalDuration: Duration(milliseconds: 2400),
      ),
    );

    await expectation;
  });

  test('seekToClip forwards clip index to platform', () async {
    final player = NativeTimelinePlayer();
    await player.load(const [
      TimelineClip(path: '/tmp/a.mp4', type: MediaType.video),
    ]);

    await player.seekToClip(3);

    expect(fakePlatform.calls, contains('seekToClip'));
    expect(fakePlatform.lastClipIndex, 3);
  });

  test('commands before load throw StateError', () {
    final player = NativeTimelinePlayer();

    expect(() => player.play(), throwsStateError);
    expect(() => player.seekToClip(0), throwsStateError);
    expect(() => player.undo(), throwsStateError);
    expect(() => player.redo(), throwsStateError);
    expect(() => player.stateStream, throwsStateError);
  });

  // ── Editing operations ────────────────────────────────────────────────

  group('editing operations require load', () {
    test('trimClip throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(() => player.trimClip(0), throwsStateError);
    });

    test('splitClip throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(
        () => player.splitClip(0, const Duration(seconds: 1)),
        throwsStateError,
      );
    });

    test('insertClip throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(
        () => player.insertClip(
          0,
          const TimelineClip(path: '/b.mp4', type: MediaType.video),
        ),
        throwsStateError,
      );
    });

    test('removeClip throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(() => player.removeClip(0), throwsStateError);
    });

    test('moveClip throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(() => player.moveClip(0, 1), throwsStateError);
    });

    test('replaceClip throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(
        () => player.replaceClip(
          0,
          const TimelineClip(path: '/b.mp4', type: MediaType.video),
        ),
        throwsStateError,
      );
    });

    test('exportCurrentTimeline throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(() => player.exportCurrentTimeline(), throwsStateError);
    });
  });

  group('editing operations delegate to platform', () {
    late NativeTimelinePlayer player;

    setUp(() async {
      player = NativeTimelinePlayer(platform: fakePlatform);
      await player.load(const [
        TimelineClip(path: '/a.mp4', type: MediaType.video),
      ]);
    });

    test('trimClip forwards clipIndex and trim bounds', () async {
      await player.trimClip(
        2,
        trimStart: const Duration(milliseconds: 500),
        trimEnd: const Duration(seconds: 3),
      );
      expect(fakePlatform.calls, contains('trimClip'));
      expect(fakePlatform.lastClipIndex, 2);
      expect(fakePlatform.lastTrimStartMs, 500);
      expect(fakePlatform.lastTrimEndMs, 3000);
      expect(fakePlatform.lastTextureId, 42);
    });

    test('trimClip with null args passes null to platform', () async {
      await player.trimClip(1);
      expect(fakePlatform.lastTrimStartMs, isNull);
      expect(fakePlatform.lastTrimEndMs, isNull);
    });

    test('splitClip forwards clipIndex and position', () async {
      await player.splitClip(1, const Duration(milliseconds: 1200));
      expect(fakePlatform.calls, contains('splitClip'));
      expect(fakePlatform.lastClipIndex, 1);
      expect(fakePlatform.lastAtLocalPositionMs, 1200);
      expect(fakePlatform.lastTextureId, 42);
    });

    test('splitClip rejects atLocalPosition <= zero', () {
      expect(() => player.splitClip(0, Duration.zero), throwsArgumentError);
    });

    test('insertClip forwards atIndex and serialized clip', () async {
      const clip = TimelineClip(
        path: '/b.mp4',
        type: MediaType.image,
        duration: Duration(seconds: 2),
      );
      await player.insertClip(1, clip);
      expect(fakePlatform.calls, contains('insertClip'));
      expect(fakePlatform.lastAtIndex, 1);
      expect(fakePlatform.lastClipPayload?['path'], '/b.mp4');
      expect(fakePlatform.lastClipPayload?['type'], 'image');
      expect(fakePlatform.lastTextureId, 42);
    });

    test('removeClip forwards clipIndex', () async {
      await player.removeClip(2);
      expect(fakePlatform.calls, contains('removeClip'));
      expect(fakePlatform.lastClipIndex, 2);
      expect(fakePlatform.lastTextureId, 42);
    });

    test('moveClip forwards fromIndex and toIndex', () async {
      await player.moveClip(0, 2);
      expect(fakePlatform.calls, contains('moveClip'));
      expect(fakePlatform.lastFromIndex, 0);
      expect(fakePlatform.lastToIndex, 2);
      expect(fakePlatform.lastTextureId, 42);
    });

    test('moveClip is no-op when fromIndex == toIndex', () async {
      await player.moveClip(1, 1);
      expect(fakePlatform.calls, isNot(contains('moveClip')));
    });

    test('replaceClip forwards clipIndex and serialized clip', () async {
      const clip = TimelineClip(
        path: '/c.mp4',
        type: MediaType.video,
        trimStart: Duration(milliseconds: 500),
      );
      await player.replaceClip(0, clip);
      expect(fakePlatform.calls, contains('replaceClip'));
      expect(fakePlatform.lastClipIndex, 0);
      expect(fakePlatform.lastClipPayload?['path'], '/c.mp4');
      expect(fakePlatform.lastClipPayload?['trimStartMs'], 500);
    });

    test(
      'exportCurrentTimeline delegates with textureId and outputPath',
      () async {
        final path = await player.exportCurrentTimeline(
          outputPath: '/tmp/out.mp4',
        );
        expect(path, '/tmp/out.mp4');
        expect(fakePlatform.calls, contains('exportCurrentTimeline'));
        expect(fakePlatform.lastTextureId, 42);
      },
    );

    test('exportCurrentTimeline rejects concurrent export', () async {
      fakePlatform.exportCompleter = Completer<String>();
      final firstExport = player.exportCurrentTimeline();
      expect(() => player.exportCurrentTimeline(), throwsStateError);
      fakePlatform.exportCompleter!.complete('/tmp/out.mp4');
      await firstExport;
      fakePlatform.exportCompleter = null;
    });

    test('setClipSpeed forwards clipIndex and speed to platform', () async {
      await player.setClipSpeed(0, 1.5);
      expect(fakePlatform.calls, contains('setClipSpeed'));
      expect(fakePlatform.lastClipIndex, 0);
      expect(fakePlatform.lastSpeed, 1.5);
      expect(fakePlatform.lastTextureId, 42);
    });

    test('undo and redo delegate to platform with textureId', () async {
      await player.undo();
      await player.redo();

      expect(fakePlatform.calls, containsAllInOrder(['undo', 'redo']));
      expect(fakePlatform.lastTextureId, 42);
    });
  });

  group('editing argument validation', () {
    late NativeTimelinePlayer player;

    setUp(() async {
      player = NativeTimelinePlayer(platform: fakePlatform);
      await player.load(const [
        TimelineClip(path: '/a.mp4', type: MediaType.video),
      ]);
    });

    test('trimClip rejects negative clipIndex', () {
      expect(() => player.trimClip(-1), throwsArgumentError);
    });

    test('splitClip rejects negative clipIndex', () {
      expect(
        () => player.splitClip(-1, const Duration(seconds: 1)),
        throwsArgumentError,
      );
    });

    test('insertClip rejects negative atIndex', () {
      expect(
        () => player.insertClip(
          -1,
          const TimelineClip(path: '/b.mp4', type: MediaType.video),
        ),
        throwsArgumentError,
      );
    });

    test('removeClip rejects negative clipIndex', () {
      expect(() => player.removeClip(-1), throwsArgumentError);
    });

    test('moveClip rejects negative fromIndex', () {
      expect(() => player.moveClip(-1, 0), throwsArgumentError);
    });

    test('moveClip rejects negative toIndex', () {
      expect(() => player.moveClip(0, -1), throwsArgumentError);
    });

    test('replaceClip rejects negative clipIndex', () {
      expect(
        () => player.replaceClip(
          -1,
          const TimelineClip(path: '/b.mp4', type: MediaType.video),
        ),
        throwsArgumentError,
      );
    });

    test('setClipSpeed rejects negative clipIndex', () {
      expect(() => player.setClipSpeed(-1, 1.0), throwsArgumentError);
    });

    test('setClipSpeed rejects speed below 0.5', () {
      expect(() => player.setClipSpeed(0, 0.3), throwsRangeError);
    });

    test('setClipSpeed rejects speed above 2.0', () {
      expect(() => player.setClipSpeed(0, 2.5), throwsRangeError);
    });
  });

  group('renderGrid', () {
    TimelineGridComposition grid() => TimelineGridComposition(
      width: 1080,
      height: 1920,
      videoCells: const [
        TimelineGridCell(path: '/a.mp4', rect: Rect.fromLTWH(0, 0, 1, 0.5)),
        TimelineGridCell(path: '/b.mp4', rect: Rect.fromLTWH(0, 0.5, 1, 0.5)),
      ],
      overlayImagePath: '/overlay.png',
      audioCellIndex: 1,
      maxDuration: const Duration(seconds: 30),
    );

    test('works without load and forwards the serialized grid', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);

      final path = await player.renderGrid(grid(), outputPath: '/tmp/g.mp4');

      expect(path, '/tmp/g.mp4');
      expect(fakePlatform.lastGridOutputPath, '/tmp/g.mp4');
      expect(fakePlatform.lastGridPayload, {
        'width': 1080,
        'height': 1920,
        'cells': [
          {'path': '/a.mp4', 'x': 0.0, 'y': 0.0, 'width': 1.0, 'height': 0.5},
          {'path': '/b.mp4', 'x': 0.0, 'y': 0.5, 'width': 1.0, 'height': 0.5},
        ],
        'overlayImagePath': '/overlay.png',
        'audioCellIndex': 1,
        'maxDurationMs': 30000,
      });
    });

    test('shares the single export slot', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      fakePlatform.exportCompleter = Completer<String>();

      final first = player.renderGrid(grid(), outputPath: '/tmp/g.mp4');
      expect(
        () => player.renderGrid(grid(), outputPath: '/tmp/h.mp4'),
        throwsStateError,
      );
      fakePlatform.exportCompleter!.complete('/tmp/g.mp4');
      await first;
      fakePlatform.exportCompleter = null;
    });

    test('rejects an empty output path', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(
        () => player.renderGrid(grid(), outputPath: ''),
        throwsArgumentError,
      );
    });
  });

  group('generateThumbnails', () {
    test(
      'delegates to platform with converted milliseconds and default width',
      () async {
        final player = NativeTimelinePlayer(platform: fakePlatform);

        final paths = await player.generateThumbnails('/path/video.mp4', [
          Duration.zero,
          const Duration(seconds: 1),
        ]);

        expect(fakePlatform.calls, contains('generateThumbnails'));
        expect(fakePlatform.lastGenerateThumbnailsPath, '/path/video.mp4');
        expect(fakePlatform.lastGenerateThumbnailsTimestampsMs, [0, 1000]);
        expect(fakePlatform.lastGenerateThumbnailsWidth, 120);
        expect(paths, ['/tmp/thumb_0_120.jpg', '/tmp/thumb_1000_120.jpg']);
      },
    );

    test('forwards custom width to platform', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);

      await player.generateThumbnails('/path/video.mp4', [
        const Duration(milliseconds: 500),
      ], width: 240);

      expect(fakePlatform.lastGenerateThumbnailsWidth, 240);
    });

    test('returns empty list for empty timestamp list', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);

      final paths = await player.generateThumbnails('/path/video.mp4', []);

      expect(paths, isEmpty);
    });
  });

  // ── Audio track ──────────────────────────────────────────────────────────

  group('setAudioTrack', () {
    test('throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      const track = AudioTrack(path: '/music/bg.mp3');
      expect(() => player.setAudioTrack(track), throwsStateError);
    });

    test(
      'calls platform.setAudioTrack with textureId and serialized track after load',
      () async {
        final player = NativeTimelinePlayer(platform: fakePlatform);
        await player.load(const [
          TimelineClip(path: '/a.mp4', type: MediaType.video),
        ]);

        const track = AudioTrack(
          path: '/music/bg.mp3',
          offset: Duration(seconds: 1),
          volume: 0.8,
        );
        await player.setAudioTrack(track);

        expect(fakePlatform.calls, contains('setAudioTrack'));
        expect(fakePlatform.lastTextureId, 42);
        expect(fakePlatform.lastAudioTrackPayload?['path'], '/music/bg.mp3');
        expect(fakePlatform.lastAudioTrackPayload?['offsetMs'], 1000);
        expect(fakePlatform.lastAudioTrackPayload?['volume'], 0.8);
      },
    );
  });

  group('removeAudioTrack', () {
    test('throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(() => player.removeAudioTrack(), throwsStateError);
    });

    test('calls platform.removeAudioTrack with textureId after load', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      await player.load(const [
        TimelineClip(path: '/a.mp4', type: MediaType.video),
      ]);

      await player.removeAudioTrack();

      expect(fakePlatform.calls, contains('removeAudioTrack'));
      expect(fakePlatform.lastTextureId, 42);
    });
  });

  // ── Text overlays ────────────────────────────────────────────────────────

  const sampleOverlay = TimelineTextOverlay(
    id: 'text-1',
    text: 'Hello',
    start: Duration(milliseconds: 500),
    end: Duration(seconds: 3),
    x: 0.25,
    y: 0.75,
    fontSize: 0.08,
  );

  group('addTextOverlay', () {
    test('throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(() => player.addTextOverlay(sampleOverlay), throwsStateError);
    });

    test(
      'calls platform.addTextOverlay with textureId and serialized overlay after load',
      () async {
        final player = NativeTimelinePlayer(platform: fakePlatform);
        await player.load(const [
          TimelineClip(path: '/a.mp4', type: MediaType.video),
        ]);

        await player.addTextOverlay(sampleOverlay);

        expect(fakePlatform.calls, contains('addTextOverlay'));
        expect(fakePlatform.lastTextureId, 42);
        expect(fakePlatform.lastTextOverlayPayload?['id'], 'text-1');
        expect(fakePlatform.lastTextOverlayPayload?['text'], 'Hello');
        expect(fakePlatform.lastTextOverlayPayload?['startMs'], 500);
        expect(fakePlatform.lastTextOverlayPayload?['endMs'], 3000);
        expect(fakePlatform.lastTextOverlayPayload?['x'], 0.25);
        expect(fakePlatform.lastTextOverlayPayload?['y'], 0.75);
      },
    );
  });

  group('updateTextOverlay', () {
    test('throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(() => player.updateTextOverlay(sampleOverlay), throwsStateError);
    });

    test(
      'calls platform.updateTextOverlay with textureId and serialized overlay after load',
      () async {
        final player = NativeTimelinePlayer(platform: fakePlatform);
        await player.load(const [
          TimelineClip(path: '/a.mp4', type: MediaType.video),
        ]);

        await player.updateTextOverlay(sampleOverlay);

        expect(fakePlatform.calls, contains('updateTextOverlay'));
        expect(fakePlatform.lastTextureId, 42);
        expect(fakePlatform.lastTextOverlayPayload?['id'], 'text-1');
        expect(fakePlatform.lastTextOverlayPayload?['text'], 'Hello');
      },
    );
  });

  // ── Video layers ─────────────────────────────────────────────────────────

  const sampleLayer = TimelineVideoLayer(
    id: 'layer-1',
    path: '/layer.mp4',
    start: Duration(milliseconds: 1500),
  );

  group('video layers', () {
    test('add/update/remove throw StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(() => player.addVideoLayer(sampleLayer), throwsStateError);
      expect(() => player.updateVideoLayer(sampleLayer), throwsStateError);
      expect(() => player.removeVideoLayer('layer-1'), throwsStateError);
    });

    test(
      'addVideoLayer sends payload and returns the resolved layer',
      () async {
        final player = NativeTimelinePlayer(platform: fakePlatform);
        await player.load(const [
          TimelineClip(path: '/a.mp4', type: MediaType.video),
        ]);

        final resolved = await player.addVideoLayer(sampleLayer);

        expect(fakePlatform.lastTextureId, 42);
        expect(fakePlatform.lastVideoLayerPayload, <String, dynamic>{
          'id': 'layer-1',
          'path': '/layer.mp4',
          'startMs': 1500,
          'trimStartMs': 0,
          'x': 0.5,
          'y': 0.5,
          'widthFraction': 0.5,
          'opacity': 1.0,
        });
        expect(resolved.trimEnd, const Duration(seconds: 5));
        expect(resolved.sourceWidth, 1080);
        expect(resolved.sourceHeight, 1920);
      },
    );

    test('native video_layer_limit error propagates', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      await player.load(const [
        TimelineClip(path: '/a.mp4', type: MediaType.video),
      ]);
      fakePlatform.addVideoLayerError = PlatformException(
        code: 'video_layer_limit',
      );

      await expectLater(
        player.addVideoLayer(sampleLayer),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'video_layer_limit',
          ),
        ),
      );
    });

    test('update and remove delegate with the texture id', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      await player.load(const [
        TimelineClip(path: '/a.mp4', type: MediaType.video),
      ]);

      await player.updateVideoLayer(sampleLayer.copyWith(x: 0.2));
      expect(fakePlatform.calls, contains('updateVideoLayer'));
      expect(fakePlatform.lastVideoLayerPayload?['x'], 0.2);

      await player.removeVideoLayer('layer-1');
      expect(fakePlatform.lastRemovedVideoLayerId, 'layer-1');
    });
  });

  group('removeTextOverlay', () {
    test('throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(() => player.removeTextOverlay('text-1'), throwsStateError);
    });

    test(
      'calls platform.removeTextOverlay with textureId and overlay id after load',
      () async {
        final player = NativeTimelinePlayer(platform: fakePlatform);
        await player.load(const [
          TimelineClip(path: '/a.mp4', type: MediaType.video),
        ]);

        await player.removeTextOverlay('text-1');

        expect(fakePlatform.calls, contains('removeTextOverlay'));
        expect(fakePlatform.lastTextureId, 42);
        expect(fakePlatform.lastRemovedTextOverlayId, 'text-1');
      },
    );
  });

  // ── Captions ─────────────────────────────────────────────────────────────

  final sampleCue = TimelineCaptionCue(
    text: 'Olá mundo',
    start: const Duration(milliseconds: 500),
    end: const Duration(seconds: 3),
    words: [
      TimelineCaptionWord(
        text: 'Olá',
        start: const Duration(milliseconds: 500),
        end: const Duration(milliseconds: 900),
      ),
    ],
  );

  group('setCaptions', () {
    test('throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(
        () => player.setCaptions([sampleCue], const TimelineCaptionStyle()),
        throwsStateError,
      );
    });

    test(
      'calls platform.setCaptions with textureId, serialized cues and style after load',
      () async {
        final player = NativeTimelinePlayer(platform: fakePlatform);
        await player.load(const [
          TimelineClip(path: '/a.mp4', type: MediaType.video),
        ]);

        await player.setCaptions(
          [sampleCue],
          const TimelineCaptionStyle(
            positionY: 0.9,
            karaoke: true,
            backgroundOpacity: 0.5,
          ),
        );

        expect(fakePlatform.calls, contains('setCaptions'));
        expect(fakePlatform.lastTextureId, 42);
        expect(fakePlatform.lastCaptionsCues, [
          {
            'text': 'Olá mundo',
            'startMs': 500,
            'endMs': 3000,
            'words': [
              {'text': 'Olá', 'startMs': 500, 'endMs': 900},
            ],
          },
        ]);
        expect(fakePlatform.lastCaptionsStyle, {
          'color': 0xFFFFFFFF,
          'fontSize': 0.055,
          'positionY': 0.9,
          'uppercase': false,
          'karaoke': true,
          'strokeWidth': 0.0,
          'backgroundOpacity': 0.5,
          'highlightColor': 0xFFFFD700,
        });
      },
    );
  });

  group('removeCaptions', () {
    test('throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(() => player.removeCaptions(), throwsStateError);
    });

    test('calls platform.removeCaptions with textureId after load', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      await player.load(const [
        TimelineClip(path: '/a.mp4', type: MediaType.video),
      ]);

      await player.removeCaptions();

      expect(fakePlatform.calls, contains('removeCaptions'));
      expect(fakePlatform.lastTextureId, 42);
    });
  });

  group('extractAudio', () {
    test('throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(
        () => player.extractAudio(outputPath: '/tmp/audio.m4a'),
        throwsStateError,
      );
    });

    test('calls platform.extractAudio and returns the output path', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      await player.load(const [
        TimelineClip(path: '/a.mp4', type: MediaType.video),
      ]);

      final path = await player.extractAudio(outputPath: '/tmp/audio.m4a');

      expect(fakePlatform.calls, contains('extractAudio'));
      expect(fakePlatform.lastTextureId, 42);
      expect(fakePlatform.lastExtractAudioOutputPath, '/tmp/audio.m4a');
      expect(path, '/tmp/audio.m4a');
    });
  });
}
