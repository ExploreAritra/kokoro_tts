import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/example/lib/main.dart');
  var content = file.readAsStringSync();
  
  // Remove global activate
  content = content.replaceFirst('''
  try {
    SoLoud.instance.filters.pitchShiftFilter.activate();
  } catch (e) {
    print("Failed to activate pitchShiftFilter: \$e");
  }
''', '');

  // Add activate to source before playing
  content = content.replaceFirst('''
      try {
        _currentHandle = SoLoud.instance.play(_currentSource!);
''', '''
      try {
        try {
          _currentSource!.filters.pitchShiftFilter.activate();
        } catch (_) {}
        _currentHandle = SoLoud.instance.play(_currentSource!);
''');

  // Change processQueue pitch shift setter
  content = content.replaceAll('''
        SoLoud.instance.filters.pitchShiftFilter.shift.value = _targetPitch;
''', '''
        if (_currentHandle != null) {
          _currentSource!.filters.pitchShiftFilter.shift(soundHandle: _currentHandle).value = _targetPitch;
        }
''');

  // Change Slider pitch shift setter
  content = content.replaceAll('''
                              SoLoud.instance.filters.pitchShiftFilter.shift.value = val;
''', '''
                              if (_currentHandle != null && _currentSource != null) {
                                _currentSource!.filters.pitchShiftFilter.shift(soundHandle: _currentHandle).value = val;
                              }
''');

  file.writeAsStringSync(content);
}
