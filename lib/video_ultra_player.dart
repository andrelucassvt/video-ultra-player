/// A Flutter plugin for gapless native timeline playback and export.
///
/// Use [NativeTimelinePlayer] to load, play, seek, and export a sequence of
/// [TimelineClip]s using platform-native composition (AVFoundation on iOS,
/// Media3 on Android).
///
/// ```dart
/// final player = NativeTimelinePlayer();
/// await player.load([
///   TimelineClip(path: '/path/to/video.mp4', type: MediaType.video),
/// ]);
/// await player.play();
/// ```
library;

export 'package:video_ultra_player/src/models/audio_track.dart';
export 'package:video_ultra_player/src/models/clip_thumbnail.dart';
export 'package:video_ultra_player/src/models/clip_transition.dart';
export 'package:video_ultra_player/src/models/edit_history_state.dart';
export 'package:video_ultra_player/src/models/timeline_clip.dart';
export 'package:video_ultra_player/src/models/timeline_composition_config.dart';
export 'package:video_ultra_player/src/models/timeline_export_progress.dart';
export 'package:video_ultra_player/src/models/timeline_player_state.dart';
export 'package:video_ultra_player/src/models/timeline_text_overlay.dart';
export 'package:video_ultra_player/src/native_timeline_player.dart';
