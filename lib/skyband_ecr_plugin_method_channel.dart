import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'skyband_ecr_plugin_platform_interface.dart';

/// An implementation of [SkybandEcrPluginPlatform] that uses method channels.
class MethodChannelSkybandEcrPlugin extends SkybandEcrPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('skyband_ecr_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
