#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint skyband_ecr_plugin.podspec` to validate before publishing.
#
require 'yaml'
pubspec = YAML.load_file(File.join('..', '..', 'pubspec.yaml'))
version = pubspec['version']

Pod::Spec.new do |s|
  s.name             = 'skyband_ecr_plugin'
  s.version          = version
  s.summary          = 'Skyband ECR Plugin'
  s.description      = 'A Flutter plugin for Skyband ECR integration'
  s.homepage         = 'https://skyband.com'
  s.license          = { :type => 'Commercial', :text => 'Copyright (c) 2023 Skyband' }
  s.author           = { 'Skyband' => 'info@skyband.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 arm64',
    'VALID_ARCHS' => 'arm64 x86_64',
    'OTHER_LDFLAGS[sdk=iphoneos*]' => '-framework SkyBandECRSDK',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphonesimulator*]' => 'SIMULATOR',
    'ENABLE_BITCODE' => 'NO'
  }
  
  s.user_target_xcconfig = { 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 arm64',
    'ENABLE_BITCODE' => 'NO'
  }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'skyband_ecr_plugin_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

  s.preserve_paths = 'Frameworks/SkyBandECRSDK/SkyBandECRSDK.framework'
  
  # Only include the framework for device builds
  s.vendored_frameworks = 'Frameworks/SkyBandECRSDK/SkyBandECRSDK.framework'
  s.frameworks = 'UIKit', 'Foundation'
end
