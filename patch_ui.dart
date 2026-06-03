import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/example/lib/main.dart');
  var content = file.readAsStringSync();
  
  // Unfocus when tapped outside
  content = content.replaceFirst('''
  Widget build(BuildContext context) {
    return Scaffold(
''', '''
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
''');

  // Add closing parenthesis to the widget tree
  content = content.replaceFirst('''
    );
  }
}
''', '''
      ),
    );
  }
}
''');

  // Fix UI states for buttons
  content = content.replaceFirst('''
                          if (_isSynthesizing) ...[
''', '''
                          if (_isSynthesizing || _isPlaying || _isPaused) ...[
''');

  // Fix Pause / Resume / Synthesis
  content = content.replaceFirst('''
                                        _isPaused ? Icons.play_arrow : Icons.pause,
''', '''
                                        _isPaused ? Icons.play_arrow : Icons.pause,
''');

  file.writeAsStringSync(content);
  print("Patched UI");
}
