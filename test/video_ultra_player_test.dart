import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player/video_ultra_player_platform_interface.dart';
import 'package:video_ultra_player/video_ultra_player_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockVideoUltraPlayerPlatform
    with MockPlatformInterfaceMixin
    implements VideoUltraPlayerPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final VideoUltraPlayerPlatform initialPlatform = VideoUltraPlayerPlatform.instance;

  test('$MethodChannelVideoUltraPlayer is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelVideoUltraPlayer>());
  });

  test('getPlatformVersion', () async {
    VideoUltraPlayer videoUltraPlayerPlugin = VideoUltraPlayer();
    MockVideoUltraPlayerPlatform fakePlatform = MockVideoUltraPlayerPlatform();
    VideoUltraPlayerPlatform.instance = fakePlatform;

    expect(await videoUltraPlayerPlugin.getPlatformVersion(), '42');
  });
}
