import 'package:flutter_test/flutter_test.dart';
import 'package:skyband_ecr_plugin/skyband_ecr_plugin.dart';
import 'package:skyband_ecr_plugin/skyband_ecr_plugin_platform_interface.dart';
import 'package:skyband_ecr_plugin/skyband_ecr_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSkybandEcrPluginPlatform
    with MockPlatformInterfaceMixin
    implements SkybandEcrPluginPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final SkybandEcrPluginPlatform initialPlatform = SkybandEcrPluginPlatform.instance;

  test('$MethodChannelSkybandEcrPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSkybandEcrPlugin>());
  });

  test('getPlatformVersion', () async {
    SkybandEcrPlugin skybandEcrPlugin = SkybandEcrPlugin();
    MockSkybandEcrPluginPlatform fakePlatform = MockSkybandEcrPluginPlatform();
    SkybandEcrPluginPlatform.instance = fakePlatform;

    expect(await skybandEcrPlugin.getPlatformVersion(), '42');
  });
}
