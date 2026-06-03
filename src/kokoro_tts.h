#ifndef KOKORO_TTS_H_
#define KOKORO_TTS_H_

#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

FFI_PLUGIN_EXPORT int kokoro_init(const char* model_path, const char* voices_path, const char* espeak_data_path);
FFI_PLUGIN_EXPORT int kokoro_is_initialized();
FFI_PLUGIN_EXPORT int kokoro_synthesize(const char* text, const char* voice_name, const char* output_wav_path, float speed);
FFI_PLUGIN_EXPORT void kokoro_free();

// Dummy function to prevent dead-code stripping on iOS
FFI_PLUGIN_EXPORT void kokoro_dummy_prevent_strip();

#ifdef __cplusplus
}
#endif

#endif // KOKORO_TTS_H_
