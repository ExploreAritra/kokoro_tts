import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/example/lib/main.dart');
  var content = file.readAsStringSync();
  
  // Add audio_session import
  if (!content.contains("import 'package:audio_session/audio_session.dart';")) {
    content = content.replaceFirst("import 'package:flutter_soloud/flutter_soloud.dart';", "import 'package:flutter_soloud/flutter_soloud.dart';\nimport 'package:audio_session/audio_session.dart';");
  }
  
  // Add initialization
  if (!content.contains("AudioSession.instance")) {
    content = content.replaceFirst("await SoLoud.instance.init();", '''
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  await SoLoud.instance.init();
''');
  }
  
  file.writeAsStringSync(content);
  print("Patched audio session.");
}
