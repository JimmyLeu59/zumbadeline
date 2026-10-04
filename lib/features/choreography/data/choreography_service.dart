import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/track.dart';

class ChoreographyService {
  ChoreographyService(this._client);

  final SupabaseClient _client;

  Future<List<Track>> listTracks({
    DanceStyle? style,
    CardioIntensity? intensity,
    DateTime? notPlayedSince,
  }) async {
    var query = _client.from('tracks').select();
    if (style != null) query = query.eq('style', style.name);
    if (intensity != null) query = query.eq('intensity', intensity.name);
    if (notPlayedSince != null) {
      query = query.or(
        'last_played_at.is.null,last_played_at.lt.${notPlayedSince.toUtc().toIso8601String()}',
      );
    }

    final rows = await query.order('title');
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
}
