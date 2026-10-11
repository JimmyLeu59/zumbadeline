import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/offline_store.dart';
import 'local_document_store.dart';
import '../domain/track.dart';

class ChoreographyService {
  ChoreographyService(this._client, this._offlineStore);

  final SupabaseClient _client;
  final OfflineStore _offlineStore;
  final LocalDocumentStore _localDocumentStore = const LocalDocumentStore();

  Future<List<Track>> listTracks({
    DanceStyle? style,
    CardioIntensity? intensity,
    DateTime? notPlayedSince,
    String? activityId,
  }) async {
    final cacheKey = activityId == null
        ? 'tracks_cache'
        : 'tracks_cache:$activityId';
    if (!await _offlineStore.isOnline()) {
      final cached = _offlineStore.readJsonList(cacheKey);
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
    if (activityId != null) query = query.eq('activity_id', activityId);
    if (style != null) query = query.eq('style', style.name);
    if (intensity != null) query = query.eq('intensity', intensity.name);
    if (notPlayedSince != null) {
      query = query.or(
        'last_played_at.is.null,last_played_at.lt.${notPlayedSince.toUtc().toIso8601String()}',
      );
    }

    final rows = await query.order('title');
    final enrichedRows = rows.map((row) {
      final localPath = _offlineStore.readString(
        'track_document:${row['id']}',
      );
      return {
        ...row,
        'local_document_path':
            localPath == null || localPath.isEmpty ? null : localPath,
      };
    }).toList(growable: false);
    if (style == null && intensity == null && notPlayedSince == null) {
      await _offlineStore.cacheJson(cacheKey, enrichedRows);
    }
    return enrichedRows.map(Track.fromMap).toList(growable: false);
  }

  Future<Track> saveTrack(Track track) async {
    final row = await _client
        .from('tracks')
        .upsert(track.toMap())
        .select()
        .single();
    return Track.fromMap(row);
  }

  Future<void> deleteTrack(
    String trackId, {
    String? localDocumentPath,
  }) async {
    await _client.from('tracks').delete().eq('id', trackId);
    final localPath =
        localDocumentPath ?? _offlineStore.readString('track_document:$trackId');
    if (localPath != null && localPath.isNotEmpty) {
      await _localDocumentStore.delete(localPath);
      await _offlineStore.delete('track_document:$trackId');
    }
  }

  Future<String> saveLocalDocument({
    required Track track,
    required Uint8List bytes,
    required String fileName,
    String? activityId,
  }) async {
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Document exceeds 20 MB');
    }
    final extension = fileName.split('.').last.toLowerCase();
    if (!const {'pdf', 'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
      throw ArgumentError.value(fileName, 'fileName', 'Unsupported file type');
    }
    final path = await _localDocumentStore.save(
      trackId: track.id,
      extension: extension,
      bytes: bytes,
    );
    try {
      await _offlineStore.saveString('track_document:${track.id}', path);
      await _updateCachedDocumentPath(
        trackId: track.id,
        path: path,
        activityId: activityId ?? track.activityId,
      );
    } catch (error) {
      await _offlineStore.delete('track_document:${track.id}');
      await _localDocumentStore.delete(path);
      rethrow;
    }
    final previousPath = track.localDocumentPath;
    if (previousPath != null && previousPath != path) {
      await _localDocumentStore.delete(previousPath);
    }
    return path;
  }

  Future<Uint8List> readLocalDocument(String path) =>
      _localDocumentStore.read(path);

  Future<void> _updateCachedDocumentPath({
    required String trackId,
    required String path,
    String? activityId,
  }) async {
    final keys = {
      'tracks_cache',
      if (activityId != null) 'tracks_cache:$activityId',
    };
    for (final key in keys) {
      final rows = _offlineStore.readJsonList(key);
      if (rows == null) continue;
      for (final row in rows) {
        if (row['id'] == trackId) row['local_document_path'] = path;
      }
      await _offlineStore.cacheJson(key, rows);
    }
  }

  Future<String> signedDocumentUrl(String path) async {
    if (path.startsWith('http')) return path;
    return _client.storage.from('choreography_docs').createSignedUrl(path, 3600);
  }
}
