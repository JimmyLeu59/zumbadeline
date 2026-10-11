import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<Directory> _documentDirectory() async {
  final supportDirectory = await getApplicationSupportDirectory();
  final directory = Directory(
    '${supportDirectory.path}${Platform.pathSeparator}pedagogical_documents',
  );
  await directory.create(recursive: true);
  return directory;
}

Future<String> saveLocalDocument(
  String trackId,
  String extension,
  Uint8List bytes,
) async {
  final directory = await _documentDirectory();
  final safeTrackId = trackId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final file = File(
    '${directory.path}${Platform.pathSeparator}'
    '${safeTrackId}_${DateTime.now().microsecondsSinceEpoch}.$extension',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Uint8List> readLocalDocument(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw StateError('Le document local n’existe plus : $path');
  }
  return file.readAsBytes();
}

Future<void> deleteLocalDocument(String path) async {
  final directory = await _documentDirectory();
  final root = '${directory.absolute.path}${Platform.pathSeparator}';
  final file = File(path).absolute;
  if (!file.path.startsWith(root)) {
    throw ArgumentError.value(path, 'path', 'Document path is outside the app store.');
  }
  if (await file.exists()) await file.delete();
}
