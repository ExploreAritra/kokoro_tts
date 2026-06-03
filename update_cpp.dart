import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/src/kokoro_tts.cpp');
  var content = file.readAsStringSync();
  
  content = content.replaceAll(
    '''
            drwav wav;
            if (drwav_init_file_write(&wav, output_wav_path, &format, nullptr)) {
                drwav_write_pcm_frames(&wav, audio_len, pcm_data);
                drwav_uninit(&wav);
                delete[] pcm_data;
                printf("[Kokoro C++] Success: wrote %zu samples to %s\\n", audio_len, output_wav_path);
                fflush(stdout);
                return 0; // Success
            } else {
                delete[] pcm_data;
                printf("[Kokoro C++] Error: drwav_init_file_write failed for %s\\n", output_wav_path);
                fflush(stdout);
                return -5; // File write failed
            }
''',
    '''
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
'''
  );
  
  file.writeAsStringSync(content);
  print("Updated cpp file.");
}
