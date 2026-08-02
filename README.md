# video_ultra_player

A Flutter plugin for previewing and exporting a native gapless media timeline made from local video and image files. Renders into a single Flutter `Texture` backed by AVFoundation (iOS) and AndroidX Media3 (Android).

<img src="https://raw.githubusercontent.com/andrelucassvt/video-ultra-player/master/wireframe-en.png" width="480" alt="Editor wireframe">

## Features

- Gapless native timeline preview in one Flutter `Texture`.
- MP4 export with real-time progress stream.
- Video and image clips in the same timeline.
- Non-destructive clip editing: trim, split, insert, remove, move, replace.
- Per-clip speed (0.5× – 2×) and pan/crop with normalized alignment values.
- Overlay audio track with offset, volume, trim, fade-in, and fade-out.
- Timeline text overlays with positioning, timing, rotation, colors, opacity, alignment, and custom fonts.
- Undo/redo with `canUndo` / `canRedo` flags in the state stream.
- Filmstrip thumbnail generation.
- Output aspect ratio presets and resolution control.

## Platform support

| Platform | Preview | Export |
| --- | --- | --- |
| iOS | ✓ | ✓ |
| Android | ✓ | ✓ |
| Web / Desktop | — | — |

## Getting started

```bash
flutter pub add video_ultra_player
```

```dart
import 'package:video_ultra_player/video_ultra_player.dart';
```

## Basic usage

```dart
final player = NativeTimelinePlayer();

final textureId = await player.load([
  const TimelineClip(path: '/path/intro.mp4', type: MediaType.video),
  const TimelineClip(path: '/path/card.png',  type: MediaType.image, duration: Duration(seconds: 3)),
  const TimelineClip(path: '/path/outro.mp4', type: MediaType.video),
]);

// Render
Texture(textureId: textureId)

// Control
await player.play();
await player.pause();
await player.seekTo(const Duration(seconds: 2));
await player.seekToClip(1);
await player.setVolume(0.8);

// State
player.stateStream.listen((state) {
  print('${state.globalPosition} — clip ${state.clipIndex} — undo: ${state.canUndo}');
});

// Dispose
await player.dispose();
```

## Editing

All edits apply to the live composition and emit a new `TimelinePlayerState`.

```dart
await player.trimClip(0, trimStart: const Duration(seconds: 1), trimEnd: const Duration(seconds: 8));
await player.splitClip(1, const Duration(seconds: 3));
await player.insertClip(2, const TimelineClip(path: '/path/b-roll.mp4', type: MediaType.video));
await player.removeClip(2);
await player.moveClip(0, 2);
await player.replaceClip(1, const TimelineClip(path: '/path/new.mp4', type: MediaType.video));
await player.setClipSpeed(0, 0.5);     // slow motion
await player.setClipAlignment(0, 0.4, -0.2);
await player.undo();
await player.redo();
```

## Audio track

```dart
await player.setAudioTrack(const AudioTrack(
  path: '/path/music.mp3',
  offset: Duration(seconds: 2),
  volume: 0.7,
  fadeIn: Duration(milliseconds: 500),
  fadeOut: Duration(seconds: 1),
));

await player.removeAudioTrack();
```

## Text overlays

Text overlays use normalized frame coordinates and are visible in the
half-open timeline window `[start, end)`. The same overlay is rendered in the
preview and burned into the exported MP4.

```dart
const title = TimelineTextOverlay(
  id: 'opening-title',
  text: 'My video',
  start: Duration.zero,
  end: Duration(seconds: 3),
  x: 0.5,
  y: 0.2,
  fontSize: 0.08,
  color: 0xFFFFFFFF,
  backgroundColor: 0x99000000,
);

await player.addTextOverlay(title);
await player.updateTextOverlay(title.copyWith(rotationDegrees: -5));
await player.removeTextOverlay(title.id);
```

## Export

```dart
// From clip list
final path = await player.exportTimeline(clips, outputPath: '/path/out.mp4');

// From current loaded timeline (matches the preview exactly)
final path = await player.exportCurrentTimeline();

// Track progress
player.exportProgress.listen((p) => print('${p.progress * 100}%'));
```

## Clip thumbnails

```dart
final thumbs = await player.generateThumbnails(
  '/path/clip.mp4',
  [Duration.zero, const Duration(seconds: 1), const Duration(seconds: 2)],
  width: 120,
); // List<String> of JPEG paths
```

## Output config

```dart
await player.load(clips, config: const TimelineCompositionConfig(
  aspectRatio: OutputAspectRatio.ratio9x16,
  baseWidth: 1080,
));
```

## API reference

### NativeTimelinePlayer

| Member | Description |
| --- | --- |
| `load(clips, {config})` | Builds the native composition, returns `textureId`. |
| `exportTimeline(clips, {outputPath, config})` | Exports a clip list to MP4. |
| `exportCurrentTimeline({outputPath})` | Exports the loaded composition to MP4. |
| `play()` / `pause()` | Playback control. |
| `seekTo(Duration)` / `seekToClip(int)` | Seek by position or clip index. |
| `setVolume(double)` | Volume `0.0..1.0`. |
| `trimClip` / `splitClip` / `insertClip` / `removeClip` / `moveClip` / `replaceClip` | Clip edits. |
| `setClipSpeed(int, double)` | Per-clip speed (0.5 – 2.0). |
| `setClipAlignment(int, double, double)` | Pan/crop alignment. |
| `setAudioTrack(AudioTrack)` / `removeAudioTrack()` | Overlay audio. |
| `addTextOverlay` / `updateTextOverlay` / `removeTextOverlay` | Timeline text overlays. |
| `undo()` / `redo()` | Edit history. |
| `generateThumbnails(path, timestamps, {width})` | JPEG thumbnail list. |
| `stateStream` | `Stream<TimelinePlayerState>` |
| `exportProgress` | `Stream<TimelineExportProgress>` |
| `dispose()` | Releases native resources. |

### TimelineClip

| Property | Description |
| --- | --- |
| `path` | Absolute local file path. |
| `type` | `MediaType.video` or `MediaType.image`. |
| `duration` | Required for images (default: 2 s). |
| `speed` | Playback speed (0.5 – 2.0, default: 1.0). |
| `alignment` / `scale` | Pan/crop. |
| `trimStart` / `trimEnd` | Source in/out points. |
| `transitionToNext` | Serialized transition descriptor; native playback/export currently use a hard cut. |

### TimelineTextOverlay

| Property | Description |
| --- | --- |
| `id` / `text` | Stable identifier and multiline content. |
| `start` / `end` | Timeline visibility window `[start, end)`. |
| `x` / `y` | Center in normalized frame coordinates (`0.0..1.0`). |
| `rotationDegrees` / `fontSize` | Rotation and size relative to frame height. |
| `color` / `backgroundColor` / `opacity` | ARGB colors and overlay opacity. |
| `textAlign` | Multiline left, center, or right alignment. |
| `fontFamily` / `fontPath` | System family or absolute custom font path. |

### TimelinePlayerState

| Property | Description |
| --- | --- |
| `globalPosition` | Position in the full timeline. |
| `clipIndex` | Active clip index. |
| `localPosition` | Position inside the active clip. |
| `isPlaying` | Playback state. |
| `totalDuration` | Total timeline duration. |
| `clipDurations` | Resolved duration per clip. |
| `canUndo` / `canRedo` | Edit history availability. |

## Technical notes

- Empty clip lists are rejected by `load` and `exportTimeline`.
- Image clips default to 2 s when `duration` is omitted.
- iOS image clips are converted to temporary MP4 segments before composition.
- Clip transitions are currently serialized but both native pipelines render hard cuts.
- Exported files are returned as local paths — use `gal` or similar to save to the gallery.
- `exportTimeline` is independent of the preview player and can be called without `load`.
