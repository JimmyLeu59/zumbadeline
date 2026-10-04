import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/offline_store.dart';
import '../domain/track.dart';

class ChoreographyService {
  ChoreographyService(this._client, this._offlineStore);

  final SupabaseClient _client;
  final OfflineStore _offlineStore;

  Future<List<Track>> listTracks({
    DanceStyle? style,
    CardioIntensity? intensity,
    DateTime? notPlayedSince,
  }) async {
    if (!await _offlineStore.isOnline()) {
      final cached = _offlineStore.readJsonList('tracks_cache');
      if (cached == null) {
        throw StateError('Aucune fiche chorégraphique n’est disponible hors-ligne.');
      }
      final cutoff = notPlayedSince;
      return cached
          .map(Track.fromMap)
          .where((track) {
            if (style != null && track.style != style) return false;
            if (intensity != null && track.intensity != intensity) return false;
            if (cutoff != null &&
                track.lastPlayedAt != null &&
                !track.lastPlayedAt!.isBefore(cutoff)) {
              return false;
            }
            return true;
          })
          .toList(growable: false);
    }
    var query = _client.from('tracks').select();
    if (style != null) query = query.eq('style', style.name);
    if (intensity != null) query = query.eq('intensity', intensity.name);
    if (notPlayedSince != null) {
      query = query.or(
        'last_played_at.is.null,last_played_at.lt.${notPlayedSince.toUtc().toIso8601String()}',
      );
    }

    final rows = await query.order('title');
    if (style == null && intensity == null && notPlayedSince == null) {
      await _offlineStore.cacheJson('tracks_cache', rows);
    }
    return rows.map((row) => Track.fromMap(row)).toList(growable: false);
  }

  Future<Track> saveTrack(Track track) async {
    final row = await _client
        .from('tracks')
        .upsert(track.toMap())
        .select()
        .single();
    return Track.fromMap(row);
  }

  Future<void> deleteTrack(String trackId) async {
    await _client.from('tracks').delete().eq('id', trackId);
  }

  Future<String> uploadDocument({
    required Track track,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Document exceeds 20 MB');
    }
    final extension = fileName.split('.').last.toLowerCase();
    const mimeTypes = {
      'pdf': 'application/pdf',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
    };
    final contentType = mimeTypes[extension];
    if (contentType == null) {
      throw ArgumentError.value(fileName, 'fileName', 'Unsupported file type');
    }
    final path =
        '${track.id}/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _client.storage.from('choreography_docs').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: contentType,
          ),
        );
    try {
      await _client.from('tracks').update({
        'document_url': path,
        'document_type': extension == 'pdf' ? 'pdf' : 'photo',
      }).eq('id', track.id);
    } catch (_) {
      await _client.storage.from('choreography_docs').remove([path]);
      rethrow;
    }
    final previousPath = track.documentUrl;
    if (previousPath != null && !previousPath.startsWith('http')) {
      await _client.storage.from('choreography_docs').remove([previousPath]);
    }
    return path;
  }

  Future<String> signedDocumentUrl(String path) async {
    if (path.startsWith('http')) return path;
    return _client.storage.from('choreography_docs').createSignedUrl(path, 3600);
  }
}
