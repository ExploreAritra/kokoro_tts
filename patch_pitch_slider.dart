import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/example/lib/main.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceFirst('''
                                onChanged: (value) {
                                  setState(() {
                                    _targetPitch = value;
                                  });
                                },
''', '''
                                onChanged: (value) {
                                  setState(() {
                                    _targetPitch = value;
                                    if (_currentHandle != null && _currentSource != null) {
                                      _currentSource!.filters.pitchShiftFilter.shift(soundHandle: _currentHandle).value = value;
                                    }
                                  });
                                },
''');
  file.writeAsStringSync(content);
}
