import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  const cell = TimelineGridCell(
    path: '/a.mp4',
    rect: Rect.fromLTWH(0.5, 0, 0.5, 1),
  );

  test('serializes cells as normalized rects', () {
    final grid = TimelineGridComposition(
      width: 1080,
      height: 1080,
      videoCells: const [cell],
    );

    expect(grid.toJson(), {
      'width': 1080,
      'height': 1080,
      'cells': [
        {'path': '/a.mp4', 'x': 0.5, 'y': 0.0, 'width': 0.5, 'height': 1.0},
      ],
      'overlayImagePath': null,
      'audioCellIndex': null,
      'maxDurationMs': null,
    });
  });

  test('rejects odd or non-positive sizes', () {
    expect(
      () => TimelineGridComposition(
        width: 1081,
        height: 1080,
        videoCells: const [cell],
      ),
      throwsArgumentError,
    );
    expect(
      () => TimelineGridComposition(
        width: 1080,
        height: 0,
        videoCells: const [cell],
      ),
      throwsArgumentError,
    );
  });

  test('rejects empty cells and cells outside the canvas', () {
    expect(
      () => TimelineGridComposition(width: 2, height: 2, videoCells: const []),
      throwsArgumentError,
    );
    expect(
      () => TimelineGridComposition(
        width: 2,
        height: 2,
        videoCells: const [
          TimelineGridCell(path: '/a.mp4', rect: Rect.fromLTWH(0.6, 0, 0.5, 1)),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('rejects an audio cell index out of range', () {
    expect(
      () => TimelineGridComposition(
        width: 2,
        height: 2,
        videoCells: const [cell],
        audioCellIndex: 1,
      ),
      throwsRangeError,
    );
  });

  test('value equality', () {
    TimelineGridComposition build() => TimelineGridComposition(
      width: 2,
      height: 2,
      videoCells: const [cell],
      audioCellIndex: 0,
    );
    expect(build(), build());
    expect(build().hashCode, build().hashCode);
  });
}
