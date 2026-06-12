---
name: implement-video-editor
description: >-
  Scaffolds the full CapCut-like timeline video editor from the video_ultra_player
  plugin's example/ into a consumer Flutter app, keeping the exact same dark design,
  PLUS a media-picker screen before the editor where the user selects videos/images
  to load. Generates the editor screen, ChangeNotifier controller, all timeline
  widgets, theme, and the picker; adds the required dependencies and iOS/Android
  permissions. Use whenever the user wants to add the video editor / timeline editor
  to their app, "implement the editor like in the example", build a CapCut-style
  video editor, add a clip timeline with trim/split/speed/audio/export, or add a
  screen to pick videos and images before editing — even if they don't name the
  plugin or say "scaffold". Activate for "adiciona o editor de vídeo", "quero o
  editor igual ao example", "tela pra escolher os vídeos antes de editar",
  "implementa a timeline de edição", or "monta o editor no meu app".
---

# Implement the video editor (with a media-picker screen up front)

This skill drops the proven editor from the plugin's `example/` app into a
**consumer Flutter app** that uses `video_ultra_player`, preserving the exact
dark "CapCut-like" design, and adds one thing the example lacks: a **media-picker
screen shown before the editor**, where the user chooses videos and images that
become the timeline.

The design is not re-derived from a description — it's **bundled verbatim** in
`assets/app_template/lib/` and copied in. Your job is orchestration: copy, rewire
the package name, wire navigation, set up deps and permissions, and verify it
analyzes cleanly. Resist rewriting the UI by hand; the tuned timeline widgets
(clip strip, trim handles, ruler, playhead) are easy to subtly break.

## What gets generated

```
lib/
├── main.dart                    # entry → MediaPickerScreen (template; wire, don't blindly clobber)
├── media/
│   ├── media_clip.dart          # path → TimelineClip helper (video vs image, 3s default for images)
│   └── media_picker_screen.dart # NEW screen: pick videos/images, review, → editor
└── editor/
    ├── editor_controller.dart   # ChangeNotifier wrapping NativeTimelinePlayer (loadClips entry)
    ├── editor_screen.dart       # takes the picked clips, no sample auto-load
    ├── theme/editor_theme.dart  # dark palette, yellow #f5c518 accent
    └── widgets/                 # top bar, preview, playback, timeline, toolbar, sheets, audio row
```

The flow is: **MediaPickerScreen** (`pickMultipleMedia` → list of clips, review,
"Continuar") → `Navigator.push` → **EditorScreen(clips:)** → `controller.loadClips`.
The editor keeps every feature from the example: play/seek, select, split, trim,
reorder, remove, speed, aspect ratio, resolution, audio track + volume,
undo/redo, filmstrip thumbnails, and export-to-gallery.

## Steps

### 1. Locate the app and read its package name

Find the consumer app root (the `pubspec.yaml` with a `flutter:` section and a
`name:`). Read `name:` — call it `APP_PKG`. Every bundled `.dart` uses the token
`video_ultra_player_example` for its own package; the scaffold script rewrites
that token to `APP_PKG`. (The plugin import `package:video_ultra_player/...` has
no `_example` suffix, so it is never touched.)

If the app does **not** yet depend on the plugin, that's expected — step 2 adds it.

### 2. Add dependencies

Add these under `dependencies:` in the app's `pubspec.yaml` (Dart syntax, not the
Android Groovy/Kotlin DSL — this is the Flutter pubspec):

```yaml
  video_ultra_player:
    path: /ABSOLUTE/PATH/TO/video_ultra_player   # ← REPLACE: ask the user, or use a git/hosted ref
  image_picker: ^1.2.2   # media-picker screen (pickMultipleMedia)
  file_picker: ^11.0.2   # editor's "add audio track"
  gal: ^2.3.1            # export-to-gallery
```

The `video_ultra_player` line is a placeholder — never paste it literally. If the
plugin isn't already in the pubspec, ask the user how they consume it (`path:`,
`git:`, or a published version) before writing it.

Ask the user how they reference the plugin (`path:`, `git:`, or a published
version) if it isn't already in the pubspec — don't guess a path. Then run
`flutter pub get`.

### 3. Scaffold the Dart files

Run the bundled script — it copies the templates and does the token rewrite
deterministically (don't hand-copy 16 files):

```bash
bash <skill_dir>/scripts/scaffold.sh <APP_ROOT> <APP_PKG>
```

This writes `lib/editor/` and `lib/media/`. It does **not** overwrite
`lib/main.dart` — wiring the entry point is a judgment call (step 4).

### 4. Wire the entry point

Make `MediaPickerScreen` the start of the editor flow.

- **Fresh app** (default counter `main.dart`, no real screens): replace
  `lib/main.dart` with the template at
  `assets/app_template/lib/main.dart` (apply the same token rewrite:
  `video_ultra_player_example` → `APP_PKG`).
- **Existing app** with its own routing/home: do **not** clobber `main.dart`.
  Instead, route to `const MediaPickerScreen()` from wherever the user enters the
  editor (a button, a route, a tab). Import
  `package:<APP_PKG>/media/media_picker_screen.dart`.

Ask which case applies if it's ambiguous.

### 5. Native permissions

The picker reads the photo library and `gal` writes the export back to it.

**iOS** — `ios/Runner/Info.plist`, inside the top `<dict>`:

```xml
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Selecione vídeos e imagens para montar sua timeline.</string>
	<key>NSPhotoLibraryAddUsageDescription</key>
	<string>Salvar os vídeos exportados na sua galeria.</string>
```

**Android** — `android/app/src/main/AndroidManifest.xml`, before `<application>`
(only needed for `gal` on API < 29; modern image_picker uses the system photo
picker and needs no read permission):

```xml
    <uses-permission
        android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28" />
```

Also confirm the app's `android/app/build.gradle(.kts)` has `minSdk` ≥ 24 (the
plugin requires it). Don't lower an existing higher value.

### 6. Verify

Run `flutter analyze`. It should be clean. The most common issue is a leftover
`video_ultra_player_example` reference — grep for it under `lib/` and rewrite any
stragglers to `APP_PKG`. Then `flutter pub get` if you haven't, and offer to run
the app so the user sees the picker → editor flow.

## Design notes

`editor/theme/editor_theme.dart` is the single source of the look: near-black
background `#08090c`, surface `#12141a`, yellow accent `#f5c518`, muted text
`#9aa3af`, Material 3 dark. The picker screen pulls from the same constants
(`editorBackground`, `editorAccent`, `editorSurfaceHigh`, `editorLine`,
`editorTextMuted`) so it matches the editor pixel-for-pixel. If the user wants a
different brand color, change `editorAccent` once — everything follows.

## Keeping the bundled design fresh

This skill lives in the same repo as `example/`. If the example's timeline
widgets evolve, re-sync the verbatim design files (theme + widgets, excluding the
adapted `editor_top_bar.dart`) with:

```bash
bash <skill_dir>/scripts/sync_from_example.sh
```

The adapted entry points (`editor_controller.dart`, `editor_screen.dart`,
`editor_top_bar.dart`) and the new `media/*` files carry consumer-app edits and
are intentionally left alone — review them by hand if the example changes shape.

For the underlying plugin API (what `NativeTimelinePlayer` exposes, the models),
see `references/plugin-api.md`.
