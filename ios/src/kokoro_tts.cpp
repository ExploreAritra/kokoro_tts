#include "kokoro_tts.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <string>

#define DR_WAV_IMPLEMENTATION
#include "dr_wav.h"

// Include ONNX Runtime
#include "onnxruntime_cxx_api.h"

// Include espeak-ng
#include "espeak-ng/src/include/espeak-ng/speak_lib.h"

// Include Kokoro Vocab
#include "kokoro_vocab.h"
#ifdef __ANDROID__
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "Kokoro C++", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "Kokoro C++", __VA_ARGS__)
#else
#define LOGI(...) do { printf("[Kokoro C++] " __VA_ARGS__);   } while(0)
#define LOGE(...) do { printf("[Kokoro C++] Error: " __VA_ARGS__);   } while(0)
#endif

#include <fstream>
#include <iostream>
#include <cstring>
#include <algorithm>

static bool g_initialized = false;
static std::string g_model_path = "";
static std::string g_voices_path = "";

// ONNX Globals
static Ort::Env* g_ort_env = nullptr;
static Ort::Session* g_ort_session = nullptr;

extern "C" {

FFI_PLUGIN_EXPORT int kokoro_init(const char* model_path, const char* voices_path, const char* espeak_data_path) {
    LOGI("kokoro_init called with model_path: %s", model_path ? model_path : "null");
    LOGI("voices_path: %s", voices_path ? voices_path : "null");
    LOGI("espeak_data_path: %s", espeak_data_path ? espeak_data_path : "null");
    if (model_path) g_model_path = model_path;
    if (voices_path) g_voices_path = voices_path;
    
    // Initialize ONNX Env
    try {
        g_ort_env = new Ort::Env(ORT_LOGGING_LEVEL_WARNING, "KokoroTTS");
        Ort::SessionOptions session_options;
        session_options.SetIntraOpNumThreads(2);
        
        // Attempt to load model
        // In a real implementation we convert std::string to std::wstring on Windows
#ifdef _WIN32
        // Windows requires wstring
#else
        g_ort_session = new Ort::Session(*g_ort_env, g_model_path.c_str(), session_options);
#endif
    } catch (const Ort::Exception& e) {
        LOGE("ONNX Exception: %s", e.what());
        
        return -10;
    } catch (const std::exception& e) {
        LOGE("std::exception: %s", e.what());
        
        return -10;
    } catch (...) {
        LOGE("Unknown exception in ONNX init");
        
        return -10;
    }

    // Initialize espeak-ng
    int sample_rate = espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, espeak_data_path, 0);
    if (sample_rate < 0) {
        LOGE("espeak init error: %d", sample_rate);
        return -11; // espeak init error
    }
    
    // Configure default voice to allocate translator context
    espeak_SetVoiceByName("en-us");

    LOGI("kokoro_init success");
    g_initialized = true;
    return 1; // Success
}

FFI_PLUGIN_EXPORT int kokoro_is_initialized() {
    return g_initialized ? 1 : 0;
}

FFI_PLUGIN_EXPORT int kokoro_synthesize(const char* text, const char* voice_name, const char* output_wav_path, float speed_val) {
    LOGI("Synthesize called with text length %zu, voice %s, output %s", text ? strlen(text) : 0, voice_name ? voice_name : "null", output_wav_path ? output_wav_path : "null");
    
    
    if (!g_initialized || !g_ort_session) {
        LOGE("not initialized (g_initialized=%d, g_ort_session=%p)", g_initialized, g_ort_session);
        
        return -1;
    }
    if (!text || !output_wav_path) {
        LOGE("null text or output path");
        
        return -2;
    }

    // 1. Text to Phonemes via espeak-ng (using 2 for espeakPHONEMES_IPA)
    std::string all_phonemes = "";
    const char* text_ptr = text;
    while (text_ptr != nullptr && *text_ptr != '\0') {
        const char* phonemes = espeak_TextToPhonemes((const void**)&text_ptr, espeakCHARS_AUTO, 2);
        if (phonemes) {
            all_phonemes += phonemes;
        }
    }
    
    LOGI("Generated phonemes: %s", all_phonemes.c_str());
    
    // 2. Tokenization
    std::vector<int64_t> tokens;
    tokens.push_back(0); // '$' start token
    
    if (!all_phonemes.empty()) {
        const char* p = all_phonemes.c_str();
        while (*p != '\0') {
            int char_len = 1;
            if ((*p & 0xF8) == 0xF0) char_len = 4;
            else if ((*p & 0xF0) == 0xE0) char_len = 3;
            else if ((*p & 0xE0) == 0xC0) char_len = 2;
            
            std::string character(p, char_len);
            auto it = KOKORO_VOCAB.find(character);
            if (it != KOKORO_VOCAB.end()) {
                tokens.push_back(it->second);
            } else if (character != " " && character != "\n") {
                // Unknown character
            }
            p += char_len;
        }
    }
    tokens.push_back(0); // '$' end token
    
    LOGI("Generated %zu tokens", tokens.size());
    for(size_t i = 0; i < std::min((size_t)5, tokens.size()); i++) printf("%lld ", (long long)tokens[i]);
    
    

    // 3. Inference via ONNX
    Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);

    // Tokens Tensor
    int64_t seq_len = static_cast<int64_t>(tokens.size());
    std::vector<int64_t> tokens_shape = {1, seq_len};
    Ort::Value tokens_tensor = Ort::Value::CreateTensor<int64_t>(
        memory_info, tokens.data(), tokens.size(), tokens_shape.data(), tokens_shape.size());

    // 4. Parse voices_flat.bin to get the style vector
    // The flat bin format:
    // Magic "KOKO" (4 bytes)
    // Num Voices (uint32_t)
    // For each voice: Name (32 bytes), Floats (511 * 256 * 4 bytes)
    std::vector<float> style(256, 0.0f);
    
    std::ifstream vfile(g_voices_path, std::ios::binary);
    if (vfile.is_open()) {
        char magic[4];
        vfile.read(magic, 4);
        if (strncmp(magic, "KOKO", 4) == 0) {
            uint32_t num_voices = 0;
            vfile.read(reinterpret_cast<char*>(&num_voices), 4);
            
            size_t voice_block_size = 32 + (511 * 256 * 4);
            char vname[32];
            
            // Default to first voice if not found, or use the target voice
            const char* target_voice = voice_name ? voice_name : "af";
            
            for (uint32_t i = 0; i < num_voices; i++) {
                vfile.read(vname, 32);
                if (strncmp(vname, target_voice, strlen(target_voice)) == 0) {
                    // Found voice! Clamp seq_len
                    int64_t safe_seq_len = seq_len;
                    if (safe_seq_len > 510) safe_seq_len = 510;
                    
                    // Seek to the exact 256-d slice for this sequence length
                    // Offset: (safe_seq_len * 256 * 4)
                    size_t slice_offset = safe_seq_len * 256 * 4;
                    vfile.seekg(slice_offset, std::ios::cur);
                    
                    // Read 256 floats
                    vfile.read(reinterpret_cast<char*>(style.data()), 256 * sizeof(float));
                    break;
                } else {
                    // Skip this voice's float data
                    vfile.seekg(511 * 256 * 4, std::ios::cur);
                }
            }
        }
    }

    // Style Tensor
    std::vector<int64_t> style_shape = {1, 256};
    Ort::Value style_tensor = Ort::Value::CreateTensor<float>(
        memory_info, style.data(), style.size(), style_shape.data(), style_shape.size());

    // Speed Tensor
    std::vector<float> speed = {speed_val};
    std::vector<int64_t> speed_shape = {1};
    Ort::Value speed_tensor = Ort::Value::CreateTensor<float>(
        memory_info, speed.data(), speed.size(), speed_shape.data(), speed_shape.size());

    const char* input_names[] = {"input_ids", "style", "speed"};
    Ort::Value input_tensors[] = {std::move(tokens_tensor), std::move(style_tensor), std::move(speed_tensor)};

    // Run inference
    try {
        const char* output_names[] = {"waveform"};
        auto output_tensors = g_ort_session->Run(
            Ort::RunOptions{nullptr}, 
            input_names, 
            input_tensors, 
            3, 
            output_names, 
            1
        );
        
        if (!output_tensors.empty()) {
            float* audio_data = output_tensors[0].GetTensorMutableData<float>();
            size_t audio_len = output_tensors[0].GetTensorTypeAndShapeInfo().GetElementCount();

            drwav_data_format format;
            format.container = drwav_container_riff;
            format.format = DR_WAVE_FORMAT_PCM;
            format.channels = 1;
            format.sampleRate = 24000;
            format.bitsPerSample = 16;

            int16_t* pcm_data = new int16_t[audio_len];
            for (size_t i = 0; i < audio_len; i++) {
                float sample = audio_data[i];
                if (sample > 1.0f) sample = 1.0f;
                if (sample < -1.0f) sample = -1.0f;
                pcm_data[i] = (int16_t)(sample * 32767.0f);
            }

            drwav wav;
            void* pWavData = nullptr;
            size_t wavDataSize = 0;
            if (drwav_init_memory_write_sequential_pcm_frames(&wav, &pWavData, &wavDataSize, &format, audio_len, nullptr)) {
                drwav_write_pcm_frames(&wav, audio_len, pcm_data);
                drwav_uninit(&wav);
                
                std::ofstream outfile(output_wav_path, std::ios::binary);
                if (outfile) {
                    outfile.write(reinterpret_cast<const char*>(pWavData), wavDataSize);
                    outfile.close();
                    printf("[Kokoro C++] Success: wrote %zu samples to %s\n", audio_len, output_wav_path);
                    drwav_free(pWavData, nullptr);
                    delete[] pcm_data;
                    
                    return 0; // Success
                } else {
                    printf("[Kokoro C++] Error: failed to open output file %s for writing\n", output_wav_path);
                    drwav_free(pWavData, nullptr);
                    delete[] pcm_data;
                    
                    return -5;
                }
            } else {
                delete[] pcm_data;
                printf("[Kokoro C++] Error: drwav_init_memory_write_sequential_pcm_frames failed\n");
                
                return -5; // File write failed
            }
        } else {
            printf("[Kokoro C++] Error: output_tensors is empty\n");
            
        }
    } catch (const Ort::Exception& e) {
        printf("[Kokoro C++] Exception during ONNX Run: %s\n", e.what());
        
        return -4; // Inference failed
    } catch (const std::exception& e) {
        printf("[Kokoro C++] Standard exception: %s\n", e.what());
        
        return -4;
    } catch (...) {
        printf("[Kokoro C++] Unknown exception during inference\n");
        
        return -4;
    }
    
    printf("[Kokoro C++] Error: Unknown failure at end of function\n");
    
    return -6; // Unknown failure
}

FFI_PLUGIN_EXPORT void kokoro_free() {
    g_initialized = false;
    if (g_ort_session) { delete g_ort_session; g_ort_session = nullptr; }
    if (g_ort_env) { delete g_ort_env; g_ort_env = nullptr; }
}

FFI_PLUGIN_EXPORT void kokoro_dummy_prevent_strip() {
    // This is intentionally left empty. 
    // It's called from Objective-C to prevent the linker from dead-code stripping this C++ file.
}

}
