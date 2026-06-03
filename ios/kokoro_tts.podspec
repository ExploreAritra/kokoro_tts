#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint kokoro_tts.podspec` to validate before publishing.
require 'fileutils'
FileUtils.rm_rf('src')
FileUtils.cp_r('../src', 'src')

Pod::Spec.new do |s|
  s.name             = 'kokoro_tts'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*',
                   'src/espeak-ng/src/libespeak-ng/**/*.c',
                   'src/espeak-ng/src/ucd-tools/src/**/*.c'
  s.exclude_files = 'src/espeak-ng/src/libespeak-ng/event.c',
                    'src/espeak-ng/src/libespeak-ng/fifo.c',
                    'src/espeak-ng/src/libespeak-ng/espeak_command.c',
                    'src/espeak-ng/src/libespeak-ng/mbrowrap.c',
                    'src/espeak-ng/src/libespeak-ng/compilembrola.c',
                    'src/espeak-ng/src/libespeak-ng/synth_mbrola.c',
                    'src/espeak-ng/src/libespeak-ng/klatt.c',
                    'src/espeak-ng/src/libespeak-ng/sPlayer.c'

  s.dependency 'Flutter'
  s.dependency 'onnxruntime-c'
  s.library = 'c++'
  s.platform = :ios, '13.0'
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/src/espeak-ng/src/include" "${PODS_TARGET_SRCROOT}/src/espeak-ng/src/include/compat" "${PODS_TARGET_SRCROOT}/src/espeak-ng/src/ucd-tools/src/include" "${PODS_TARGET_SRCROOT}/src/espeak-ng/android/jni/include"',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'USE_ASYNC=0 BUILD_SHARED_LIBS=0 USE_MBROLA=0 USE_LIBSONIC=0 USE_LIBPCAUDIO=0 USE_KLATT=0 USE_SPEECHPLAYER=0 COMPILE_INTONATIONS=0',
    'OTHER_LDFLAGS' => '-weak_framework "CoreML"'
  }
  
  s.swift_version = '5.0'
end
