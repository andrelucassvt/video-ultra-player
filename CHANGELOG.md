## 2.3.0

### Captions

- Added the public `TimelineCaptionCue`, `TimelineCaptionWord`, and `TimelineCaptionStyle` models and the federated `setCaptions`, `removeCaptions`, and `extractAudio` APIs.
- Captions burn into the preview and the exported MP4 on iOS and Android through a single native overlay that picks the active cue from the frame's presentation time — one composition rebuild covers 20–180 cues.
- Added the karaoke mode: the active word is highlighted per its own window (`words` on each cue), with per-word `CATextLayer` highlight layers on iOS export and span-based highlighting in the Android bitmap renderer.
- Style support: ARGB text/highlight colors, font size and stroke as fractions of the video height, normalized vertical position, uppercase, and background box opacity.
- Caption mutations participate in the native undo/redo history on both platforms.
- Added `NativeTimelinePlayer.extractAudio({outputPath})`: extracts the audio of the loaded composition (trims, speeds, gaps included) as an m4a file — Android uses a Media3 `Transformer` audio-only composition; iOS exports the composition with `AVAssetExportPresetAppleM4A`.
- Audio extraction keeps the source sample rate and channel layout (the `sampleRate` contract hint is reserved for future resampling).

## 2.2.0

### In-place output config

- Added `NativeTimelinePlayer.setCompositionConfig(TimelineCompositionConfig config)` and the underlying federated `setCompositionConfig` platform call — changes output resolution/aspect ratio without a dispose/load cycle, preserving the texture ID, clip list, text overlays, audio track, undo history, and playback position. Previously the example app routed aspect-ratio changes through dispose + load, which blanked the preview and silently dropped overlays and undo history.
- Added `NativeTimelinePlayer.compositionConfig` getter to read the config currently applied to the loaded timeline.
- iOS applies the change through the existing surgical `videoComposition` rebuild path (only render size and per-segment transforms depend on config, so the underlying composition is untouched and nothing is re-decoded).

### Performance

- Loading no longer blocks the platform thread: iOS composition assembly (reading source tracks, rendering stills) runs on a dedicated build queue, and Android metadata extraction runs on a bounded pool resolving clips in parallel — only texture/player creation returns to the main thread on either platform.
- Android now does a single `MediaMetadataRetriever` pass per clip (duration, dimensions, and rotation together) behind a process-wide `SourceMetadataCache` keyed by path, mtime, and size, instead of two passes.
- iOS still-image renders now live in a shared `ImageClipVideoCache` that survives controller disposal, encode at 6 fps, and cap the canvas at 1920 px, instead of re-encoding every still to MP4 on each rebuild at full photo resolution.
- Reduced channel traffic: both platforms deduplicate the emitted state payload, `NativeTimelinePlayer.stateStream` applies `distinct()` in Dart, and the Android playback ticker drops to 250 ms while paused instead of pushing ~30 identical messages per second.
- Scrub throttle increased from 16 ms to 33 ms to match the composition's 30 fps render rate, avoiding queued seek frames the preview never shows.
- Rapid taps through an aspect-ratio/resolution picker now coalesce into a single trailing native call instead of one rebuild per tap.
- Removed a per-display-tick debug log left in the iOS texture.

## 2.1.1

- Fixed iOS text-overlay export crashes on affected Simulator runtimes by compositing overlays as an additional Core Animation input track instead of post-processing the rendered video layer.
- Replaced raster-backed export layers with `CATextLayer` while preserving cached raster rendering for the live preview.

## 2.1.0

### Text overlays

- Added the public `TimelineTextOverlay` model and the federated `addTextOverlay`, `updateTextOverlay`, and `removeTextOverlay` APIs.
- Added native text rendering to preview and MP4 export on iOS and Android, including timeline visibility windows, normalized positioning, rotation, opacity, foreground/background colors, multiline alignment, system fonts, and custom font files.
- Included text overlay mutations in the native undo/redo history.
- Added a complete text editing flow to the example app with creation, selection, dragging, timing, styling, and deletion controls.

### Example editor

- Redesigned the editor with a light theme, consolidated toolbar, and dedicated media and text timeline lanes.
- Added image clip duration editing and stable session storage for imported media files.
- Improved media selection, export/error feedback, and automated editor coverage.

### Fixes and performance

- Fixed an iOS `AVPlayerItem.setVideoComposition` abort when adding text by keeping `AVVideoCompositionCoreAnimationTool` in the offline export pipeline and rendering text directly into preview texture frames.
- Fixed upside-down iOS text and made preview/export reuse the same cached rasterization, with frame rendering serialized off the main thread.
- Fixed Android freezes and Media3 bitmap errors when a text overlay is outside its time window by preserving valid text dimensions and hiding it through opacity.
- Fixed the example preview showing a second selected-text copy or keeping it visible after its end time.

## 2.0.5

- Fixed iOS crash/silent failure when loading a timeline with no audio clips: audio composition track is now created only when at least one clip has an audio track (`hasAnyClipAudio` guard in `TimelineComposition`).

## 2.0.4
 - Update doc
 
## 2.0.3

- Constrained wireframe image to 480 px wide in README.

## 2.0.2

- Trimmed README to reduce size on pub.dev (552 → 183 lines).

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
