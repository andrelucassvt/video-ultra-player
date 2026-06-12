## 2.0.1

- Fixed README wireframe image not rendering on pub.dev (switched to absolute GitHub raw URL).

## 2.0.0

### Clip speed

- Added `TimelineClip.speed` (`double`, range `[0.5, 2.0]`, default `1.0`) — per-clip playback speed multiplier that adjusts effective clip duration at the native compositor level.
- Added `NativeTimelinePlayer.setClipSpeed(int clipIndex, double speed)` to change a loaded clip's speed without a full reload.

### Audio track overlay

- Added `AudioTrack` model — describes an external audio file overlaid on the timeline with offset, volume, trim bounds, and fade-in/out ramps.
- Added `NativeTimelinePlayer.setAudioTrack(AudioTrack track)` to attach or replace the overlay audio track on a loaded timeline.
- Added `NativeTimelinePlayer.removeAudioTrack()` to detach the current overlay audio track.

### Undo / redo

- Added `EditHistoryState` model (`canUndo`, `canRedo`) — emitted by the native layer whenever the edit-history stack changes.
- Added `NativeTimelinePlayer.undo()` and `NativeTimelinePlayer.redo()` to step through the edit history without a reload.
- `TimelinePlayerState` now carries an `EditHistoryState` so the UI can reflect undo/redo availability in real time.

### Clip thumbnails

- Added `ClipThumbnail` model — holds the file-system path and source timestamp for a cached JPEG frame.
- Added `NativeTimelinePlayer.generateThumbnails(int clipIndex, {int count})` to extract evenly-spaced frames from a clip for display in a timeline scrubber.

### Example app — full editor UI

- Replaced the old single-screen demo with a CapCut-inspired editor shell:
  - `EditorScreen` with `EditorController` managing all editing state.
  - Timeline section: horizontal ruler, animated playhead, clip strip with per-clip thumbnail strips, and drag-to-trim handles.
  - Bottom toolbar: Play/Pause, Split at playhead, Speed sheet, Aspect Ratio sheet, and Delete clip.
  - Media picker — pick videos from the device gallery to add to the timeline.
  - Export button uses `exportCurrentTimeline()` so the output always matches the current preview.

### Bug fixes

- Fixed audio track errors caused by incorrect clipping configuration on Android.
- Fixed frame-ready observation timing that caused blank frames on initial load on Android.
- Fixed clip width calculation using `clamp` for a minimum visible width in the timeline UI.
- Fixed duration handling for edited clips to use full source duration in the Media3 compositor.

---

## 1.2.0

### Timeline editing

- Added `NativeTimelinePlayer.trimClip(int clipIndex, {Duration? trimStart, Duration? trimEnd})` to non-destructively adjust the in/out points of a clip.
- Added `NativeTimelinePlayer.splitClip(int clipIndex, Duration atLocalPosition)` to cut a clip in two at a given position; the split point is always a hard cut.
- Added `NativeTimelinePlayer.insertClip(int atIndex, TimelineClip clip)` to insert a new clip at any position in the timeline.
- Added `NativeTimelinePlayer.removeClip(int clipIndex)` to remove a clip from the timeline.
- Added `NativeTimelinePlayer.moveClip(int fromIndex, int toIndex)` to reorder clips without a full reload.
- Added `NativeTimelinePlayer.replaceClip(int clipIndex, TimelineClip clip)` to swap a clip while preserving playback position.
- All editing operations rebuild the native composition in-place and preserve the current playback position and play/pause state.

### Export from edited state

- Added `NativeTimelinePlayer.exportCurrentTimeline({String? outputPath})` to export the timeline as it currently exists in the native compositor — including all edits applied since `load`. This is the correct export method to call after any editing operation.

### Model changes

- Added `TimelineClip.trimStart` and `TimelineClip.trimEnd` (`Duration?`) to declare source trim bounds when constructing a clip.
- Added `TimelineClip.transitionToNext` (`ClipTransition?`) for per-boundary transitions.
- Added `ClipTransition` model (`TransitionType.none` / `TransitionType.crossfade`, `Duration duration`).
- Added `TimelinePlayerState.clipDurations` (`List<Duration>`) — emitted after every mutation so the UI can re-sync the timeline bar without a reload.

### Example app

- Added editing toolbar: Split at playhead, Remove clip, Move ◀/▶, Trim in/Trim out.
- Export button now uses `exportCurrentTimeline()` so the exported MP4 matches the edited preview.
- Clip chip count now derived from `state.clipDurations` for immediate accuracy after splits and removes.

---

## 1.1.0

- Added `NativeTimelinePlayer.seekToClip(int clipIndex)` to seek directly to the start of a specific clip in the timeline (resolved natively on both iOS and Android).
- Added clip-jump chips in the example app to demonstrate the new API.

## 1.0.2

- Fixed image clips rendered upside-down in preview and export on iOS (`makePixelBuffer`: apply vertical flip to CGContext before drawing UIImage).

## 1.0.1

- Removed cross-fade transition feature: `TimelineCompositionConfig.transitionDuration` removed.
- Fixed Android preview blank screen caused by incompatibility between `VideoCompositorSettings` and `CompositionPlayer` (`SingleInputVideoGraph`).
- Simplified composition to a single gapless sequence on both iOS and Android.
- Improved playback error messages to include full native cause chain.

## 1.0.0

- Initial release.
- Added native gapless timeline preview for local video and image clips.
- Added MP4 export for composed timelines on iOS and Android.
- Added playback controls, timeline state stream, scrub support, and per-clip pan/crop alignment.
- Added an example app with bundled sample media, gallery video selection, preview, and export.
