# video_ultra_player — public API reference

The editor templates drive the plugin through one façade, `NativeTimelinePlayer`.
You rarely need to touch it directly (the bundled `EditorController` already
wraps every call), but this is the contract when you extend or debug.

Import everything from the barrel:

```dart
import 'package:video_ultra_player/video_ultra_player.dart';
```

## Models

- **`TimelineClip`** — one clip. `path` (absolute file path), `type`
  (`MediaType.video` | `MediaType.image`), optional `duration` (required for
  images, omit for video to use full source), `alignment`, `scale`, `speed`
  (0.5–2.0), `trimStart`, `trimEnd`, `transitionToNext`. Immutable; has
  `copyWith` and `toJson`.
- **`MediaType`** — `video` | `image`.
- **`AudioTrack`** — `path`, `volume` (0.0–1.0). Background audio over the timeline.
- **`OutputAspectRatio`** — `ratio16x9`, `ratio9x16`, `ratio1x1`, `original`.
- **`TimelineCompositionConfig`** — `aspectRatio`, `baseWidth` (output width px).
- **`TimelinePlayerState`** — playback snapshot: `isPlaying`, `globalPosition`,
  `localPosition`, `totalDuration`, `clipIndex`, `clipDurations`. Streamed.
- **`TimelineExportProgress`** — `state`, `progress` (0–1). Streamed during export.

## `NativeTimelinePlayer`

| Method | Purpose |
| --- | --- |
| `load(clips, config:)` → `Future<int>` | Build composition, returns the texture id |
| `stateStream` | `Stream<TimelinePlayerState>` playback updates |
| `exportProgress` | `Stream<TimelineExportProgress>` |
| `play()` / `pause()` / `seekTo(pos)` / `seekToClip(i)` | Transport |
| `setVolume(v)` / `setAudioTrack(t)` / `removeAudioTrack()` | Audio |
| `setClipAlignment(i,x,y)` / `setClipSpeed(i,speed)` | Per-clip transforms |
| `trimClip(i, trimStart:, trimEnd:)` / `splitClip(i, atLocal)` | Edits |
| `insertClip(at, clip)` / `removeClip(i)` / `moveClip(from,to)` / `replaceClip(i,clip)` | Edits |
| `undo()` / `redo()` | History |
| `generateThumbnails(path, timestamps, width:)` → `Future<List<String>>` | Filmstrip |
| `exportCurrentTimeline(outputPath:)` → `Future<String>` | Render to mp4 |
| `dispose()` | Release native resources |

## How the templates use it

`EditorController` (a `ChangeNotifier`) owns one `NativeTimelinePlayer`, keeps
the `List<TimelineClip>` and an undo/redo stack in sync with native edits, and
exposes intent methods (`split`, `trimClip`, `moveClip`, `setSelectedClipSpeed`,
`addAudioTrack`, `export`, `undo`, …). `EditorScreen` rebuilds from
`AnimatedBuilder(controller)` + `StreamBuilder<TimelinePlayerState>`. The only
entry point the picker flow calls is **`loadClips(List<TimelineClip>)`**.
