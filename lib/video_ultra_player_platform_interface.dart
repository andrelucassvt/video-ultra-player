import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'video_ultra_player_method_channel.dart';

abstract class VideoUltraPlayerPlatform extends PlatformInterface {
  /// Constructs a VideoUltraPlayerPlatform.
  VideoUltraPlayerPlatform() : super(token: _token);

  static final Object _token = Object();

  static VideoUltraPlayerPlatform _instance = MethodChannelVideoUltraPlayer();

  /// The default instance of [VideoUltraPlayerPlatform] to use.
  ///
  /// Defaults to [MethodChannelVideoUltraPlayer].
  static VideoUltraPlayerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [VideoUltraPlayerPlatform] when
  /// they register themselves.
  static set instance(VideoUltraPlayerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
