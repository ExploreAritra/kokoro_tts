import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kokoro_tts/kokoro_tts.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:dio/dio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
    final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  await SoLoud.instance.init();

  runApp(const KokoroShowcaseApp());
}

class KokoroShowcaseApp extends StatelessWidget {
  const KokoroShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kokoro TTS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0C29),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: const KokoroHome(),
    );
  }
}

class KokoroHome extends StatefulWidget {
  const KokoroHome({super.key});

  @override
  State<KokoroHome> createState() => _KokoroHomeState();
}

class _KokoroHomeState extends State<KokoroHome> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController(text: "Hello from Kokoro TTS! This is a completely local, hardware-accelerated text-to-speech engine running right here on your device.");
  
  String _selectedVoice = 'af_bella';
  final List<String> _voices = [
    'af', 'af_alloy', 'af_aoede', 'af_bella', 'af_heart', 'af_jessica', 'af_kore', 'af_nicole', 'af_nova', 'af_river', 'af_sarah', 'af_sky',
    'am_adam', 'am_echo', 'am_eric', 'am_fenrir', 'am_liam', 'am_michael', 'am_onyx', 'am_puck', 'am_santa',
    'bf_alice', 'bf_emma', 'bf_isabella', 'bf_lily',
    'bm_daniel', 'bm_fable', 'bm_george', 'bm_lewis',
    'ef_dora', 'em_alex', 'em_santa',
    'ff_siwis',
    'hf_alpha', 'hf_beta', 'hm_omega', 'hm_psi',
    'if_sara', 'im_nicola',
    'jf_alpha', 'jf_gongitsune', 'jf_nezumi', 'jf_tebukuro', 'jm_kumo',
    'pf_dora', 'pm_alex', 'pm_santa',
    'zf_xiaobei', 'zf_xiaoni', 'zf_xiaoxiao', 'zf_xiaoyi', 'zm_yunjian', 'zm_yunxi', 'zm_yunxia', 'zm_yunyang'
  ];

  bool _isInitializing = true;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _isSynthesizing = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  String _statusMessage = "Loading neural networks...";
  List<String> _generatedWavPaths = [];
  
  double _targetSpeed = 1.0;
  double _targetPitch = 1.0;
  double _nativeSpeed = 1.0;
  
  StreamSubscription<String>? _synthesizeSubscription;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Audio queue state
  final Queue<AudioSource> _audioQueue = Queue<AudioSource>();
  SoundHandle? _currentHandle;
  AudioSource? _currentSource;
  bool _isQueueProcessing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initEngine();
  }

  Future<String> _downloadOrGetFile(String fileName) async {
    final supportDir = await getApplicationSupportDirectory();
    final file = File('${supportDir.path}/$fileName');
    if (await file.exists()) return file.path;
    
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = "Downloading $fileName...";
    });
    
    final url = "https://github.com/ExploreAritra/kokoro_tts/releases/download/v1.0.0-models/$fileName";
    try {
      await Dio().download(
        url, 
        file.path,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _downloadProgress = received / total;
              _statusMessage = "Downloading $fileName... ${(_downloadProgress * 100).toStringAsFixed(1)}%";
            });
          }
        },
      );
    } catch (e) {
      if (await file.exists()) await file.delete();
      throw Exception("Failed to download $fileName: $e");
    }
    
    setState(() {
      _isDownloading = false;
    });
    return file.path;
  }

  Future<void> _extractEspeakData() async {
    final supportDir = await getApplicationSupportDirectory();
    final espeakDataPath = '${supportDir.path}/assets/espeak-ng-data';
    
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final espeakAssets = manifest.listAssets().where((String key) => key.startsWith('assets/espeak-ng-data/') && !key.contains('.DS_Store'));

    int copiedCount = 0;
    for (String assetPath in espeakAssets) {
      final file = File('${supportDir.path}/$assetPath');
      if (!await file.exists()) {
        final byteData = await rootBundle.load(assetPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
        copiedCount++;
      }
    }
    print("Flutter: Checked espeak-ng-data, copied $copiedCount new files.");
    
    // Check if phontab exists
    final phontabFile = File('${supportDir.path}/assets/espeak-ng-data/phontab');
    print("Flutter: phontab exists on device: ${await phontabFile.exists()}");
  }

  Future<void> _initEngine() async {
    try {
      final modelPath = await _downloadOrGetFile('kokoro_model.onnx');
      final voicesPath = await _downloadOrGetFile('voices_flat.bin');
      await _extractEspeakData();
      final supportDir = await getApplicationSupportDirectory();
      final espeakDataPath = '${supportDir.path}/assets';
      
      print("Calling KokoroTts.init...");
      final initOk = await KokoroTts.init(modelPath, voicesPath, espeakDataPath);
      print("KokoroTts.init returned: $initOk");
      setState(() {
        _isInitializing = false;
        _statusMessage = initOk ? "Engine Ready" : "Initialization Failed";
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _statusMessage = "Error: $e";
      });
    }
  }

  void _processQueue() async {
    if (_isQueueProcessing) return;
    _isQueueProcessing = true;
    
    while (_audioQueue.isNotEmpty) {
      if (!mounted) break;
      
      _currentSource = _audioQueue.removeFirst();
      
      try {
        try {
          _currentSource!.filters.pitchShiftFilter.activate();
        } catch (_) {}
        _currentHandle = SoLoud.instance.play(_currentSource!);
        
        // Apply initial effects
        SoLoud.instance.setRelativePlaySpeed(_currentHandle!, _targetSpeed / _nativeSpeed);
        if (_currentHandle != null) {
          _currentSource!.filters.pitchShiftFilter.shift(soundHandle: _currentHandle).value = _targetPitch;
        }

        setState(() {
          _isPlaying = true;
          _isPaused = false;
        });

        // Wait for sound to finish playing
        final completer = Completer<void>();
        final sub = _currentSource!.soundEvents.listen((event) {
           if (event.event == SoundEventType.soundDisposed || event.event == SoundEventType.handleIsNoMoreValid) {
              if (!completer.isCompleted) completer.complete();
           }
        });

        await completer.future;
        sub.cancel();
      } catch (e) {
        print("Flutter: Error playing sound: $e");
      }
      
      // Cleanup source
      if (_currentSource != null) {
        await SoLoud.instance.disposeSource(_currentSource!);
        _currentSource = null;
      }
      _currentHandle = null;
    }
    
    _isQueueProcessing = false;
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _isPaused = false;
        if (!_isSynthesizing) {
          _statusMessage = "Synthesis Complete";
        }
      });
    }
  }

  Future<void> _stopAudio() async {
    _synthesizeSubscription?.cancel();
    setState(() {
      _isSynthesizing = false;
      _isPlaying = false;
      _isPaused = false;
      _statusMessage = "Stopped";
    });
    
    _audioQueue.clear();
    SoLoud.instance.disposeAllSources();
    _currentHandle = null;
    if (_currentSource != null) {
      await SoLoud.instance.disposeSource(_currentSource!);
      _currentSource = null;
    }
  }

  Future<void> _synthesizeAndPlay() async {
    if (_textController.text.trim().isEmpty) return;
    
    await _stopAudio();
    _generatedWavPaths.clear();

    setState(() {
      _isSynthesizing = true;
      _statusMessage = "Synthesizing stream...";
    });

    try {
      _nativeSpeed = _targetSpeed;
      
      _synthesizeSubscription = KokoroTts.synthesizeStream(
        _textController.text, 
        _selectedVoice,
        speed: _nativeSpeed
      ).listen(
        (String outputPath) async {
          print("Flutter: New audio chunk received: $outputPath");
          _generatedWavPaths.add(outputPath);
          try {
            await Future.delayed(const Duration(milliseconds: 10)); // Give filesystem time to flush
            final fileBytes = await File(outputPath).readAsBytes();
            final source = await SoLoud.instance.loadMem(outputPath, fileBytes);
            _audioQueue.add(source);
            if (!_isQueueProcessing) {
              _processQueue();
            }
          } catch (e) {
            print("Flutter: Failed to load $outputPath: $e");
          }
        },
        onDone: () {
          print("Flutter: Synthesis stream done.");
          setState(() {
            _isSynthesizing = false;
            if (!_isPlaying) {
              _statusMessage = "Synthesis Complete";
            }
          });
        },
        onError: (e) {
          setState(() {
            _isSynthesizing = false;
            _statusMessage = "Error: $e";
          });
        }
      );
    } catch (e) {
      setState(() {
        _statusMessage = "Error: $e";
        _isSynthesizing = false;
      });
    }
  }

  @override
  void dispose() {
    _synthesizeSubscription?.cancel();
    _pulseController.dispose();
    _textController.dispose();
    _stopAudio();
    SoLoud.instance.deinit();
    super.dispose();
  }

  Future<void> _stitchAndShareAudio(BuildContext context) async {
    if (_generatedWavPaths.isEmpty) return;
    
    setState(() {
      _statusMessage = "Preparing audio file...";
    });

    try {
      final supportDir = await getApplicationSupportDirectory();
      final finalPath = '${supportDir.path}/final_synthesis.wav';
      final finalFile = File(finalPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }

      final builder = BytesBuilder();
      List<int>? header;
      int totalPcmBytes = 0;

      for (int i = 0; i < _generatedWavPaths.length; i++) {
        final chunkFile = File(_generatedWavPaths[i]);
        if (!await chunkFile.exists()) continue;
        
        final bytes = await chunkFile.readAsBytes();
        if (bytes.length < 44) continue;
        
        if (i == 0) {
          header = bytes.sublist(0, 44);
        }
        
        final pcmData = bytes.sublist(44);
        builder.add(pcmData);
        totalPcmBytes += pcmData.length;
      }

      if (header != null) {
        final byteData = ByteData(44);
        for (int i = 0; i < 44; i++) {
          byteData.setUint8(i, header[i]);
        }
        // ChunkSize: 36 + totalPcmBytes
        byteData.setUint32(4, 36 + totalPcmBytes, Endian.little);
        // Subchunk2Size: totalPcmBytes
        byteData.setUint32(40, totalPcmBytes, Endian.little);

        final finalSink = finalFile.openWrite();
        finalSink.add(byteData.buffer.asUint8List());
        finalSink.add(builder.takeBytes());
        await finalSink.flush();
        await finalSink.close();
      }

      setState(() {
        _statusMessage = "Ready for share";
      });

      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(finalPath)], 
        text: "Generated with Kokoro TTS",
        sharePositionOrigin: box != null ? (box.localToGlobal(Offset.zero) & box.size) : null,
      );
      
      setState(() {
        _statusMessage = "Synthesis Complete";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Error exporting: $e";
      });
    }
  }

  Widget _buildGlassmorphicContainer({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
        children: [
          // Dynamic Background Gradients
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0xFF8E2DE2), Colors.transparent]),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0xFF4A00E0), Colors.transparent]),
              ),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      "Kokoro AI",
                      style: GoogleFonts.outfit(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "On-Device Neural Text-to-Speech",
                      style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    
                    // Voice Selector
                    _buildGlassmorphicContainer(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedVoice,
                          dropdownColor: const Color(0xFF1A1A2E),
                          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                          isExpanded: true,
                          style: const TextStyle(fontSize: 18, color: Colors.white),
                          items: _voices.map((String voice) {
                            return DropdownMenuItem<String>(
                              value: voice,
                              child: Row(
                                children: [
                                  const Icon(Icons.record_voice_over, color: Color(0xFF8E2DE2), size: 20),
                                  const SizedBox(width: 12),
                                  Text(voice.replaceAll('_', ' ').toUpperCase(), 
                                       style: const TextStyle(fontWeight: FontWeight.w500)),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedVoice = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Speed and Pitch Sliders
                    _buildGlassmorphicContainer(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Speed: ${_targetSpeed.toStringAsFixed(1)}x", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                              Slider(
                                value: _targetSpeed,
                                min: 0.5,
                                max: 2.0,
                                divisions: 15,
                                activeColor: const Color(0xFF8E2DE2),
                                onChanged: (value) {
                                  setState(() {
                                    _targetSpeed = value;
                                    if (_currentHandle != null) {
                                      SoLoud.instance.setRelativePlaySpeed(_currentHandle!, _targetSpeed / _nativeSpeed);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Pitch: ${_targetPitch.toStringAsFixed(1)}x", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                              Slider(
                                value: _targetPitch,
                                min: 0.5,
                                max: 2.0,
                                divisions: 15,
                                activeColor: const Color(0xFF8E2DE2),
                                onChanged: (value) {
                                  setState(() {
                                    _targetPitch = value;
                                    if (_currentHandle != null && _currentSource != null) {
                                      _currentSource!.filters.pitchShiftFilter.shift(soundHandle: _currentHandle).value = value;
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Text Input
                    SizedBox(
                      height: 200,
                      child: _buildGlassmorphicContainer(
                        padding: const EdgeInsets.all(0),
                        child: TextField(
                          controller: _textController,
                          maxLines: null,
                          expands: true,
                          style: const TextStyle(fontSize: 18, height: 1.5, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: "Type something to generate speech...",
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(24),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Status Text
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _statusMessage,
                        key: ValueKey(DateTime.now().millisecondsSinceEpoch.toString() + _statusMessage),
                        style: TextStyle(
                          fontSize: 14,
                          color: _statusMessage.contains("Failed") || _statusMessage.contains("Error")
                              ? Colors.redAccent
                              : Colors.white.withOpacity(0.7),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Action Button
                    if (_isSynthesizing || _isPlaying || _isPaused)
                      Row(
                        children: [
                          Expanded(
                            child: ScaleTransition(
                              scale: _isSynthesizing || _isPlaying || _isPaused ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                              child: GestureDetector(
                                onTap: _isInitializing || _isSynthesizing
                                    ? null
                                    : () {
                                        if (_isPlaying) {
                                          SoLoud.instance.setPause(_currentHandle!, true);
                                          setState(() {
                                            _isPlaying = false;
                                            _isPaused = true;
                                          });
                                        } else if (_isPaused) {
                                          SoLoud.instance.setPause(_currentHandle!, false);
                                          setState(() {
                                            _isPlaying = true;
                                            _isPaused = false;
                                          });
                                        }
                                      },
                                child: Container(
                                  height: 64,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(32),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF8E2DE2).withOpacity(0.4),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      )
                                    ],
                                  ),
                                  child: Center(
                                    child: _isInitializing || _isSynthesizing
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                          )
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                                              const SizedBox(width: 8),
                                              Text(
                                                _isPlaying ? "Pause" : "Resume",
                                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: _stopAudio,
                            child: Container(
                              height: 64,
                              width: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.redAccent.withOpacity(0.1),
                                border: Border.all(color: Colors.redAccent.withOpacity(0.4), width: 1.5),
                              ),
                              child: const Center(
                                child: Icon(Icons.stop_rounded, color: Colors.redAccent, size: 28),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: ScaleTransition(
                              scale: const AlwaysStoppedAnimation(1.0),
                              child: GestureDetector(
                                onTap: _isInitializing ? null : _synthesizeAndPlay,
                                child: Container(
                                  height: 64,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(32),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF8E2DE2).withOpacity(0.4),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      )
                                    ],
                                  ),
                                  child: const Center(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.graphic_eq_rounded, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text(
                                          "Synthesize",
                                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_generatedWavPaths.isNotEmpty) ...[
                            const SizedBox(width: 16),
                            GestureDetector(
                              onTap: () => _stitchAndShareAudio(context),
                              child: Container(
                                height: 64,
                                width: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00C9FF).withOpacity(0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    )
                                  ],
                                ),
                                child: const Center(
                                  child: Icon(Icons.download_rounded, color: Colors.white, size: 28),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    if (_isDownloading)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _downloadProgress,
                            backgroundColor: Colors.white.withOpacity(0.1),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8E2DE2)),
                            minHeight: 6,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
