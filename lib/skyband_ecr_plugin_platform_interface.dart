import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'skyband_ecr_plugin_method_channel.dart';

abstract class SkybandEcrPluginPlatform extends PlatformInterface {
  /// Constructs a SkybandEcrPluginPlatform.
  SkybandEcrPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static SkybandEcrPluginPlatform _instance = MethodChannelSkybandEcrPlugin();

  /// The default instance of [SkybandEcrPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelSkybandEcrPlugin].
  static SkybandEcrPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SkybandEcrPluginPlatform] when
  /// they register themselves.
  static set instance(SkybandEcrPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
