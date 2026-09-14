#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint animemaster.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'animemaster'
  s.version          = '2.4.4'
  s.summary          = 'Native parser and local media scanner for AnimeMaster.'
  s.description      = <<-DESC
AnimeMaster native helpers for magnet parsing and local media discovery.
                       DESC
  s.homepage         = 'https://github.com/CongutSun/AnimeMaster_Engine'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'CongutSun' => 'CongutSun@users.noreply.github.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
  s.swift_version = '5.0'
end
