import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/example/lib/main.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceFirst('''
      final supportDir = await getApplicationSupportDirectory();
      final espeakDataPath = '\${supportDir.path}/assets/espeak-ng-data';
      
      print("Calling KokoroTts.init...");
      final initOk = await KokoroTts.init(modelPath, voicesPath, espeakDataPath);
''', '''
      final supportDir = await getApplicationSupportDirectory();
      final espeakDataPath = '\${supportDir.path}/assets';
      
      print("Calling KokoroTts.init...");
      final initOk = await KokoroTts.init(modelPath, voicesPath, espeakDataPath);
''');
  file.writeAsStringSync(content);
}
