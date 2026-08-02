import 'dart:async';

import 'package:video_ultra_player/video_ultra_player.dart';

/// In-memory player for widget tests: records channel-like calls and keeps a
/// local overlay list, mirroring the native behavior.
class FakeTimelinePlayer extends NativeTimelinePlayer {
  FakeTimelinePlayer();

  final List<String> calls = <String>[];
  final List<TimelineTextOverlay> overlays = <TimelineTextOverlay>[];
  final StreamController<TimelinePlayerState> _stateController =
      StreamController<TimelinePlayerState>.broadcast();

  @override
  Future<int> load(
    List<TimelineClip> clips, {
    TimelineCompositionConfig? config,
  }) async {
    calls.add('load');
    return 42;
  }

  @override
  Stream<TimelinePlayerState> get stateStream => _stateController.stream;

  @override
  Future<void> addTextOverlay(TimelineTextOverlay overlay) async {
    calls.add('addTextOverlay:${overlay.id}');
    overlays.add(overlay);
  }

  @override
  Future<void> updateTextOverlay(TimelineTextOverlay overlay) async {
    calls.add('updateTextOverlay:${overlay.id}');
    final index = overlays.indexWhere((o) => o.id == overlay.id);
    if (index != -1) {
      overlays[index] = overlay;
    }
  }

  @override
  Future<void> removeTextOverlay(String overlayId) async {
    calls.add('removeTextOverlay:$overlayId');
    overlays.removeWhere((o) => o.id == overlayId);
  }

  Future<void> close() => _stateController.close();
}
