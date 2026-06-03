import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/example/lib/main.dart');
  var content = file.readAsStringSync();
  
  if (!content.contains("SoLoud.instance.filters.pitchShiftFilter.activate();")) {
    content = content.replaceFirst('''
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  await SoLoud.instance.init();
''', '''
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  await SoLoud.instance.init();
  try {
    SoLoud.instance.filters.pitchShiftFilter.activate();
  } catch (e) {
    print("Failed to activate pitchShiftFilter: \$e");
  }
''');
  }

  // Then add shift update whenever _processQueue is playing
  content = content.replaceAll('''
        // Apply initial effects
        SoLoud.instance.setRelativePlaySpeed(_currentHandle!, _targetSpeed / _nativeSpeed);
        // Note: Pitch filter is omitted here since it requires activating PitchShiftSingle filter first.
''', '''
        // Apply initial effects
        SoLoud.instance.setRelativePlaySpeed(_currentHandle!, _targetSpeed / _nativeSpeed);
        SoLoud.instance.filters.pitchShiftFilter.shift.value = _targetPitch;
''');

  // And also in the Slider for pitch!
  content = content.replaceFirst('''
                        onChanged: (val) {
                          setState(() {
                            _targetPitch = val;
                          });
                        },
''', '''
                        onChanged: (val) {
                          setState(() {
                            _targetPitch = val;
                          });
                          if (_isSynthesizing || _isPlaying || _isPaused) {
                            try {
                              SoLoud.instance.filters.pitchShiftFilter.shift.value = val;
                            } catch (_) {}
                          }
                        },
''');

  file.writeAsStringSync(content);
}
