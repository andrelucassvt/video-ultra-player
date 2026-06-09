import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_ultra_player/src/models/timeline_player_state.dart';
import 'package:video_ultra_player/video_ultra_player_platform_interface.dart';

class MethodChannelVideoUltraPlayer extends VideoUltraPlayerPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel(
    'video_ultra_player/timeline_player',
  );

  @visibleForTesting
  final eventChannel = const EventChannel(
    'video_ultra_player/timeline_player/events',
  );

  @override
  Future<int> load(List<Map<String, dynamic>> clips) async {
    final textureId = await methodChannel.invokeMethod<int>(
      'load',
      <String, Object?>{'clips': clips},
    );
    if (textureId == null) {
      throw StateError('Native timeline load did not return a texture id.');
    }
    return textureId;
  }

  @override
  Future<String> exportTimeline(
    List<Map<String, dynamic>> clips, {
    String? outputPath,
  }) async {
    final exportedPath = await methodChannel.invokeMethod<String>(
      'exportTimeline',
      <String, Object?>{'clips': clips, 'outputPath': outputPath},
    );
    if (exportedPath == null) {
      throw StateError('Native timeline export did not return an output path.');
    }
    return exportedPath;
  }

  @override
  Future<void> play(int textureId) {
    return methodChannel.invokeMethod<void>('play', _textureArgs(textureId));
  }

  @override
  Future<void> pause(int textureId) {
    return methodChannel.invokeMethod<void>('pause', _textureArgs(textureId));
  }

  @override
  Future<void> seekTo(int textureId, Duration position) {
    return methodChannel.invokeMethod<void>('seekTo', <String, Object?>{
      'textureId': textureId,
      'positionMs': position.inMilliseconds,
    });
  }

  @override
  Future<void> setVolume(int textureId, double volume) {
    return methodChannel.invokeMethod<void>('setVolume', <String, Object?>{
      'textureId': textureId,
      'volume': volume,
    });
  }

  @override
  Future<void> setClipAlignment(
    int textureId,
    int clipIndex,
    double x,
    double y,
  ) {
    return methodChannel.invokeMethod<void>(
      'setClipAlignment',
      <String, Object?>{
        'textureId': textureId,
        'clipIndex': clipIndex,
        'x': x,
        'y': y,
      },
    );
  }

  @override
  Future<void> dispose(int textureId) {
    return methodChannel.invokeMethod<void>('dispose', _textureArgs(textureId));
  }

  @override
  Stream<TimelinePlayerState> stateStream(int textureId) {
    return eventChannel
        .receiveBroadcastStream(_textureArgs(textureId))
        .map(
          (event) =>
              TimelinePlayerState.fromMap(event as Map<dynamic, dynamic>),
        );
  }

  Map<String, Object?> _textureArgs(int textureId) {
    return <String, Object?>{'textureId': textureId};
  }
}
