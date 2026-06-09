import 'package:video_ultra_player/src/models/timeline_clip.dart';
import 'package:video_ultra_player/src/models/timeline_player_state.dart';
import 'package:video_ultra_player/video_ultra_player_platform_interface.dart';

class NativeTimelinePlayer {
  NativeTimelinePlayer({VideoUltraPlayerPlatform? platform})
    : _platform = platform ?? VideoUltraPlayerPlatform.instance;

  final VideoUltraPlayerPlatform _platform;
  int? _textureId;
  Stream<TimelinePlayerState>? _stateStream;

  int? get textureId => _textureId;

  bool get isLoaded => _textureId != null;

  Stream<TimelinePlayerState> get stateStream {
    final textureId = _requireTextureId();
    return _stateStream ??= _platform
        .stateStream(textureId)
        .asBroadcastStream();
  }

  Future<int> load(List<TimelineClip> clips) async {
    if (clips.isEmpty) {
      throw ArgumentError.value(
        clips,
        'clips',
        'Must contain at least one clip.',
      );
    }

    final textureId = await _platform.load(
      clips.map((clip) => clip.toJson()).toList(growable: false),
    );
    _textureId = textureId;
    _stateStream = null;
    return textureId;
  }

  Future<String> exportTimeline(
    List<TimelineClip> clips, {
    String? outputPath,
  }) {
    if (clips.isEmpty) {
      throw ArgumentError.value(
        clips,
        'clips',
        'Must contain at least one clip.',
      );
    }

    return _platform.exportTimeline(
      clips.map((clip) => clip.toJson()).toList(growable: false),
      outputPath: outputPath,
    );
  }

  Future<void> play() {
    return _platform.play(_requireTextureId());
  }

  Future<void> pause() {
    return _platform.pause(_requireTextureId());
  }

  Future<void> seekTo(Duration position) {
    return _platform.seekTo(_requireTextureId(), position);
  }

  Future<void> setVolume(double volume) {
    if (volume < 0 || volume > 1) {
      throw RangeError.range(volume, 0, 1, 'volume');
    }
    return _platform.setVolume(_requireTextureId(), volume);
  }

  Future<void> setClipAlignment(int clipIndex, double x, double y) {
    return _platform.setClipAlignment(_requireTextureId(), clipIndex, x, y);
  }

  Future<void> dispose() async {
    final textureId = _textureId;
    if (textureId == null) {
      return;
    }
    _textureId = null;
    _stateStream = null;
    await _platform.dispose(textureId);
  }

  int _requireTextureId() {
    final textureId = _textureId;
    if (textureId == null) {
      throw StateError(
        'NativeTimelinePlayer.load must complete before this call.',
      );
    }
    return textureId;
  }
}
