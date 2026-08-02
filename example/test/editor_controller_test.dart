import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/media_clip.dart';
import 'package:video_ultra_player_example/editor/media_session/editor_media_session_service_impl.dart';

import 'test_fakes.dart';

void main() {
  test('missing media blocks the native player', () async {
    final player = FakeTimelinePlayer();
    final controller = EditorController(player: player);

    await controller.replaceTimeline(
      [
        TimelineClip(
          path: '/nonexistent/never.mp4',
          type: MediaType.video,
        ),
      ],
      source: 'test',
    );

    expect(controller.error, editorMediaUnavailableError);
    expect(controller.loading, isFalse);
    expect(controller.hasTimeline, isFalse);
    expect(player.calls, isEmpty);
    controller.dispose();
  });

  test('a load completing after dispose is discarded', () async {
    final gate = Completer<int>();
    final player = FakeTimelinePlayer(loadGate: gate);
    final controller = EditorController(player: player);
    final dir = await Directory.systemTemp.createTemp('vc_late_test_');
    final file = File('${dir.path}/a.mp4');
    await file.writeAsBytes(<int>[1, 2, 3]);

    var notifications = 0;
    controller.addListener(() => notifications++);

    final pending = controller.replaceTimeline(
      [TimelineClip(path: file.path, type: MediaType.video)],
      source: 'test',
    );
    await _waitUntil(() async => player.calls.contains('load'));
    controller.dispose();
    gate.complete(42);
    await pending;

    expect(player.calls, contains('load'));
    expect(player.calls, contains('dispose'));
    expect(controller.error, isNull);
    expect(controller.textureId, isNull);
    expect(notifications, 0);

    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('image clip duration is clamped and committed via replaceClip', () async {
    final player = FakeTimelinePlayer();
    final controller = EditorController(player: player);
    final dir = await Directory.systemTemp.createTemp('vc_image_test_');
    final file = File('${dir.path}/still.png');
    await file.writeAsBytes(<int>[1, 2, 3]);

    await controller.replaceTimeline(
      [
        TimelineClip(
          path: file.path,
          type: MediaType.image,
          duration: kDefaultImageClipDuration,
        ),
      ],
      source: 'test',
    );
    expect(controller.hasSelectedImageClip, isTrue);

    await controller.setSelectedClipImageDuration(const Duration(seconds: 30));

    expect(controller.clips.single.duration, const Duration(seconds: 15));
    expect(player.calls, contains('replaceClip:0'));
    expect(controller.canUndo, isTrue);

    controller.dispose();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('pickMedia imports media into the session and replaces the timeline',
      () async {
    final supportDir = await Directory.systemTemp.createTemp('vc_support_');
    final sourceDir = await Directory.systemTemp.createTemp('vc_source_');
    final video = File('${sourceDir.path}/a.mp4')..writeAsBytesSync(<int>[1, 2, 3]);
    final image = File('${sourceDir.path}/b.png')..writeAsBytesSync(<int>[4, 5]);
    final session = EditorMediaSessionServiceImpl(
      supportDirectoryProvider: () async => supportDir,
    );
    final player = FakeTimelinePlayer();
    final controller = EditorController(
      player: player,
      picker: _FakeImagePicker(<XFile>[XFile(video.path), XFile(image.path)]),
      mediaSession: session,
    );

    await controller.pickMedia();

    expect(controller.clips.length, 2);
    expect(controller.clips[0].type, MediaType.video);
    expect(controller.clips[0].duration, isNull);
    expect(controller.clips[1].type, MediaType.image);
    expect(controller.clips[1].duration, kDefaultImageClipDuration);
    expect(controller.clips[0].path, isNot(video.path));
    expect(controller.clips[0].path, startsWith(supportDir.path));
    expect(player.calls, contains('load'));

    final sessionsRoot = Directory(
      '${supportDir.path}/video_ultra_player_example_editor_sessions',
    );
    final importedFiles = await sessionsRoot
        .list(recursive: true)
        .where((entity) => entity is File)
        .toList();
    expect(importedFiles.length, 2);

    // Switching to another timeline releases the orphaned session files.
    final other = File('${sourceDir.path}/c.mp4')..writeAsBytesSync(<int>[6, 7]);
    await controller.replaceTimeline(
      [TimelineClip(path: other.path, type: MediaType.video)],
      source: 'other',
    );

    await _waitUntil(() async {
      final files = await sessionsRoot
          .list(recursive: true)
          .where((entity) => entity is File)
          .toList();
      return files.isEmpty;
    });

    controller.dispose();
    await sourceDir.delete(recursive: true);
  });
}

class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker(this.files);

  final List<XFile> files;

  @override
  Future<List<XFile>> pickMultipleMedia({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    return files;
  }
}

Future<void> _waitUntil(Future<bool> Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition never became true');
}
