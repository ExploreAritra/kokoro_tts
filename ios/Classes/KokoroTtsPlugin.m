#import "KokoroTtsPlugin.h"

// Define C function prototypes for all exported functions
#ifdef __cplusplus
extern "C" {
#endif
    int kokoro_init(const char* model_path, const char* voices_path, const char* espeak_data_path);
    int kokoro_is_initialized(void);
    int kokoro_synthesize(const char* text, const char* voice_name, const char* output_wav_path);
    void kokoro_free(void);
#ifdef __cplusplus
}
#endif

@implementation KokoroTtsPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"kokoro_tts_pointers"
            binaryMessenger:[registrar messenger]];
  KokoroTtsPlugin* instance = [[KokoroTtsPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getFuncAddrs" isEqualToString:call.method]) {
      result(@{
          @"init": @((int64_t)&kokoro_init),
          @"is_initialized": @((int64_t)&kokoro_is_initialized),
          @"synthesize": @((int64_t)&kokoro_synthesize),
          @"free": @((int64_t)&kokoro_free),
      });
  } else {
      result(FlutterMethodNotImplemented);
  }
}
@end
