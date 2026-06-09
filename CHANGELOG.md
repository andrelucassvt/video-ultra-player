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
