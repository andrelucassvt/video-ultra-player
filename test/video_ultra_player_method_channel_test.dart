import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
      });
    },
  );

  test('commands invoke native channel with arguments', () async {
    await platform.play(77);
    await platform.pause(77);
    await platform.seekTo(77, const Duration(milliseconds: 300));
    await platform.setVolume(77, 0.25);
    await platform.setClipAlignment(77, 2, -1, 1);
    await platform.dispose(77);

    expect(calls.map((call) => call.method), [
      'play',
      'pause',
      'seekTo',
      'setVolume',
      'setClipAlignment',
      'dispose',
    ]);
    expect(calls[2].arguments, {'textureId': 77, 'positionMs': 300});
    expect(calls[3].arguments, {'textureId': 77, 'volume': 0.25});
    expect(calls[4].arguments, {
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
    });

    expect(state.globalPosition, const Duration(milliseconds: 1200));
    expect(state.clipIndex, 2);
    expect(state.localPosition, const Duration(milliseconds: 400));
    expect(state.isPlaying, isTrue);
    expect(state.totalDuration, const Duration(milliseconds: 3000));
  });
}
