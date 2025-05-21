#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint skyband_ecr_plugin.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'skyband_ecr_plugin'
  s.version          = '1.0.0'
  s.summary          = 'A Flutter plugin for SkyBand ECR integration'
  s.description      = <<-DESC
A Flutter plugin for integrating SkyBand ECR devices.
                       DESC
  s.homepage         = 'https://github.com/yourusername/skyband_ecr_plugin'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'your.email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'SkyBandECRSDK', '3.5.0'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'skyband_ecr_plugin_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

  s.vendored_frameworks = 'frameworks/SkyBandECRSDK/SkyBandECRSDK.framework'
end
