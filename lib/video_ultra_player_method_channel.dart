import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'video_ultra_player_platform_interface.dart';

/// An implementation of [VideoUltraPlayerPlatform] that uses method channels.
class MethodChannelVideoUltraPlayer extends VideoUltraPlayerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('video_ultra_player');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
