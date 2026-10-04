import '../../choreography/domain/track.dart';
import '../domain/session_plan.dart';

class RoomModeService {
  RoomModeService(this.plan);

  final SessionPlan plan;
  int _currentIndex = 0;

  Track? get currentTrack =>
      plan.tracks.isEmpty ? null : plan.tracks[_currentIndex];

  Track? get nextTrack => plan.tracks.isEmpty ||
          _currentIndex + 1 >= plan.tracks.length
      ? null
      : plan.tracks[_currentIndex + 1];

  int get currentNumber => plan.tracks.isEmpty ? 0 : _currentIndex + 1;

  bool advance() {
    if (_currentIndex + 1 >= plan.tracks.length) return false;
    _currentIndex++;
    return true;
  }

  bool goToTrack(int index) {
    if (index < 0 || index >= plan.tracks.length) return false;
    _currentIndex = index;
    return true;
  }

  List<Track> reorderTracks(int oldIndex, int newIndex) {
    final reordered = [...plan.tracks];
    if (oldIndex < 0 || oldIndex >= reordered.length) return reordered;
    final destination =
        newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (destination < 0 || destination >= reordered.length) return reordered;
    final track = reordered.removeAt(oldIndex);
    reordered.insert(destination, track);
    return reordered;
  }
}
