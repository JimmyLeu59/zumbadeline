import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/track_play_count.dart';

class StatisticsService {
  StatisticsService(this._client);

  final SupabaseClient _client;

  Future<List<TrackPlayCount>> mostPlayedTracks({
    required DateTime from,
    required DateTime to,
    int limit = 10,
  }) async {
    if (to.isBefore(from)) {
      throw ArgumentError.value(to, 'to', 'Must not be before from');
    }
    if (limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'Must not be negative');
    }

    final rows = await _client
        .from('session_tracks')
        .select(
          'track_id, tracks!inner(title, artist), sessions!inner(starts_at, status)',
        )
        .gte('sessions.starts_at', from.toUtc().toIso8601String())
        .lte('sessions.starts_at', to.toUtc().toIso8601String())
        .eq('sessions.status', 'completed');

    final counts = <String, TrackPlayCount>{};
    for (final row in rows) {
      final track = row['tracks'] as Map<String, dynamic>;
      final trackId = row['track_id'] as String;
      final previous = counts[trackId];
      counts[trackId] = TrackPlayCount(
        trackId: trackId,
        title: track['title'] as String,
        artist: track['artist'] as String? ?? '',
        playCount: (previous?.playCount ?? 0) + 1,
      );
    }

    final result = counts.values.toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return result.take(limit).toList(growable: false);
  }
}
