import 'dart:io';

void main() {
  final file = File('/Users/admin/StudioProjects/kokoro_tts/src/kokoro_tts.cpp');
  var content = file.readAsStringSync();
  
  content = content.replaceFirst('''
    } catch (const Ort::Exception& e) {
        return -10; // ONNX Error
    }
''', '''
    } catch (const Ort::Exception& e) {
        printf("[Kokoro C++] ONNX Exception: %s\\n", e.what());
        fflush(stdout);
        return -10; // ONNX Error
    } catch (const std::exception& e) {
        printf("[Kokoro C++] std::exception: %s\\n", e.what());
        fflush(stdout);
        return -10;
    } catch (...) {
        printf("[Kokoro C++] Unknown exception in ONNX init\\n");
        fflush(stdout);
        return -10;
    }
''');

  file.writeAsStringSync(content);
}
