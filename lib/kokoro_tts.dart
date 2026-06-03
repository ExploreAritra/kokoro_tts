import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

import 'kokoro_tts_bindings_generated.dart';

import 'package:flutter/services.dart';

const String _libName = 'kokoro_tts';

/// Custom class wrapper for KokoroTts FFI
class KokoroTts {
  /// Base URL of the Gradio space running Kokoro-TTS.
  static String baseUrl = 'https://pendrokar-kokoro-tts.hf.space';

  /// Enable on-the-fly speech downloads.
  static bool enableOnlineDownload = false;

  /// Enable local caching of downloaded speech files.
  static bool enableCaching = true;

  /// Initialize the Kokoro TTS model and voice settings on-device.
  static Future<bool> init(String modelPath, String voicesPath, String espeakDataPath) async {
    Map<String, int>? funcAddrs;
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        final Map<dynamic, dynamic> result = await const MethodChannel('kokoro_tts_pointers').invokeMethod('getFuncAddrs');
        funcAddrs = result.cast<String, int>();
      } catch (e) {
        developer.log("KokoroTts: Failed to get func addrs from MethodChannel: $e");
      }
    }
    
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextRequestId++;
    final _InitRequest request = _InitRequest(requestId, modelPath, voicesPath, espeakDataPath, funcAddrs);
    final Completer<bool> completer = Completer<bool>();
    _initRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  /// Synthesize text to a WAV file path on-device.
  /// If online downloading is enabled, queries the online Space first.
  /// Otherwise, falls back to the native C++ FFI synthesis.
  static Future<int> synthesize(String text, String voiceName, String outputWavPath, {double speed = 1.0}) async {
    if (enableOnlineDownload) {
      try {
        final cacheFile = enableCaching ? await _getCacheFile(text, voiceName, speed) : null;
        if (cacheFile != null && await cacheFile.exists()) {
          final destFile = File(outputWavPath);
          await cacheFile.copy(destFile.path);
          return 0; // Success (cache hit)
        }

        // Try downloading online
        final downloadPath = await _downloadOnline(text, voiceName, speed);
        if (downloadPath != null) {
          final tempDownloadedFile = File(downloadPath);
          if (await tempDownloadedFile.exists()) {
            // Save to cache
            if (cacheFile != null) {
              await cacheFile.parent.create(recursive: true);
              await tempDownloadedFile.copy(cacheFile.path);
            }
            // Copy to output path
            final destFile = File(outputWavPath);
            await tempDownloadedFile.copy(destFile.path);
            // Clean up temp downloaded file
            try {
              await tempDownloadedFile.delete();
            } catch (_) {}
            return 0; // Success
          }
        }
      } catch (e) {
        developer.log("KokoroTts: Online download failed ($e), falling back to offline FFI...");
      }
    }

    // Fallback to FFI helper isolate
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextRequestId++;
    final _SynthesizeRequest request = _SynthesizeRequest(requestId, text, voiceName, outputWavPath, speed);
    final Completer<int> completer = Completer<int>();
    _synthesizeRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  /// Splits text into sentences and yields the file path for each synthesized audio chunk sequentially.
  static Stream<String> synthesizeStream(String text, String voiceName, {double speed = 1.0}) async* {
    final RegExp sentenceSplitter = RegExp(r'(?<=[.!?\n])\s+');
    // For very long contiguous text without punctuation, this might still generate large chunks, 
    // but works perfectly for standard text.
    final List<String> sentences = text.split(sentenceSplitter).where((s) => s.trim().isNotEmpty).toList();
    
    final tempDir = Directory.systemTemp;
    int chunkIndex = 0;
    
    for (String sentence in sentences) {
      final outputPath = '${tempDir.path}/kokoro_chunk_${DateTime.now().millisecondsSinceEpoch}_$chunkIndex.wav';
      final result = await synthesize(sentence.trim(), voiceName, outputPath, speed: speed);
      print("KokoroTts synthesize result: $result");
      
      if (result == 0) {
        final file = File(outputPath);
        if (await file.exists()) {
          print("KokoroTts generated file size: ${await file.length()} bytes at $outputPath");
        } else {
          print("KokoroTts generated file does not exist at $outputPath");
        }
        yield outputPath;
      } else {
        String errorMsg = "Unknown error";
        switch (result) {
          case -1: errorMsg = "Not initialized or ONNX session missing"; break;
          case -2: errorMsg = "Text or output path is null"; break;
          case -4: errorMsg = "Inference failed (ONNX Error)"; break;
          case -5: errorMsg = "dr_wav failed to open file for writing"; break;
          case -6: errorMsg = "Unknown failure in C++ execution"; break;
          case -10: errorMsg = "ONNX initialization exception"; break;
          case -11: errorMsg = "espeak_Initialize failed"; break;
        }
        throw Exception("Synthesis failed with result code $result: $errorMsg");
      }
      chunkIndex++;
    }
  }

  /// Free all resources loaded by the Kokoro TTS engine.
  static Future<void> free() async {
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextRequestId++;
    final _FreeRequest request = _FreeRequest(requestId);
    final Completer<void> completer = Completer<void>();
    _freeRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  static Future<File?> _getCacheFile(String text, String voice, double speed) async {
    try {
      final cleanText = text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      final prefix = cleanText.length > 20 ? cleanText.substring(0, 20) : cleanText;
      final hash = text.hashCode.abs();
      final filename = '${prefix}_${voice}_${speed.toStringAsFixed(1)}_$hash.wav';
      
      final tempDir = Directory.systemTemp;
      final cacheDir = Directory('${tempDir.path}/kokoro_tts_cache');
      return File('${cacheDir.path}/$filename');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _downloadOnline(String text, String voice, double speed) async {
    HttpClient? httpClient;
    try {
      httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      
      final predictUri = Uri.parse('$baseUrl/gradio_api/api/predict');
      final request = await httpClient.postUrl(predictUri);
      
      request.headers.contentType = ContentType.json;
      request.headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      request.headers.set('accept-encoding', 'identity');
      request.headers.set('accept', '*/*');
      
      final requestBody = jsonEncode({
        "data": [
          text,
          voice,
          speed,
        ]
      });
      
      request.write(requestBody);
      final response = await request.close();
      
      if (response.statusCode != 200) {
        throw HttpException('Predict API returned status code ${response.statusCode}');
      }
      
      final responseBody = await response.transform(utf8.decoder).join();
      final Map<String, dynamic> decoded = jsonDecode(responseBody);
      
      final List<dynamic>? data = decoded['data'];
      if (data == null || data.isEmpty) {
        throw const FormatException('Invalid or empty Gradio predict response data');
      }
      
      final String? fileUrl = data[0]['url'];
      if (fileUrl == null || fileUrl.isEmpty) {
        throw const FormatException('No file URL found in response data');
      }
      
      // Download the WAV file
      final downloadUri = Uri.parse(fileUrl);
      final downloadRequest = await httpClient.getUrl(downloadUri);
      downloadRequest.headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      downloadRequest.headers.set('accept-encoding', 'identity');
      downloadRequest.headers.set('accept', '*/*');
      final downloadResponse = await downloadRequest.close();
      
      if (downloadResponse.statusCode != 200) {
        throw HttpException('WAV download returned status code ${downloadResponse.statusCode}');
      }
      
      final tempDir = Directory.systemTemp;
      final tempFilePath = '${tempDir.path}/kokoro_temp_${DateTime.now().millisecondsSinceEpoch}.wav';
      final tempFile = File(tempFilePath);
      
      final fileSink = tempFile.openWrite();
      await downloadResponse.pipe(fileSink);
      await fileSink.flush();
      await fileSink.close();
      
      return tempFilePath;
    } catch (e) {
      developer.log('KokoroTts: _downloadOnline error: $e');
      return null;
    } finally {
      httpClient?.close();
    }
  }
}

// Request and response models for Isolate communication
class _InitRequest {
  final int id;
  final String modelPath;
  final String voicesPath;
  final String espeakDataPath;
  final Map<String, int>? funcAddrs;
  _InitRequest(this.id, this.modelPath, this.voicesPath, this.espeakDataPath, this.funcAddrs);
}

class _InitResponse {
  final int id;
  final bool success;
  _InitResponse(this.id, this.success);
}

class _SynthesizeRequest {
  final int id;
  final String text;
  final String voiceName;
  final String outputWavPath;
  final double speed;
  _SynthesizeRequest(this.id, this.text, this.voiceName, this.outputWavPath, this.speed);
}

class _SynthesizeResponse {
  final int id;
  final int statusCode;
  _SynthesizeResponse(this.id, this.statusCode);
}

class _FreeRequest {
  final int id;
  _FreeRequest(this.id);
}

class _FreeResponse {
  final int id;
  _FreeResponse(this.id);
}

int _nextRequestId = 0;
final Map<int, Completer<bool>> _initRequests = {};
final Map<int, Completer<int>> _synthesizeRequests = {};
final Map<int, Completer<void>> _freeRequests = {};

Future<SendPort> _helperIsolateSendPort = () async {
  final Completer<SendPort> completer = Completer<SendPort>();

  final ReceivePort receivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is SendPort) {
        completer.complete(data);
        return;
      }
      if (data is _InitResponse) {
        final Completer<bool>? completer = _initRequests.remove(data.id);
        completer?.complete(data.success);
        return;
      }
      if (data is _SynthesizeResponse) {
        final Completer<int>? completer = _synthesizeRequests.remove(data.id);
        completer?.complete(data.statusCode);
        return;
      }
      if (data is _FreeResponse) {
        final Completer<void>? completer = _freeRequests.remove(data.id);
        completer?.complete(null);
        return;
      }
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  await Isolate.spawn((SendPort sendPort) async {
    KokoroTtsBindings? bindings;
    
    final ReceivePort helperReceivePort = ReceivePort()
      ..listen((dynamic data) {
        if (data is _InitRequest) {
          if (bindings == null) {
            if (data.funcAddrs != null) {
              bindings = KokoroTtsBindings.fromLookup(<T extends ffi.NativeType>(String symbolName) {
                final address = data.funcAddrs![symbolName.replaceAll('kokoro_', '')];
                if (address != null) {
                  return ffi.Pointer.fromAddress(address).cast<T>();
                }
                throw ArgumentError('Symbol not found: $symbolName');
              });
            } else {
              final ffi.DynamicLibrary dylib = () {
                if (Platform.isMacOS || Platform.isIOS) return ffi.DynamicLibrary.process();
                if (Platform.isAndroid || Platform.isLinux) return ffi.DynamicLibrary.open('lib$_libName.so');
                if (Platform.isWindows) return ffi.DynamicLibrary.open('$_libName.dll');
                throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
              }();
              bindings = KokoroTtsBindings(dylib);
            }
          }
          
          final modelPathPtr = data.modelPath.toNativeUtf8().cast<ffi.Char>();
          final voicesPathPtr = data.voicesPath.toNativeUtf8().cast<ffi.Char>();
          final espeakDataPathPtr = data.espeakDataPath.toNativeUtf8().cast<ffi.Char>();
          final int result = bindings!.kokoro_init(modelPathPtr, voicesPathPtr, espeakDataPathPtr); print("kokoro_init returned $result");
          calloc.free(modelPathPtr);
          calloc.free(voicesPathPtr);
          calloc.free(espeakDataPathPtr);
          
          sendPort.send(_InitResponse(data.id, result == 1));
          return;
        }
        if (data is _SynthesizeRequest) {
          final textPtr = data.text.toNativeUtf8().cast<ffi.Char>();
          final voiceNamePtr = data.voiceName.toNativeUtf8().cast<ffi.Char>();
          final outputWavPathPtr = data.outputWavPath.toNativeUtf8().cast<ffi.Char>();
          
          final int result = bindings!.kokoro_synthesize(textPtr, voiceNamePtr, outputWavPathPtr, data.speed);
          
          calloc.free(textPtr);
          calloc.free(voiceNamePtr);
          calloc.free(outputWavPathPtr);
          
          sendPort.send(_SynthesizeResponse(data.id, result));
          return;
        }
        if (data is _FreeRequest) {
          bindings?.kokoro_free();
          sendPort.send(_FreeResponse(data.id));
          return;
        }
        throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
      });

    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  return completer.future;
}();
