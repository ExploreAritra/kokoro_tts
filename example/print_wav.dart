import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) return;
  final file = File(args[0]);
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  print("Bytes: ${bytes.take(64).toList()}");
}
