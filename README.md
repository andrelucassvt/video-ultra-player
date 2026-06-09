# video_ultra_player

A Flutter plugin for previewing and exporting a native media timeline made from
local video and image files.

`video_ultra_player` builds one native composition per timeline, renders it into
a single Flutter `Texture`, and can export the same timeline as an MP4 file. This
avoids the visible flash or gap that often appears when switching between
multiple Flutter video players at clip boundaries.

## Features

- Gapless native timeline preview in one Flutter `Texture`.
- MP4 export for the same list of timeline clips.
- Video and image clips in the same timeline.
- Playback controls: play, pause, seek, volume, and dispose.
- Timeline state stream with global position, local clip position, clip index,
  playing state, and total duration.
- Per-clip pan/crop with normalized alignment values.
- iOS implementation backed by AVFoundation.
- Android implementation backed by AndroidX Media3.

## Platform support

| Platform | Preview | Export | Native implementation |
| --- | --- | --- | --- |
| iOS | Yes | Yes | AVFoundation, FlutterTexture, AVAssetExportSession |
| Android | Yes | Yes | Media3 CompositionPlayer, Transformer, SurfaceTexture |
| Web | No | No | Not implemented |
| macOS / Windows / Linux | No | No | Not implemented |

## Getting started

Add the package to your app:

```bash
flutter pub add video_ultra_player
```

Then import it:

```dart
import 'package:video_ultra_player/video_ultra_player.dart';
```

The plugin works with local file paths. If your media comes from assets,
downloads, a camera capture, or the photo library, copy or resolve it to a local
file path before calling `load` or `exportTimeline`.

## Basic usage

Create a player and define the timeline:

```dart
final player = NativeTimelinePlayer();

final clips = <TimelineClip>[
  const TimelineClip(
    path: '/local/path/intro.mp4',
    type: MediaType.video,
  ),
  const TimelineClip(
    path: '/local/path/title-card.png',
    type: MediaType.image,
    duration: Duration(seconds: 2),
    scale: 1.2,
  ),
  const TimelineClip(
    path: '/local/path/outro.mp4',
    type: MediaType.video,
  ),
];
```

Load the native composition and render the texture:

```dart
final textureId = await player.load(clips);

AspectRatio(
  aspectRatio: 16 / 9,
  child: Texture(textureId: textureId),
);
```

Control playback:

```dart
await player.play();
await player.pause();
await player.seekTo(const Duration(milliseconds: 1500));
await player.setVolume(0.8);
```

Listen to timeline state:

```dart
StreamBuilder<TimelinePlayerState>(
  stream: player.stateStream,
  builder: (context, snapshot) {
    final state = snapshot.data ?? const TimelinePlayerState.initial();

    return Text(
      'Clip ${state.clipIndex + 1} - '
      '${state.globalPosition.inMilliseconds} ms',
    );
  },
);
```

Apply pan/crop to a clip:

```dart
await player.setClipAlignment(
  state.clipIndex,
  0.4,
  -0.2,
);
```

Alignment values use the `-1.0..1.0` range for both axes. To export the same
pan/crop result, keep your `TimelineClip` list updated with the latest
`Alignment` values before calling `exportTimeline`.

Dispose the player when it is no longer needed:

```dart
@override
void dispose() {
  player.dispose();
  super.dispose();
}
```

## Exporting MP4

Use `exportTimeline` to render the timeline to a local MP4 file:

```dart
final outputPath = await player.exportTimeline(
  clips,
  outputPath: '/local/path/final-video.mp4',
);
```

If `outputPath` is omitted, the native platform creates a temporary output file
and returns its path.

`exportTimeline` does not require `load` to be called first. It only needs a
non-empty list of `TimelineClip`s with valid local file paths.

## Loading videos from the gallery

Gallery picking is intentionally not built into this plugin. Use a picker package
in your app, then pass the returned local paths to `video_ultra_player`.

Example using `image_picker`:

```yaml
dependencies:
  image_picker: ^1.2.2
  video_ultra_player: ^1.0.0
```

```dart
import 'package:image_picker/image_picker.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

final picker = ImagePicker();
final player = NativeTimelinePlayer();

final videos = await picker.pickMultiVideo();
if (videos.isNotEmpty) {
  final clips = videos
      .map(
        (video) => TimelineClip(
          path: video.path,
          type: MediaType.video,
        ),
      )
      .toList();

  final textureId = await player.load(clips);

  final outputPath = await player.exportTimeline(clips);
}
```

If your app opens the iOS photo library, add a usage description to the app's
`ios/Runner/Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Select videos from your library to preview and export them.</string>
```

## API reference

### TimelineClip

```dart
const TimelineClip({
  required String path,
  required MediaType type,
  Duration? duration,
  Alignment alignment = Alignment.center,
  double scale = 1.0,
})
```

| Property | Description |
| --- | --- |
| `path` | Local file path for the media item. |
| `type` | `MediaType.video` or `MediaType.image`. |
| `duration` | Optional segment duration. Recommended for images. |
| `alignment` | Initial pan/crop alignment for the clip. |
| `scale` | Clip scale used for crop/zoom. Must be greater than zero. |

### TimelinePlayerState

| Property | Description |
| --- | --- |
| `globalPosition` | Current position in the full timeline. |
| `clipIndex` | Index of the active clip. |
| `localPosition` | Current position inside the active clip. |
| `isPlaying` | Whether the native player is currently playing. |
| `totalDuration` | Total duration of the timeline. |

### NativeTimelinePlayer

| Member | Description |
| --- | --- |
| `load(List<TimelineClip>)` | Builds the native preview composition and returns a `textureId`. |
| `exportTimeline(List<TimelineClip>, {String? outputPath})` | Exports the timeline to MP4 and returns the output path. |
| `play()` | Starts playback. |
| `pause()` | Pauses playback. |
| `seekTo(Duration)` | Seeks to a global timeline position. |
| `setVolume(double)` | Sets volume from `0.0` to `1.0`. |
| `setClipAlignment(int, double, double)` | Updates pan/crop alignment for a clip. |
| `stateStream` | Broadcast stream of `TimelinePlayerState`. |
| `textureId` | Current Flutter texture id after `load`. |
| `dispose()` | Releases native player and texture resources. |

## Example app

The `example/` app demonstrates:

- Loading bundled sample assets.
- Selecting multiple videos from the gallery with `image_picker`.
- Rendering the native timeline in a Flutter `Texture`.
- Playback, scrubbing, volume, and pan/crop.
- Exporting the loaded timeline to MP4.

Run it with:

```bash
cd example
flutter run
```

## Technical notes

- `load` and `exportTimeline` reject empty clip lists.
- Playback methods and `stateStream` require `load` to complete first.
- `exportTimeline` is independent from the preview player and can be called
  without loading a texture.
- Image clips use a default duration of 2 seconds when no duration is provided.
- iOS image clips are converted to temporary MP4 segments before composition.
- Android rebuilds the Media3 composition when live pan/crop changes because
  Media3 effects are immutable.
- The plugin returns local output paths; it does not save exported files to the
  user's gallery or share sheet.

## Development

Run package checks:

```bash
flutter analyze
flutter test
```

Run example checks:

```bash
cd example
flutter test
flutter build apk --debug
flutter build ios --debug --simulator
```

For implementation details, see
[`flow/native-timeline-player.md`](flow/native-timeline-player.md).
