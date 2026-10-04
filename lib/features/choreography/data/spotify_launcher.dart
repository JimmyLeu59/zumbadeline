import 'package:url_launcher/url_launcher.dart';

import '../domain/spotify_link.dart';
import '../domain/track.dart';

Future<void> openTrackInSpotify(Track track) async {
  final uri = SpotifyLink.forTrack(track);
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened) {
    throw StateError(
      'Impossible d’ouvrir Spotify. '
      'Vérifiez qu’un navigateur peut ouvrir ce lien.',
    );
  }
}
