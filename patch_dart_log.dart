import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/example/lib/main.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceFirst('''
      final initOk = await KokoroTts.init(modelPath, voicesPath, espeakDataPath);
      setState(() {
''', '''
      print("Calling KokoroTts.init...");
      final initOk = await KokoroTts.init(modelPath, voicesPath, espeakDataPath);
      print("KokoroTts.init returned: \$initOk");
      setState(() {
''');
  file.writeAsStringSync(content);
}
