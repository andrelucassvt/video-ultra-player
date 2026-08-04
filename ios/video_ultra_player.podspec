#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint video_ultra_player.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'video_ultra_player'
  s.version          = '2.2.0'
  s.summary          = 'Native gapless timeline preview and MP4 export for Flutter.'
  s.description      = <<-DESC
Flutter plugin for previewing and exporting native media timelines built from local video and image files.
                       DESC
  s.homepage         = 'https://pub.dev/packages/video_ultra_player'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Andre Lucas'
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'video_ultra_player_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
