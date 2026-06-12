import 'dart:async';

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
    return timestampsMs
        .map((ts) => '/tmp/thumb_${ts}_$width.jpg')
        .toList();
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
    });
  });

  test('load forwards serialized composition config', () async {
    final player = NativeTimelinePlayer();

    await player.load(
      const [TimelineClip(path: '/tmp/a.mp4', type: MediaType.video)],
      config: TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.ratio16x9,
        baseWidth: 1920,
      ),
    );

    expect(fakePlatform.lastConfig, {
      'aspectRatio': 'ratio16x9',
      'baseWidth': 1920,
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
      await player.load(
        const [TimelineClip(path: '/a.mp4', type: MediaType.video)],
      );
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
      expect(
        () => player.splitClip(0, Duration.zero),
        throwsArgumentError,
      );
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

    test('exportCurrentTimeline delegates with textureId and outputPath', () async {
      final path = await player.exportCurrentTimeline(outputPath: '/tmp/out.mp4');
      expect(path, '/tmp/out.mp4');
      expect(fakePlatform.calls, contains('exportCurrentTimeline'));
      expect(fakePlatform.lastTextureId, 42);
    });

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
      await player.load(
        const [TimelineClip(path: '/a.mp4', type: MediaType.video)],
      );
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

  group('generateThumbnails', () {
    test(
        'delegates to platform with converted milliseconds and default width',
        () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);

      final paths = await player.generateThumbnails(
        '/path/video.mp4',
        [Duration.zero, const Duration(seconds: 1)],
      );

      expect(fakePlatform.calls, contains('generateThumbnails'));
      expect(fakePlatform.lastGenerateThumbnailsPath, '/path/video.mp4');
      expect(fakePlatform.lastGenerateThumbnailsTimestampsMs, [0, 1000]);
      expect(fakePlatform.lastGenerateThumbnailsWidth, 120);
      expect(paths, ['/tmp/thumb_0_120.jpg', '/tmp/thumb_1000_120.jpg']);
    });

    test('forwards custom width to platform', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);

      await player.generateThumbnails(
        '/path/video.mp4',
        [const Duration(milliseconds: 500)],
        width: 240,
      );

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

    test('calls platform.setAudioTrack with textureId and serialized track after load', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      await player.load(
        const [TimelineClip(path: '/a.mp4', type: MediaType.video)],
      );

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
    });
  });

  group('removeAudioTrack', () {
    test('throws StateError before load', () {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      expect(() => player.removeAudioTrack(), throwsStateError);
    });

    test('calls platform.removeAudioTrack with textureId after load', () async {
      final player = NativeTimelinePlayer(platform: fakePlatform);
      await player.load(
        const [TimelineClip(path: '/a.mp4', type: MediaType.video)],
      );

      await player.removeAudioTrack();

      expect(fakePlatform.calls, contains('removeAudioTrack'));
      expect(fakePlatform.lastTextureId, 42);
    });
  });
}
