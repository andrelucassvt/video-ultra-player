import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

class EditorController extends ChangeNotifier {
  EditorController({NativeTimelinePlayer? player, ImagePicker? picker})
    : _player = player ?? NativeTimelinePlayer(),
      _picker = picker ?? ImagePicker();

  final NativeTimelinePlayer _player;
  final ImagePicker _picker;

  Stream<TimelinePlayerState>? _stateStream;
  Stream<TimelineExportProgress>? _exportProgressStream;
  final Map<String, Future<List<String>>> _thumbnailRequests =
      <String, Future<List<String>>>{};
  List<TimelineClip> _clips = <TimelineClip>[];
  AudioTrack? _audioTrack;
  int? _textureId;
  int _selectedClipIndex = 0;
  final String _title = 'Meu vídeo';
  String _timelineSource = 'Sample timeline';
  bool _loading = false;
  bool _exporting = false;
  bool _isPicking = false;
  final bool _editBusy = false;
  String? _error;
  String? _exportPath;
  String? _exportMessage;
  OutputAspectRatio _aspectRatio = OutputAspectRatio.ratio9x16;
  int _baseWidth = 1080;
  double _pixelsPerSecond = 72;
  Timer? _seekThrottleTimer;
  Duration? _queuedSeekPosition;
  final List<_EditorSnapshot> _undoSnapshots = <_EditorSnapshot>[];
  final List<_EditorSnapshot> _redoSnapshots = <_EditorSnapshot>[];
  bool _disposed = false;

  Stream<TimelinePlayerState>? get stateStream => _stateStream;
  Stream<TimelineExportProgress>? get exportProgressStream =>
      _exportProgressStream;
  List<TimelineClip> get clips => List.unmodifiable(_clips);
  AudioTrack? get audioTrack => _audioTrack;
  int? get textureId => _textureId;
  int get selectedClipIndex => _selectedClipIndex;
  String get title => _title;
  String get timelineSource => _timelineSource;
  bool get loading => _loading;
  bool get exporting => _exporting;
  bool get editBusy => _editBusy;
  String? get error => _error;
  String? get exportPath => _exportPath;
  String? get exportMessage => _exportMessage;
  OutputAspectRatio get aspectRatio => _aspectRatio;
  int get baseWidth => _baseWidth;
  String get resolutionLabel => '${_baseWidth}p';
  bool get hasTimeline => _textureId != null;
  double get pixelsPerSecond => _pixelsPerSecond;
  double get minPixelsPerSecond => 44;
  double get maxPixelsPerSecond => 132;
  String? get audioTrackName => _audioTrack?.path.split(RegExp(r'[/\\]')).last;
  bool get hasSelectedClip =>
      _selectedClipIndex >= 0 && _selectedClipIndex < _clips.length;
  double get selectedClipSpeed =>
      hasSelectedClip ? _clips[_selectedClipIndex].speed : 1.0;
  bool get canUndo => _undoSnapshots.isNotEmpty;
  bool get canRedo => _redoSnapshots.isNotEmpty;

  TimelineCompositionConfig get compositionConfig {
    return TimelineCompositionConfig(
      aspectRatio: _aspectRatio,
      baseWidth: _baseWidth,
    );
  }

  double? get previewAspectRatio {
    return switch (_aspectRatio) {
      OutputAspectRatio.ratio16x9 => 16 / 9,
      OutputAspectRatio.ratio9x16 => 9 / 16,
      OutputAspectRatio.ratio1x1 => 1,
      OutputAspectRatio.original => null,
    };
  }

  Future<void> loadSample() async {
    if (_loading) return;
    _setBusy(loading: true);

    try {
      final clipAPath = await _copyAssetToTempFile('assets/clip_a.mp4');
      final stillPath = await _copyAssetToTempFile('assets/still.png');
      final clipBPath = await _copyAssetToTempFile('assets/clip_b.mp4');
      await replaceTimeline([
        TimelineClip(
          path: clipAPath,
          type: MediaType.video,
          duration: const Duration(seconds: 2),
          scale: 1.05,
        ),
        TimelineClip(
          path: stillPath,
          type: MediaType.image,
          duration: const Duration(milliseconds: 1600),
          scale: 1.3,
        ),
        TimelineClip(
          path: clipBPath,
          type: MediaType.video,
          duration: const Duration(seconds: 2),
        ),
      ], source: 'Sample timeline');
    } catch (error) {
      _setError(error);
      _setBusy(loading: false);
    }
  }

  Future<void> pickVideos() async {
    if (_loading) return;
    _setBusy(loading: true);

    try {
      final videos = await _picker.pickMultiVideo();
      if (videos.isEmpty) {
        _setBusy(loading: false);
        return;
      }

      await replaceTimeline(
        videos
            .map(
              (video) => TimelineClip(path: video.path, type: MediaType.video),
            )
            .toList(growable: false),
        source: 'Gallery videos',
      );
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
      _setBusy(loading: false);
    } catch (error) {
      _setError(error);
      _setBusy(loading: false);
    }
  }

  Future<void> replaceTimeline(
    List<TimelineClip> clips, {
    required String source,
    AudioTrack? audioTrack,
  }) async {
    await _player.dispose();
    final textureId = await _player.load(clips, config: compositionConfig);
    if (audioTrack != null) {
      await _player.setAudioTrack(audioTrack);
    }

    _textureId = textureId;
    _stateStream = _player.stateStream;
    _clips = List<TimelineClip>.of(clips);
    _audioTrack = audioTrack;
    _selectedClipIndex = 0;
    _timelineSource = source;
    _exportPath = null;
    _exportMessage = null;
    _exportProgressStream = null;
    _thumbnailRequests.clear();
    _undoSnapshots.clear();
    _redoSnapshots.clear();
    _error = null;
    _loading = false;
    _notify();
  }

  Future<void> reload() async {
    if (_loading || _exporting || _clips.isEmpty) return;
    _setBusy(loading: true);

    try {
      await replaceTimeline(
        _clips,
        source: _timelineSource,
        audioTrack: _audioTrack,
      );
    } catch (error) {
      _setError(error);
      _setBusy(loading: false);
    }
  }

  Future<void> export() async {
    if (_loading || _exporting || _textureId == null) return;

    _exporting = true;
    _error = null;
    _exportPath = null;
    _exportMessage = null;
    _exportProgressStream = null;
    _notify();

    try {
      final directory = Directory(
        '${Directory.systemTemp.path}/video_ultra_player_example_exports',
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final outputPath =
          '${directory.path}/timeline_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final exportFuture = _player.exportCurrentTimeline(
        outputPath: outputPath,
      );
      _exportProgressStream = _player.exportProgress;
      _notify();
      final exportedPath = await exportFuture;

      await _saveToGallery(exportedPath);

      // O temp foi removido por _saveToGallery; a galeria é a cópia visível.
      _exportPath = null;
      _exportMessage = 'Salvo na galeria';
      _exporting = false;
      _notify();
    } catch (error) {
      _setError(error);
      _exporting = false;
      _notify();
    }
  }

  Future<void> _saveToGallery(String path) async {
    final hasAccess = await Gal.requestAccess(toAlbum: false);
    if (!hasAccess) {
      throw Exception('Permissão da galeria negada');
    }

    await Gal.putVideo(path);

    // A galeria passa a ser a cópia visível; remove o arquivo temporário.
    final tempFile = File(path);
    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (error) {
        log('[EditorController] export: falha ao remover temp: $error');
      }
    }
  }

  Future<void> playOrPause(TimelinePlayerState state) async {
    if (_textureId == null) return;
    if (state.isPlaying) {
      await _player.pause();
    } else {
      final atEnd =
          state.totalDuration > Duration.zero &&
          state.globalPosition >=
              state.totalDuration - const Duration(milliseconds: 100);
      if (atEnd) await _player.seekTo(Duration.zero);
      await _player.play();
    }
  }

  Future<void> seekTo(Duration position) {
    return _player.seekTo(position);
  }

  void previewSeek(Duration position, TimelinePlayerState state) {
    if (_textureId == null) return;
    _queuedSeekPosition = clampTimelinePosition(position, state);
    if (_seekThrottleTimer?.isActive ?? false) return;
    _flushPreviewSeek();
  }

  Future<void> commitSeek(Duration position, TimelinePlayerState state) async {
    if (_textureId == null) return;
    _seekThrottleTimer?.cancel();
    _seekThrottleTimer = null;
    _queuedSeekPosition = null;
    await _player.seekTo(clampTimelinePosition(position, state));
  }

  Future<void> selectClip(int index) async {
    if (index < 0 || index >= _clips.length) return;
    _selectedClipIndex = index;
    _notify();
    if (_textureId != null) {
      await _player.seekToClip(index);
    }
  }

  void setPixelsPerSecond(double value) {
    final next = value.clamp(minPixelsPerSecond, maxPixelsPerSecond).toDouble();
    if (_pixelsPerSecond == next) return;
    _pixelsPerSecond = next;
    _notify();
  }

  Future<void> setAspectRatio(OutputAspectRatio aspectRatio) async {
    if (_aspectRatio == aspectRatio) return;
    _aspectRatio = aspectRatio;
    _notify();
    await reload();
  }

  Future<void> setBaseWidth(int width) async {
    final next = width.clamp(1, 4096);
    if (_baseWidth == next) return;
    _baseWidth = next;
    _notify();
    await reload();
  }

  Future<void> setClipAlignment(int clipIndex, double x, double y) async {
    if (_textureId == null || clipIndex < 0 || clipIndex >= _clips.length) {
      return;
    }

    _clips[clipIndex] = _clips[clipIndex].copyWith(alignment: Alignment(x, y));
    await _player.setClipAlignment(clipIndex, x, y);
  }

  Future<void> moveClip(int fromIndex, int toIndex) async {
    if (_textureId == null ||
        fromIndex < 0 ||
        fromIndex >= _clips.length ||
        toIndex < 0 ||
        toIndex >= _clips.length ||
        fromIndex == toIndex) {
      return;
    }

    final snapshot = _makeSnapshot();
    final nextClips = List<TimelineClip>.of(_clips);
    final moved = nextClips.removeAt(fromIndex);
    nextClips.insert(toIndex, moved);

    try {
      await _player.moveClip(fromIndex, toIndex);
      _pushSnapshot(snapshot);
      _clips = nextClips;
      _selectedClipIndex = toIndex;
      _thumbnailRequests.clear();
      _notify();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> trimClip(
    int clipIndex, {
    required Duration trimStart,
    required Duration trimEnd,
  }) async {
    if (_textureId == null ||
        clipIndex < 0 ||
        clipIndex >= _clips.length ||
        trimEnd <= trimStart) {
      return;
    }

    final clip = _clips[clipIndex];
    if (clip.type == MediaType.image) return;
    final snapshot = _makeSnapshot();

    try {
      await _player.trimClip(clipIndex, trimStart: trimStart, trimEnd: trimEnd);
      _pushSnapshot(snapshot);
      _clips[clipIndex] = clip.copyWith(trimStart: trimStart, trimEnd: trimEnd);
      _thumbnailRequests.clear();
      _notify();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> split(TimelinePlayerState state) async {
    final clipIndex = state.clipIndex;
    if (_textureId == null ||
        clipIndex < 0 ||
        clipIndex >= _clips.length ||
        state.localPosition <= Duration.zero) {
      return;
    }

    final duration = clipDuration(clipIndex, state);
    if (state.localPosition >= duration) return;

    final snapshot = _makeSnapshot();
    try {
      await _player.splitClip(clipIndex, state.localPosition);
      _pushSnapshot(snapshot);
      _splitLocalClip(clipIndex, state.localPosition, duration);
      _selectedClipIndex = clipIndex + 1;
      _thumbnailRequests.clear();
      _notify();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> removeSelected() async {
    if (_textureId == null || _clips.length <= 1 || !hasSelectedClip) return;

    final clipIndex = _selectedClipIndex;
    final snapshot = _makeSnapshot();
    try {
      await _player.removeClip(clipIndex);
      _pushSnapshot(snapshot);
      _clips.removeAt(clipIndex);
      _selectedClipIndex = clipIndex.clamp(0, _clips.length - 1).toInt();
      _thumbnailRequests.clear();
      _notify();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> setSelectedClipSpeed(double speed) async {
    if (_textureId == null || !hasSelectedClip) return;
    final nextSpeed = speed.clamp(0.5, 2.0).toDouble();
    final clipIndex = _selectedClipIndex;
    final clip = _clips[clipIndex];
    if (clip.speed == nextSpeed) return;

    final snapshot = _makeSnapshot();
    try {
      await _player.setClipSpeed(clipIndex, nextSpeed);
      _pushSnapshot(snapshot);
      _clips[clipIndex] = clip.copyWith(speed: nextSpeed);
      _thumbnailRequests.clear();
      _notify();
    } catch (error) {
      _setError(error);
    }
  }

  Future<List<String>> thumbnailPathsForClip(
    int clipIndex,
    Duration duration, {
    required int width,
  }) {
    if (clipIndex < 0 || clipIndex >= _clips.length) {
      return Future<List<String>>.value(<String>[]);
    }

    final clip = _clips[clipIndex];
    if (clip.type != MediaType.video) {
      return Future<List<String>>.value(<String>[]);
    }

    final timestamps = _thumbnailTimestamps(duration);
    if (timestamps.isEmpty) {
      return Future<List<String>>.value(<String>[]);
    }

    final key =
        '${clip.path}|$width|'
        '${timestamps.map((timestamp) => timestamp.inMilliseconds).join(",")}';
    return _thumbnailRequests.putIfAbsent(key, () async {
      try {
        return await _player.generateThumbnails(
          clip.path,
          timestamps,
          width: width,
        );
      } catch (error) {
        _setError(error);
        return <String>[];
      }
    });
  }

  Future<void> addAudioTrack() async {
    if (_textureId == null || _loading || _isPicking) return;

    log('[EditorController] addAudioTrack: opening picker');
    _isPicking = true;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'aac', 'm4a', 'wav', 'flac', 'ogg', 'opus'],
        allowMultiple: false,
      );
      log(
        '[EditorController] addAudioTrack: result=${result?.files.single.path}',
      );
      final path = result?.files.single.path;
      if (path == null) return;
      await setAudioTrack(AudioTrack(path: path, volume: 0.8));
    } on PlatformException catch (error) {
      log(
        '[EditorController] addAudioTrack: PlatformException code=${error.code} message=${error.message}',
      );
      if (error.code == 'multiple_request') return;
      _setError(error.message ?? error.code);
    } catch (error) {
      log('[EditorController] addAudioTrack: error=$error');
      _setError(error);
    } finally {
      _isPicking = false;
    }
  }

  Future<void> setAudioTrack(AudioTrack track) async {
    if (_textureId == null) return;
    final snapshot = _makeSnapshot();
    try {
      await _player.setAudioTrack(track);
      _pushSnapshot(snapshot);
      _audioTrack = track;
      _notify();
    } catch (error) {
      _setError(error);
    }
  }

  void setAudioVolumePreview(double volume) {
    final track = _audioTrack;
    if (track == null) return;
    _audioTrack = track.copyWith(volume: volume.clamp(0.0, 1.0).toDouble());
    _notify();
  }

  Future<void> commitAudioVolume(double volume) async {
    final track = _audioTrack;
    if (track == null) return;
    await setAudioTrack(
      track.copyWith(volume: volume.clamp(0.0, 1.0).toDouble()),
    );
  }

  Future<void> removeAudioTrack() async {
    if (_textureId == null || _audioTrack == null) return;
    final snapshot = _makeSnapshot();
    try {
      await _player.removeAudioTrack();
      _pushSnapshot(snapshot);
      _audioTrack = null;
      _notify();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> undo() async {
    if (_textureId == null || _undoSnapshots.isEmpty) return;
    final current = _makeSnapshot();
    try {
      await _player.undo();
      _redoSnapshots.add(current);
      _restoreSnapshot(_undoSnapshots.removeLast());
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> redo() async {
    if (_textureId == null || _redoSnapshots.isEmpty) return;
    final current = _makeSnapshot();
    try {
      await _player.redo();
      _undoSnapshots.add(current);
      _restoreSnapshot(_redoSnapshots.removeLast());
    } catch (error) {
      _setError(error);
    }
  }

  List<Duration> resolvedClipDurations(TimelinePlayerState state) {
    if (state.clipDurations.length == _clips.length) {
      return List<Duration>.unmodifiable(state.clipDurations);
    }

    return List<Duration>.unmodifiable(
      _clips.map((clip) => _fallbackClipDuration(clip)),
    );
  }

  Duration clipDuration(int index, TimelinePlayerState state) {
    final durations = resolvedClipDurations(state);
    if (index < 0 || index >= durations.length) return Duration.zero;
    return durations[index];
  }

  Duration clipStart(int index, TimelinePlayerState state) {
    final durations = resolvedClipDurations(state);
    var total = Duration.zero;
    for (var i = 0; i < index && i < durations.length; i++) {
      total += durations[i];
    }
    return total;
  }

  Duration timelineDuration(TimelinePlayerState state) {
    if (state.totalDuration > Duration.zero) {
      return state.totalDuration;
    }

    return resolvedClipDurations(
      state,
    ).fold<Duration>(Duration.zero, (total, duration) => total + duration);
  }

  Duration clampTimelinePosition(Duration position, TimelinePlayerState state) {
    final totalMs = timelineDuration(state).inMilliseconds;
    if (totalMs <= 0) return Duration.zero;
    final nextMs = position.inMilliseconds.clamp(0, totalMs).toInt();
    return Duration(milliseconds: nextMs);
  }

  Future<void> reset() async {
    await loadSample();
  }

  void clearError() {
    _error = null;
    _notify();
  }

  void setPlaybackError(Object error) {
    if (_error != null) return;
    _setError(error);
  }

  void selectLiveClip(int clipIndex) {
    if (clipIndex < 0 || clipIndex == _selectedClipIndex) return;
    _selectedClipIndex = clipIndex;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _seekThrottleTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _flushPreviewSeek() {
    final position = _queuedSeekPosition;
    if (position == null || _disposed) {
      return;
    }

    _queuedSeekPosition = null;
    unawaited(_player.seekTo(position).catchError(_setError));
    _seekThrottleTimer = Timer(
      const Duration(milliseconds: 16),
      _flushPreviewSeek,
    );
  }

  List<Duration> _thumbnailTimestamps(Duration duration) {
    final durationMs = duration.inMilliseconds;
    if (durationMs <= 0) return const <Duration>[];

    final count = (durationMs / 1000).ceil().clamp(1, 5).toInt();
    return List<Duration>.generate(count, (index) {
      final timestampMs = (durationMs * (index + 0.5) / count).round();
      return Duration(milliseconds: timestampMs.clamp(0, durationMs));
    });
  }

  Duration _fallbackClipDuration(TimelineClip clip) {
    final trimStart = clip.trimStart ?? Duration.zero;
    final trimEnd = clip.trimEnd;
    if (trimEnd != null && trimEnd > trimStart) {
      final trimmed = trimEnd - trimStart;
      return Duration(
        milliseconds: (trimmed.inMilliseconds / clip.speed).round(),
      );
    }

    final duration = clip.duration ?? const Duration(seconds: 2);
    return Duration(
      milliseconds: (duration.inMilliseconds / clip.speed).round(),
    );
  }

  void _splitLocalClip(
    int clipIndex,
    Duration localPosition,
    Duration duration,
  ) {
    final clip = _clips[clipIndex];
    if (clip.type == MediaType.image) {
      _clips[clipIndex] = clip.copyWith(duration: localPosition);
      _clips.insert(
        clipIndex + 1,
        clip.copyWith(duration: duration - localPosition),
      );
      return;
    }

    final trimStart = clip.trimStart ?? Duration.zero;
    final sourceSplit =
        trimStart +
        Duration(
          milliseconds: (localPosition.inMilliseconds * clip.speed).round(),
        );
    _clips[clipIndex] = clip.copyWith(trimEnd: sourceSplit);
    _clips.insert(clipIndex + 1, clip.copyWith(trimStart: sourceSplit));
  }

  _EditorSnapshot _makeSnapshot() {
    return _EditorSnapshot(
      clips: List<TimelineClip>.of(_clips),
      audioTrack: _audioTrack,
      selectedClipIndex: _selectedClipIndex,
    );
  }

  void _pushSnapshot(_EditorSnapshot snapshot) {
    _undoSnapshots.add(snapshot);
    if (_undoSnapshots.length > 50) {
      _undoSnapshots.removeAt(0);
    }
    _redoSnapshots.clear();
  }

  void _restoreSnapshot(_EditorSnapshot snapshot) {
    _clips = List<TimelineClip>.of(snapshot.clips);
    _audioTrack = snapshot.audioTrack;
    _selectedClipIndex = snapshot.selectedClipIndex.clamp(
      0,
      _clips.isEmpty ? 0 : _clips.length - 1,
    );
    _thumbnailRequests.clear();
    _notify();
  }

  Future<String> _copyAssetToTempFile(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final directory = Directory(
      '${Directory.systemTemp.path}/video_ultra_player_example',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File('${directory.path}/${assetPath.split('/').last}');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }

  void _setBusy({required bool loading}) {
    _loading = loading;
    _error = null;
    _notify();
  }

  void _setError(Object error) {
    _error = error.toString();
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.clips,
    required this.audioTrack,
    required this.selectedClipIndex,
  });

  final List<TimelineClip> clips;
  final AudioTrack? audioTrack;
  final int selectedClipIndex;
}
