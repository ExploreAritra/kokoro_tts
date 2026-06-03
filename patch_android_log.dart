import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/src/kokoro_tts.cpp');
  var content = file.readAsStringSync();
  
  if (!content.contains("#ifdef __ANDROID__")) {
    content = content.replaceFirst('#include "kokoro_vocab.h"', '''#include "kokoro_vocab.h"
#ifdef __ANDROID__
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "Kokoro C++", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "Kokoro C++", __VA_ARGS__)
#else
#define LOGI(...) do { printf("[Kokoro C++] " __VA_ARGS__); printf("\\n"); fflush(stdout); } while(0)
#define LOGE(...) do { printf("[Kokoro C++] Error: " __VA_ARGS__); printf("\\n"); fflush(stdout); } while(0)
#endif
''');
  }

  // Replace printf with LOGI/LOGE
  content = content.replaceAll('printf("[Kokoro C++] Synthesize called with text length %zu, voice %s, output %s\\n", text ? strlen(text) : 0, voice_name ? voice_name : "null", output_wav_path ? output_wav_path : "null");',
    'LOGI("Synthesize called with text length %zu, voice %s, output %s", text ? strlen(text) : 0, voice_name ? voice_name : "null", output_wav_path ? output_wav_path : "null");');
  
  content = content.replaceAll('printf("[Kokoro C++] Error: not initialized (g_initialized=%d, g_ort_session=%p)\\n", g_initialized, g_ort_session);',
    'LOGE("not initialized (g_initialized=%d, g_ort_session=%p)", g_initialized, g_ort_session);');

  content = content.replaceAll('printf("[Kokoro C++] Error: null text or output path\\n");',
    'LOGE("null text or output path");');

  content = content.replaceAll('printf("[Kokoro C++] Generated phonemes: %s\\n", all_phonemes.c_str());',
    'LOGI("Generated phonemes: %s", all_phonemes.c_str());');
    
  content = content.replaceAll('printf("[Kokoro C++] Generated %zu tokens. First 5: ", tokens.size());',
    'LOGI("Generated %zu tokens", tokens.size());');

  content = content.replaceAll('printf("%ld ", tokens[i]);', '');
  content = content.replaceAll('printf("\\n");', '');
  content = content.replaceAll('fflush(stdout);', '');

  content = content.replaceAll('printf("[Kokoro C++] ONNX Exception: %s\\n", e.what());',
    'LOGE("ONNX Exception: %s", e.what());');
  content = content.replaceAll('printf("[Kokoro C++] std::exception: %s\\n", e.what());',
    'LOGE("std::exception: %s", e.what());');
  content = content.replaceAll('printf("[Kokoro C++] Unknown exception in ONNX init\\n");',
    'LOGE("Unknown exception in ONNX init");');
    
  file.writeAsStringSync(content);
}
