import '../../choreography/domain/track.dart';

class SessionPlan {
  const SessionPlan({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.tracks,
    this.preparationNotes,
  });

  final String id;
  final String title;
  final DateTime startsAt;
  final List<Track> tracks;
  final String? preparationNotes;

  Duration get totalDuration => tracks.fold(
        Duration.zero,
        (total, track) => total + track.duration,
      );

  List<CardioIntensity> get intensityCurve =>
      tracks.map((track) => track.intensity).toList(growable: false);
}
