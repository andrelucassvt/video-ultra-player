import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  const layer = TimelineVideoLayer(
    id: 'layer-1',
    path: '/v.mp4',
    start: Duration(milliseconds: 1500),
    trimStart: Duration(milliseconds: 200),
    trimEnd: Duration(milliseconds: 4200),
    x: 0.25,
    y: 0.75,
    widthFraction: 0.4,
  );

  test('toJson serializes durations in milliseconds', () {
    expect(layer.toJson(), <String, dynamic>{
      'id': 'layer-1',
      'path': '/v.mp4',
      'startMs': 1500,
      'trimStartMs': 200,
      'trimEndMs': 4200,
      'x': 0.25,
      'y': 0.75,
      'widthFraction': 0.4,
      'opacity': 1.0,
    });
  });

  test('fromJson round-trips toJson', () {
    expect(TimelineVideoLayer.fromJson(layer.toJson()), layer);
  });

  test('duration is trimEnd minus trimStart', () {
    expect(layer.duration, const Duration(milliseconds: 4000));
  });

  test('null trimEnd yields null duration and omits trimEndMs', () {
    const open = TimelineVideoLayer(
      id: 'layer-2',
      path: '/v.mp4',
      start: Duration.zero,
    );
    expect(open.duration, isNull);
    expect(open.toJson().containsKey('trimEndMs'), isFalse);
    expect(open.toJson()['trimStartMs'], 0);
  });

  test('fromJson reads native source dimensions', () {
    final resolved = TimelineVideoLayer.fromJson(<String, dynamic>{
      ...layer.toJson(),
      'sourceWidth': 1080,
      'sourceHeight': 1920,
    });
    expect(resolved.sourceWidth, 1080);
    expect(resolved.sourceHeight, 1920);
  });

  test('toJson never sends source dimensions to native', () {
    const withSource = TimelineVideoLayer(
      id: 'layer-3',
      path: '/v.mp4',
      start: Duration.zero,
      sourceWidth: 1080,
      sourceHeight: 1920,
    );
    expect(withSource.toJson().containsKey('sourceWidth'), isFalse);
    expect(withSource.toJson().containsKey('sourceHeight'), isFalse);
  });

  test('copyWith changes only the given field', () {
    final moved = layer.copyWith(x: 0.2);
    expect(moved.x, 0.2);
    expect(moved.y, layer.y);
    expect(moved.start, layer.start);
    expect(moved.trimEnd, layer.trimEnd);
    expect(moved.widthFraction, layer.widthFraction);
  });

  test('heightFraction is optional and only serialized when set', () {
    expect(layer.heightFraction, isNull);
    expect(layer.toJson().containsKey('heightFraction'), isFalse);

    final stretched = layer.copyWith(heightFraction: 0.3);
    expect(stretched.toJson()['heightFraction'], 0.3);
    expect(TimelineVideoLayer.fromJson(stretched.toJson()), stretched);
  });
}
