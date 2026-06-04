#include "kokoro_tts.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <string>

// --- Clause Terminator Constants from espeak-ng ---
#define CLAUSE_INTONATION_FULL_STOP 0x00000000
#define CLAUSE_INTONATION_COMMA 0x00001000
#define CLAUSE_INTONATION_QUESTION 0x00002000
#define CLAUSE_INTONATION_EXCLAMATION 0x00003000

#define CLAUSE_TYPE_CLAUSE 0x00040000
#define CLAUSE_TYPE_SENTENCE 0x00080000

#define CLAUSE_PERIOD (40 | CLAUSE_INTONATION_FULL_STOP | CLAUSE_TYPE_SENTENCE)
#define CLAUSE_COMMA (20 | CLAUSE_INTONATION_COMMA | CLAUSE_TYPE_CLAUSE)
#define CLAUSE_QUESTION (40 | CLAUSE_INTONATION_QUESTION | CLAUSE_TYPE_SENTENCE)
#define CLAUSE_EXCLAMATION (45 | CLAUSE_INTONATION_EXCLAMATION | CLAUSE_TYPE_SENTENCE)
#define CLAUSE_COLON (30 | CLAUSE_INTONATION_FULL_STOP | CLAUSE_TYPE_CLAUSE)
#define CLAUSE_SEMICOLON (30 | CLAUSE_INTONATION_COMMA | CLAUSE_TYPE_CLAUSE)
// --------------------------------------------------

#define DR_WAV_IMPLEMENTATION
#include "dr_wav.h"

// Include ONNX Runtime
#include "onnxruntime_cxx_api.h"

// Include espeak-ng
#include "espeak-ng/src/include/espeak-ng/speak_lib.h"

// Include execution providers for hardware acceleration
#ifdef __APPLE__
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#include "coreml_provider_factory.h"
#endif
#endif

#ifdef __ANDROID__
#include "nnapi_provider_factory.h"
#endif

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
        
#ifdef __APPLE__
#if TARGET_OS_IPHONE
        // CoreML dynamic shape recompilation causes massive memory leaks on iOS.
        // Disable it so ONNX Runtime falls back to CPU which handles dynamic shapes safely.
        // uint32_t coreml_flags = 0;
        // OrtSessionOptionsAppendExecutionProvider_CoreML((OrtSessionOptions*)session_options, coreml_flags);
        // LOGI("CoreML Execution Provider Appended.");
#endif
#endif

#ifdef __ANDROID__
        uint32_t nnapi_flags = 0;
        OrtSessionOptionsAppendExecutionProvider_Nnapi((OrtSessionOptions*)session_options, nnapi_flags);
        LOGI("NNAPI Execution Provider Appended.");
#endif

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

static void set_espeak_language_from_voice(const char* voice_name) {
    if (!voice_name || strlen(voice_name) == 0) return;
    
    char lang_code = voice_name[0];
    const char* espeak_voice = "en-us"; // fallback
    
    switch (lang_code) {
        case 'a': espeak_voice = "en-us"; break;
        case 'b': espeak_voice = "en-gb"; break;
        case 'e': espeak_voice = "es"; break;
        case 'f': espeak_voice = "fr-fr"; break;
        case 'h': espeak_voice = "hi"; break;
        case 'i': espeak_voice = "it"; break;
        case 'p': espeak_voice = "pt-br"; break;
        case 'z': espeak_voice = "cmn"; break;
        // 'j' for Japanese requires a separate tokenizer (like misaki) in upstream Kokoro, 
        // but espeak's 'ja' is the closest fallback for this C++ port.
        case 'j': espeak_voice = "ja"; break; 
    }
    
    espeak_SetVoiceByName(espeak_voice);
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

    set_espeak_language_from_voice(voice_name);

    // 1. Text to Phonemes via espeak-ng (using 2 for espeakPHONEMES_IPA)
    std::string all_phonemes = "";
    const char* text_ptr = text;
    while (text_ptr != nullptr && *text_ptr != '\0') {
        int terminator = 0;
        const char* phonemes = espeak_TextToPhonemesWithTerminator((const void**)&text_ptr, espeakCHARS_AUTO, 0x02, &terminator);
        if (phonemes) {
            all_phonemes += phonemes;
        }

        int punctuation = terminator & 0x000FFFFF;
        if (punctuation == CLAUSE_PERIOD) {
            all_phonemes += ".";
        } else if (punctuation == CLAUSE_QUESTION) {
            all_phonemes += "?";
        } else if (punctuation == CLAUSE_EXCLAMATION) {
            all_phonemes += "!";
        } else if (punctuation == CLAUSE_COMMA) {
            all_phonemes += ", ";
        } else if (punctuation == CLAUSE_COLON) {
            all_phonemes += ": ";
        } else if (punctuation == CLAUSE_SEMICOLON) {
            all_phonemes += "; ";
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
                LOGI("Unknown character dropped: '%s'", character.c_str());
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
