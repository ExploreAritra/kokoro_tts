import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/src/kokoro_tts.cpp');
  var content = file.readAsStringSync();
  
  content = content.replaceAll(
    '''
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
                    printf("[Kokoro C++] Success: wrote %zu samples to %s\\n", audio_len, output_wav_path);
                    drwav_free(pWavData, nullptr);
                    delete[] pcm_data;
                    fflush(stdout);
                    return 0; // Success
                } else {
                    printf("[Kokoro C++] Error: failed to open output file %s for writing\\n", output_wav_path);
                    drwav_free(pWavData, nullptr);
                    delete[] pcm_data;
                    fflush(stdout);
                    return -5;
                }
            } else {
                delete[] pcm_data;
                printf("[Kokoro C++] Error: drwav_init_memory_write_sequential_pcm_frames failed\\n");
                fflush(stdout);
                return -5; // File write failed
            }
''',
    '''
            drwav_data_format format;
            format.container = drwav_container_riff;
            format.format = DR_WAVE_FORMAT_IEEE_FLOAT;
            format.channels = 1;
            format.sampleRate = 24000;
            format.bitsPerSample = 32;
            
            drwav wav;
            void* pWavData = nullptr;
            size_t wavDataSize = 0;
            if (drwav_init_memory_write_sequential_pcm_frames(&wav, &pWavData, &wavDataSize, &format, audio_len, nullptr)) {
                drwav_write_pcm_frames(&wav, audio_len, audio_data);
                drwav_uninit(&wav);
                
                std::ofstream outfile(output_wav_path, std::ios::binary);
                if (outfile) {
                    outfile.write(reinterpret_cast<const char*>(pWavData), wavDataSize);
                    outfile.close();
                    printf("[Kokoro C++] Success: wrote %zu samples to %s\\n", audio_len, output_wav_path);
                    drwav_free(pWavData, nullptr);
                    fflush(stdout);
                    return 0; // Success
                } else {
                    printf("[Kokoro C++] Error: failed to open output file %s for writing\\n", output_wav_path);
                    drwav_free(pWavData, nullptr);
                    fflush(stdout);
                    return -5;
                }
            } else {
                printf("[Kokoro C++] Error: drwav_init_memory_write_sequential_pcm_frames failed\\n");
                fflush(stdout);
                return -5; // File write failed
            }
'''
  );
  
  file.writeAsStringSync(content);
  print("Updated cpp file.");
}
