import 'dart:typed_data';

import 'local_document_store_stub.dart'
    if (dart.library.io) 'local_document_store_io.dart' as platform;

class LocalDocumentStore {
  const LocalDocumentStore();

  Future<String> save({
    required String trackId,
    required String extension,
    required Uint8List bytes,
  }) => platform.saveLocalDocument(trackId, extension, bytes);

  Future<Uint8List> read(String path) => platform.readLocalDocument(path);

  Future<void> delete(String path) => platform.deleteLocalDocument(path);
}
