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
  int? lastTextureId;
  Duration? lastSeekPosition;
  double? lastVolume;
  int? lastClipIndex;
  double? lastAlignmentX;
  double? lastAlignmentY;
  final stateController = StreamController<TimelinePlayerState>.broadcast();

  @override
  Future<int> load(List<Map<String, dynamic>> clips) async {
    calls.add('load');
    loadedClips = clips;
    return 42;
  }

  @override
  Future<String> exportTimeline(
    List<Map<String, dynamic>> clips, {
    String? outputPath,
  }) async {
    calls.add('exportTimeline');
    loadedClips = clips;
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
      },
    ]);
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
        },
      ]);
    },
  );

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
    await player.setVolume(0.7);
    await player.setClipAlignment(1, -0.25, 0.5);
    await player.dispose();

    expect(fakePlatform.calls, [
      'load',
      'play',
      'pause',
      'seekTo',
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

  test('commands before load throw StateError', () {
    final player = NativeTimelinePlayer();

    expect(() => player.play(), throwsStateError);
    expect(() => player.stateStream, throwsStateError);
  });
}
