import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:video_ultra_player/src/models/timeline_export_progress.dart';
import 'package:video_ultra_player/src/models/timeline_player_state.dart';
import 'package:video_ultra_player/video_ultra_player_method_channel.dart';

abstract class VideoUltraPlayerPlatform extends PlatformInterface {
  VideoUltraPlayerPlatform() : super(token: _token);

  static final Object _token = Object();

  static VideoUltraPlayerPlatform _instance = MethodChannelVideoUltraPlayer();

  static VideoUltraPlayerPlatform get instance => _instance;

  static set instance(VideoUltraPlayerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<int> load(
    List<Map<String, dynamic>> clips, {
    Map<String, dynamic>? config,
  }) {
    throw UnimplementedError('load() has not been implemented.');
  }

  Future<String> exportTimeline(
    List<Map<String, dynamic>> clips, {
    String? outputPath,
    Map<String, dynamic>? config,
  }) {
    throw UnimplementedError('exportTimeline() has not been implemented.');
  }

  Future<void> play(int textureId) {
    throw UnimplementedError('play() has not been implemented.');
  }

  Future<void> pause(int textureId) {
    throw UnimplementedError('pause() has not been implemented.');
  }

  Future<void> seekTo(int textureId, Duration position) {
    throw UnimplementedError('seekTo() has not been implemented.');
  }

  Future<void> seekToClip(int textureId, int clipIndex) {
    throw UnimplementedError('seekToClip() has not been implemented.');
  }

  Future<void> setVolume(int textureId, double volume) {
    throw UnimplementedError('setVolume() has not been implemented.');
  }

  Future<void> setClipAlignment(
    int textureId,
    int clipIndex,
    double x,
    double y,
  ) {
    throw UnimplementedError('setClipAlignment() has not been implemented.');
  }

  Future<void> dispose(int textureId) {
    throw UnimplementedError('dispose() has not been implemented.');
  }

  Stream<TimelinePlayerState> stateStream(int textureId) {
    throw UnimplementedError('stateStream() has not been implemented.');
  }

  Stream<TimelineExportProgress> exportProgress() {
    throw UnimplementedError('exportProgress() has not been implemented.');
  }
}
