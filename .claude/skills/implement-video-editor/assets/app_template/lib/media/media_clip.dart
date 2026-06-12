import 'package:video_ultra_player/video_ultra_player.dart';

/// Default on-screen duration for a still image added to the timeline.
///
/// Images have no intrinsic duration, so the editor needs an explicit value to
/// show them; the user can still trim or split them like any other clip later.
const kDefaultImageClipDuration = Duration(seconds: 3);

const _videoExtensions = <String>{
  'mp4',
  'mov',
  'm4v',
  'avi',
  'mkv',
  'webm',
  '3gp',
  'm2ts',
  'mts',
  'mpeg',
  'mpg',
};

/// Whether [path] points at a video file, inferred from its extension.
bool isVideoPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return _videoExtensions.contains(path.substring(dot + 1).toLowerCase());
}

/// Builds a [TimelineClip] from a picked file [path].
///
/// Video vs image is inferred from the extension. Images get
/// [kDefaultImageClipDuration]; videos keep a null [TimelineClip.duration] so
/// the native compositor uses their full source duration.
TimelineClip timelineClipFromPath(String path) {
  final video = isVideoPath(path);
  return TimelineClip(
    path: path,
    type: video ? MediaType.video : MediaType.image,
    duration: video ? null : kDefaultImageClipDuration,
  );
}
