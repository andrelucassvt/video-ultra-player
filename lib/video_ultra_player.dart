
import 'video_ultra_player_platform_interface.dart';

class VideoUltraPlayer {
  Future<String?> getPlatformVersion() {
    return VideoUltraPlayerPlatform.instance.getPlatformVersion();
  }
}
