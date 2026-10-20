import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/offline_store.dart';
import '../domain/repertoire_song.dart';

class RepertoireService {
  RepertoireService(this._client, this._offlineStore);

  final SupabaseClient _client;
  final OfflineStore _offlineStore;
  static const _bucket = 'repertoire_documents';
  static const _maxDocumentSize = 20 * 1024 * 1024;
  static const _allowedExtensions = {'pdf', 'jpg', 'jpeg', 'png', 'webp'};

  Future<List<RepertoireSong>> listSongs(String activityId) async {
    final cacheKey = 'repertoire_cache:$activityId';
    if (!await _offlineStore.isOnline()) {
      final cached = _offlineStore.readJsonList(cacheKey);
      if (cached == null) {
        throw StateError('Aucun répertoire de chant n’est disponible hors ligne.');
      }
      return cached.map(RepertoireSong.fromMap).toList(growable: false);
    }
    final rows = await _client
        .from('repertoire_songs')
        .select()
        .eq('activity_id', activityId)
        .order('title');
    await _offlineStore.cacheJson(cacheKey, rows);
    return rows.map(RepertoireSong.fromMap).toList(growable: false);
  }

  Future<RepertoireSong> saveSong(RepertoireSong song) async {
    final row = await _client
        .from('repertoire_songs')
        .upsert(song.toMap())
        .select()
        .single();
    await _refreshCache(song.activityId);
    return RepertoireSong.fromMap(row);
  }

  Future<RepertoireSong> uploadDocument({
    required RepertoireSong song,
    required PlatformFile file,
  }) async {
    final extension = file.extension?.toLowerCase();
    if (extension == null || !_allowedExtensions.contains(extension)) {
      throw ArgumentError.value(file.name, 'file', 'Format de document non accepté.');
    }
    final source = file.xFile;
    final fileSize = await source.length();
    if (fileSize <= 0 || fileSize > _maxDocumentSize) {
      throw ArgumentError.value(
        fileSize,
        'file',
        'Le document doit faire moins de 20 Mo.',
      );
    }
    final bytes = await source.readAsBytes();
    if (bytes.isEmpty || bytes.length > _maxDocumentSize) {
      throw ArgumentError.value(
        bytes.length,
        'file',
        'Le document doit faire moins de 20 Mo.',
      );
    }
    final saved = song.id.isEmpty ? await saveSong(song) : song;
    final path = '${song.activityId}/${saved.id}.$extension';
    await _client.storage.from(_bucket).uploadBinary(
      path,
      Uint8List.fromList(bytes),
      fileOptions: FileOptions(
        upsert: true,
        contentType: _contentType(extension),
      ),
    );
    final updated = await _client
        .from('repertoire_songs')
        .update({'document_path': path})
        .eq('id', saved.id)
        .select()
        .single();
    await _refreshCache(song.activityId);
    return RepertoireSong.fromMap(updated);
  }

  Future<void> deleteSong(RepertoireSong song) async {
    await _client.from('repertoire_songs').delete().eq('id', song.id);
    final path = song.documentPath;
    if (path != null && path.isNotEmpty) {
      await _client.storage.from(_bucket).remove([path]);
    }
    await _refreshCache(song.activityId);
  }

  Future<String> signedDocumentUrl(String path) =>
      _client.storage.from(_bucket).createSignedUrl(path, 3600);

  Future<void> _refreshCache(String activityId) async {
    final rows = await _client
        .from('repertoire_songs')
        .select()
        .eq('activity_id', activityId)
        .order('title');
    await _offlineStore.cacheJson('repertoire_cache:$activityId', rows);
  }

  String _contentType(String extension) => switch (extension) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => throw ArgumentError.value(extension, 'extension'),
  };
}
