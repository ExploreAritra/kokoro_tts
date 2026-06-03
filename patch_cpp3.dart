import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/src/kokoro_tts.cpp');
  var content = file.readAsStringSync();
  
  if (!content.contains('LOGI("kokoro_init called with model_path: %s", model_path);')) {
    content = content.replaceFirst('''
FFI_PLUGIN_EXPORT int kokoro_init(const char* model_path, const char* voices_path, const char* espeak_data_path) {
    if (model_path) g_model_path = model_path;
''', '''
FFI_PLUGIN_EXPORT int kokoro_init(const char* model_path, const char* voices_path, const char* espeak_data_path) {
    LOGI("kokoro_init called with model_path: %s", model_path ? model_path : "null");
    LOGI("voices_path: %s", voices_path ? voices_path : "null");
    LOGI("espeak_data_path: %s", espeak_data_path ? espeak_data_path : "null");
    if (model_path) g_model_path = model_path;
''');
  }

  file.writeAsStringSync(content);
}
