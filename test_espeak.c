#include <stdio.h>
#include "src/espeak-ng/src/include/espeak-ng/speak_lib.h"

int main() {
    espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, NULL, 0);
    espeak_SetVoiceByName("en-us");
    
    const char* text = "Hello from Kokoro TTS.";
    const void* ptr = text;
    const char* phonemes = espeak_TextToPhonemes(&ptr, 0, 2); // 2 = espeakPHONEMES_IPA
    printf("Phonemes: %s\n", phonemes ? phonemes : "NULL");
    return 0;
}
