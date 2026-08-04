import 'dart:async';

import 'package:video_ultra_player/video_ultra_player.dart';

/// In-memory player for widget tests: records channel-like calls and keeps a
/// local overlay list, mirroring the native behavior.
class FakeTimelinePlayer extends NativeTimelinePlayer {
  FakeTimelinePlayer({this.loadGate});

  /// When set, [load] waits on this gate instead of returning immediately —
  /// used to simulate a load that completes after the controller is disposed.
  final Completer<int>? loadGate;

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
    final gate = loadGate;
    if (gate != null) {
      return gate.future;
    }
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

  @override
  Future<void> replaceClip(int clipIndex, TimelineClip clip) async {
    calls.add('replaceClip:$clipIndex');
  }

  /// Config updates applied in place, in order.
  final List<TimelineCompositionConfig> appliedConfigs =
      <TimelineCompositionConfig>[];

  /// Gate that holds [setCompositionConfig] open so a test can observe how
  /// concurrent requests coalesce.
  Completer<void>? configGate;

  @override
  Future<void> setCompositionConfig(TimelineCompositionConfig config) async {
    calls.add('setCompositionConfig');
    appliedConfigs.add(config);
    final gate = configGate;
    if (gate != null) {
      configGate = null;
      await gate.future;
    }
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }

  Future<void> close() => _stateController.close();
}
