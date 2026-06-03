import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/src/kokoro_tts.cpp');
  var content = file.readAsStringSync();
  
  if (!content.contains('LOGE("espeak init error: %d", sample_rate);')) {
    content = content.replaceFirst('''
    if (sample_rate < 0) {
        return -11; // espeak init error
    }
''', '''
    if (sample_rate < 0) {
        LOGE("espeak init error: %d", sample_rate);
        return -11; // espeak init error
    }
''');
  }

  content = content.replaceAll('return -10; // ONNX Error', 'return -10;');
  
  // Also log if model load succeeds
  content = content.replaceFirst('''
    g_initialized = true;
    return 1; // Success
''', '''
    LOGI("kokoro_init success");
    g_initialized = true;
    return 1; // Success
''');

  file.writeAsStringSync(content);
}
