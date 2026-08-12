import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/src/models/timeline_composition_config.dart';
import 'package:video_ultra_player/src/models/timeline_player_state.dart';
import 'package:video_ultra_player/video_ultra_player_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelVideoUltraPlayer();
  const channel = MethodChannel('video_ultra_player/timeline_player');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          calls.add(methodCall);
          if (methodCall.method == 'load') {
            return 77;
          }
          if (methodCall.method == 'exportTimeline') {
            return '/tmp/final.mp4';
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('load invokes native load and returns texture id', () async {
    final textureId = await platform.load([
      <String, dynamic>{'path': '/tmp/a.mp4', 'type': 'video'},
    ]);

    expect(textureId, 77);
    expect(calls.single.method, 'load');
    expect(calls.single.arguments, {
      'clips': [
        <String, dynamic>{'path': '/tmp/a.mp4', 'type': 'video'},
      ],
      'config': {
        'aspectRatio': 'original',
        'baseWidth': 1080,
        'hdrMode': 'keepHdr',
        'preserveSourceQuality': false,
        'enablePreview': true,
      },
    });
  });

  test('load includes serialized composition config', () async {
    final textureId = await platform.load(
      [
        <String, dynamic>{'path': '/tmp/a.mp4', 'type': 'video'},
      ],
      config: TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.ratio9x16,
        baseWidth: 1080,
      ).toJson(),
    );
    expect(textureId, 77);
    expect(calls.single.arguments, {
      'clips': [
        <String, dynamic>{'path': '/tmp/a.mp4', 'type': 'video'},
      ],
      'config': {
        'aspectRatio': 'ratio9x16',
        'baseWidth': 1080,
        'hdrMode': 'keepHdr',
        'preserveSourceQuality': false,
        'enablePreview': true,
      },
    });
  });

  test('load serializes enablePreview false for headless sessions', () async {
    final textureId = await platform.load(
      [
        <String, dynamic>{'path': '/tmp/a.mp4', 'type': 'video'},
      ],
      config: TimelineCompositionConfig(enablePreview: false).toJson(),
    );

    expect(textureId, 77);
    expect(calls.single.arguments, {
      'clips': [
        <String, dynamic>{'path': '/tmp/a.mp4', 'type': 'video'},
      ],
      'config': {
        'aspectRatio': 'original',
        'baseWidth': 1080,
        'hdrMode': 'keepHdr',
        'preserveSourceQuality': false,
        'enablePreview': false,
      },
    });
  });

  test(
    'exportTimeline invokes native export and returns output path',
    () async {
      final outputPath = await platform.exportTimeline([
        <String, dynamic>{'path': '/tmp/a.mp4', 'type': 'video'},
      ], outputPath: '/tmp/final.mp4');

      expect(outputPath, '/tmp/final.mp4');
      expect(calls.single.method, 'exportTimeline');
      expect(calls.single.arguments, {
        'clips': [
          <String, dynamic>{'path': '/tmp/a.mp4', 'type': 'video'},
        ],
        'outputPath': '/tmp/final.mp4',
        'config': {
          'aspectRatio': 'original',
          'baseWidth': 1080,
          'hdrMode': 'keepHdr',
          'preserveSourceQuality': false,
          'enablePreview': true,
        },
      });
    },
  );

  test('exportTimeline includes serialized composition config', () async {
    final outputPath = await platform.exportTimeline(
      [
        <String, dynamic>{'path': '/tmp/a.mp4', 'type': 'video'},
      ],
      outputPath: '/tmp/final.mp4',
      config: TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.ratio1x1,
        baseWidth: 1200,
      ).toJson(),
    );

    expect(outputPath, '/tmp/final.mp4');
    expect(calls.single.arguments, {
      'clips': [
        <String, dynamic>{'path': '/tmp/a.mp4', 'type': 'video'},
      ],
      'outputPath': '/tmp/final.mp4',
      'config': {
        'aspectRatio': 'ratio1x1',
        'baseWidth': 1200,
        'hdrMode': 'keepHdr',
        'preserveSourceQuality': false,
        'enablePreview': true,
      },
    });
  });

  test('commands invoke native channel with arguments', () async {
    await platform.play(77);
    await platform.pause(77);
    await platform.seekTo(77, const Duration(milliseconds: 300));
    await platform.seekToClip(77, 1);
    await platform.setVolume(77, 0.25);
    await platform.setClipAlignment(77, 2, -1, 1);
    await platform.setCompositionConfig(
      77,
      TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.ratio9x16,
        baseWidth: 720,
      ).toJson(),
    );
    await platform.dispose(77);

    expect(calls.map((call) => call.method), [
      'play',
      'pause',
      'seekTo',
      'seekToClip',
      'setVolume',
      'setClipAlignment',
      'setCompositionConfig',
      'dispose',
    ]);
    expect(calls[6].arguments, {
      'textureId': 77,
      'config': {
        'aspectRatio': 'ratio9x16',
        'baseWidth': 720,
        'hdrMode': 'keepHdr',
        'preserveSourceQuality': false,
        'enablePreview': true,
      },
    });
    expect(calls[2].arguments, {'textureId': 77, 'positionMs': 300});
    expect(calls[3].arguments, {'textureId': 77, 'clipIndex': 1});
    expect(calls[4].arguments, {'textureId': 77, 'volume': 0.25});
    expect(calls[5].arguments, {
      'textureId': 77,
      'clipIndex': 2,
      'x': -1.0,
      'y': 1.0,
    });
  });

  test('TimelinePlayerState.fromMap converts milliseconds', () {
    final state = TimelinePlayerState.fromMap({
      'globalPosition': 1200,
      'clipIndex': 2,
      'localPosition': 400,
      'isPlaying': true,
      'totalDuration': 3000,
      'canUndo': true,
      'canRedo': false,
    });

    expect(state.globalPosition, const Duration(milliseconds: 1200));
    expect(state.clipIndex, 2);
    expect(state.localPosition, const Duration(milliseconds: 400));
    expect(state.isPlaying, isTrue);
    expect(state.totalDuration, const Duration(milliseconds: 3000));
    expect(state.canUndo, isTrue);
    expect(state.canRedo, isFalse);
  });

  test('TimelinePlayerState.fromMap parses clipDurationsMs', () {
    final state = TimelinePlayerState.fromMap({
      'globalPosition': 0,
      'clipIndex': 0,
      'localPosition': 0,
      'isPlaying': false,
      'totalDuration': 5000,
      'clipDurationsMs': [2000, 3000],
    });

    expect(state.clipDurations, [
      const Duration(milliseconds: 2000),
      const Duration(milliseconds: 3000),
    ]);
  });

  test('TimelinePlayerState.fromMap defaults clipDurations to empty', () {
    final state = TimelinePlayerState.fromMap({
      'globalPosition': 0,
      'clipIndex': 0,
      'localPosition': 0,
      'isPlaying': false,
      'totalDuration': 0,
    });
    expect(state.clipDurations, isEmpty);
  });

  group('editing method channel payloads', () {
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            calls.add(methodCall);
            return null;
          });
    });

    test('trimClip sends correct payload', () async {
      await platform.trimClip(77, 2, trimStartMs: 500, trimEndMs: 3000);
      expect(calls.single.method, 'trimClip');
      expect(calls.single.arguments, {
        'textureId': 77,
        'clipIndex': 2,
        'trimStartMs': 500,
        'trimEndMs': 3000,
      });
    });

    test('trimClip sends null trim bounds when not specified', () async {
      await platform.trimClip(77, 2);
      expect(calls.single.arguments, {
        'textureId': 77,
        'clipIndex': 2,
        'trimStartMs': null,
        'trimEndMs': null,
      });
    });

    test('splitClip sends correct payload', () async {
      await platform.splitClip(77, 1, 1200);
      expect(calls.single.method, 'splitClip');
      expect(calls.single.arguments, {
        'textureId': 77,
        'clipIndex': 1,
        'atLocalPositionMs': 1200,
      });
    });

    test('insertClip sends correct payload', () async {
      await platform.insertClip(77, 2, <String, dynamic>{
        'path': '/b.mp4',
        'type': 'video',
      });
      expect(calls.single.method, 'insertClip');
      expect(calls.single.arguments, {
        'textureId': 77,
        'atIndex': 2,
        'clip': {'path': '/b.mp4', 'type': 'video'},
      });
    });

    test('removeClip sends correct payload', () async {
      await platform.removeClip(77, 1);
      expect(calls.single.method, 'removeClip');
      expect(calls.single.arguments, {'textureId': 77, 'clipIndex': 1});
    });

    test('moveClip sends correct payload', () async {
      await platform.moveClip(77, 0, 2);
      expect(calls.single.method, 'moveClip');
      expect(calls.single.arguments, {
        'textureId': 77,
        'fromIndex': 0,
        'toIndex': 2,
      });
    });

    test('replaceClip sends correct payload', () async {
      await platform.replaceClip(77, 0, <String, dynamic>{
        'path': '/c.mp4',
        'type': 'video',
        'trimStartMs': 500,
      });
      expect(calls.single.method, 'replaceClip');
      expect(calls.single.arguments, {
        'textureId': 77,
        'clipIndex': 0,
        'clip': {'path': '/c.mp4', 'type': 'video', 'trimStartMs': 500},
      });
    });

    test('exportCurrentTimeline sends correct payload', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            calls.add(methodCall);
            if (methodCall.method == 'exportCurrentTimeline') {
              return '/tmp/out.mp4';
            }
            return null;
          });
      final path = await platform.exportCurrentTimeline(
        77,
        outputPath: '/tmp/out.mp4',
      );
      expect(path, '/tmp/out.mp4');
      expect(calls.single.method, 'exportCurrentTimeline');
      expect(calls.single.arguments, {
        'textureId': 77,
        'outputPath': '/tmp/out.mp4',
      });
    });

    test('setClipSpeed sends correct payload', () async {
      await platform.setClipSpeed(77, 2, 1.5);
      expect(calls.single.method, 'setClipSpeed');
      expect(calls.single.arguments, {
        'textureId': 77,
        'clipIndex': 2,
        'speed': 1.5,
      });
    });

    test('undo sends correct payload', () async {
      await platform.undo(77);
      expect(calls.single.method, 'undo');
      expect(calls.single.arguments, {'textureId': 77});
    });

    test('redo sends correct payload', () async {
      await platform.redo(77);
      expect(calls.single.method, 'redo');
      expect(calls.single.arguments, {'textureId': 77});
    });

    test('generateThumbnails sends correct payload', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            calls.add(methodCall);
            if (methodCall.method == 'generateThumbnails') {
              return <String>['/tmp/t0.jpg', '/tmp/t1000.jpg'];
            }
            return null;
          });

      final paths = await platform.generateThumbnails('/path/video.mp4', [
        0,
        1000,
      ], width: 120);

      expect(calls.single.method, 'generateThumbnails');
      expect(calls.single.arguments, {
        'videoPath': '/path/video.mp4',
        'timestampsMs': [0, 1000],
        'width': 120,
      });
      expect(paths, ['/tmp/t0.jpg', '/tmp/t1000.jpg']);
    });

    test('setAudioTrack sends correct payload', () async {
      await platform.setAudioTrack(77, <String, dynamic>{
        'path': '/music/bg.mp3',
        'offsetMs': 1000,
        'volume': 0.8,
      });
      expect(calls.single.method, 'setAudioTrack');
      expect(calls.single.arguments, {
        'textureId': 77,
        'track': {'path': '/music/bg.mp3', 'offsetMs': 1000, 'volume': 0.8},
      });
    });

    test('removeAudioTrack sends correct payload', () async {
      await platform.removeAudioTrack(77);
      expect(calls.single.method, 'removeAudioTrack');
      expect(calls.single.arguments, {'textureId': 77});
    });

    test('addTextOverlay sends correct payload', () async {
      await platform.addTextOverlay(77, <String, dynamic>{
        'id': 'text-1',
        'text': 'Hello',
        'startMs': 500,
        'endMs': 3000,
        'x': 0.25,
        'y': 0.75,
        'rotationDegrees': 0,
        'fontSize': 0.08,
        'color': 0xFFFFFFFF,
        'backgroundColor': 0x00000000,
        'opacity': 1.0,
        'textAlign': 'center',
      });
      expect(calls.single.method, 'addTextOverlay');
      expect(calls.single.arguments, {
        'textureId': 77,
        'overlay': {
          'id': 'text-1',
          'text': 'Hello',
          'startMs': 500,
          'endMs': 3000,
          'x': 0.25,
          'y': 0.75,
          'rotationDegrees': 0,
          'fontSize': 0.08,
          'color': 0xFFFFFFFF,
          'backgroundColor': 0x00000000,
          'opacity': 1.0,
          'textAlign': 'center',
        },
      });
    });

    test('updateTextOverlay sends correct payload', () async {
      await platform.updateTextOverlay(77, <String, dynamic>{
        'id': 'text-1',
        'text': 'Hello',
        'startMs': 500,
        'endMs': 3000,
        'x': 0.25,
        'y': 0.75,
        'rotationDegrees': 0,
        'fontSize': 0.08,
        'color': 0xFFFFFFFF,
        'backgroundColor': 0x00000000,
        'opacity': 1.0,
        'textAlign': 'center',
      });
      expect(calls.single.method, 'updateTextOverlay');
      expect(calls.single.arguments, {
        'textureId': 77,
        'overlay': {
          'id': 'text-1',
          'text': 'Hello',
          'startMs': 500,
          'endMs': 3000,
          'x': 0.25,
          'y': 0.75,
          'rotationDegrees': 0,
          'fontSize': 0.08,
          'color': 0xFFFFFFFF,
          'backgroundColor': 0x00000000,
          'opacity': 1.0,
          'textAlign': 'center',
        },
      });
    });

    test('removeTextOverlay sends correct payload', () async {
      await platform.removeTextOverlay(77, 'text-1');
      expect(calls.single.method, 'removeTextOverlay');
      expect(calls.single.arguments, {'textureId': 77, 'overlayId': 'text-1'});
    });
  });
}
