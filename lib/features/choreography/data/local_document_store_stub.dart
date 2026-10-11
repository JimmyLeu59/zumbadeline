import 'dart:typed_data';

Future<String> saveLocalDocument(
  String trackId,
  String extension,
  Uint8List bytes,
) => throw UnsupportedError('Le stockage local n’est pas disponible sur cette plateforme.');

Future<Uint8List> readLocalDocument(String path) =>
    throw UnsupportedError('Le stockage local n’est pas disponible sur cette plateforme.');

Future<void> deleteLocalDocument(String path) =>
    throw UnsupportedError('Le stockage local n’est pas disponible sur cette plateforme.');
