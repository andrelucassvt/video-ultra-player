import 'package:video_ultra_player/src/models/timeline_composition_config.dart';
import 'package:video_ultra_player/src/models/timeline_export_progress.dart';
import 'package:video_ultra_player/src/models/timeline_clip.dart';
import 'package:video_ultra_player/src/models/timeline_player_state.dart';
import 'package:video_ultra_player/video_ultra_player_platform_interface.dart';

class NativeTimelinePlayer {
  NativeTimelinePlayer({VideoUltraPlayerPlatform? platform})
    : _platform = platform ?? VideoUltraPlayerPlatform.instance;

  final VideoUltraPlayerPlatform _platform;
  int? _textureId;
  Stream<TimelinePlayerState>? _stateStream;
  Stream<TimelineExportProgress>? _exportProgressStream;
  bool _exporting = false;

  int? get textureId => _textureId;

  bool get isLoaded => _textureId != null;

  Stream<TimelinePlayerState> get stateStream {
    final textureId = _requireTextureId();
    return _stateStream ??= _platform
        .stateStream(textureId)
        .asBroadcastStream();
  }

  Stream<TimelineExportProgress> get exportProgress {
    if (!_exporting) {
      throw StateError(
        'NativeTimelinePlayer.exportTimeline must be in progress before this call.',
      );
    }
    return _exportProgressStream ??= _platform
        .exportProgress()
        .asBroadcastStream();
  }

  Future<int> load(
    List<TimelineClip> clips, {
    TimelineCompositionConfig? config,
  }) async {
    if (clips.isEmpty) {
      throw ArgumentError.value(
        clips,
        'clips',
        'Must contain at least one clip.',
      );
    }

    final textureId = await _platform.load(
      clips.map((clip) => clip.toJson()).toList(growable: false),
      config: (config ?? TimelineCompositionConfig()).toJson(),
    );
    _textureId = textureId;
    _stateStream = null;
    return textureId;
  }

  Future<String> exportTimeline(
    List<TimelineClip> clips, {
    String? outputPath,
    TimelineCompositionConfig? config,
  }) async {
    if (clips.isEmpty) {
      throw ArgumentError.value(
        clips,
        'clips',
        'Must contain at least one clip.',
      );
    }

    if (_exporting) {
      throw StateError('Only one timeline export can run at a time.');
    }

    _exporting = true;
    _exportProgressStream = null;
    try {
      return await _platform.exportTimeline(
        clips.map((clip) => clip.toJson()).toList(growable: false),
        outputPath: outputPath,
        config: (config ?? TimelineCompositionConfig()).toJson(),
      );
    } finally {
      _exporting = false;
    }
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
