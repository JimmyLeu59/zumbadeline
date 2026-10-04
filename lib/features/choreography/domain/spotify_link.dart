import 'track.dart';

abstract final class SpotifyLink {
  static final _trackIdPattern = RegExp(r'^[A-Za-z0-9]+$');

  static String? validate(String? value) {
    final link = value?.trim() ?? '';
    if (link.isEmpty) return null;
    if (link.startsWith('spotify:track:')) {
      final id = link.substring('spotify:track:'.length);
      return _trackIdPattern.hasMatch(id)
          ? null
          : 'Lien Spotify de morceau invalide.';
    }
    final uri = Uri.tryParse(link);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'open.spotify.com') {
      return 'Saisissez un lien https://open.spotify.com vers un morceau.';
    }
    final segments = uri.pathSegments;
    final trackIndex = segments.indexOf('track');
    if (trackIndex < 0 ||
        trackIndex + 1 >= segments.length ||
        !_trackIdPattern.hasMatch(segments[trackIndex + 1])) {
      return 'Le lien doit pointer vers un morceau Spotify.';
    }
    return null;
  }

  static Uri forTrack(Track track) {
    final link = track.spotifyUrl?.trim() ?? '';
    if (link.startsWith('spotify:track:')) {
      final id = link.substring('spotify:track:'.length);
      if (validate(link) != null) {
        throw FormatException('Lien Spotify de morceau invalide: $link');
      }
      return Uri.https('open.spotify.com', '/track/$id');
    }
    if (link.isNotEmpty) {
      if (validate(link) != null) {
        throw FormatException('Lien Spotify de morceau invalide: $link');
      }
      return Uri.parse(link);
    }
    final query = [track.title, track.artist]
        .where((value) => value.trim().isNotEmpty)
        .join(' ');
    return Uri.parse(
      'https://open.spotify.com/search/${Uri.encodeComponent(query)}',
    );
  }
}
