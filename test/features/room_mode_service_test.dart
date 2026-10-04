import 'package:flutter_test/flutter_test.dart';
import 'package:zumbadeline/features/choreography/domain/track.dart';
import 'package:zumbadeline/features/room/application/room_mode_service.dart';
import 'package:zumbadeline/features/room/domain/session_plan.dart';

void main() {
  final tracks = [
    _track('one', 180),
    _track('two', 240),
  ];

  test('advances through the playlist and stops at the last track', () {
    final service = RoomModeService(_plan(tracks));

    expect(service.currentTrack?.id, 'one');
    expect(service.nextTrack?.id, 'two');
    expect(service.advance(), isTrue);
    expect(service.currentNumber, 2);
    expect(service.currentTrack?.id, 'two');
    expect(service.nextTrack, isNull);
    expect(service.advance(), isFalse);
  });

  test('rejects invalid selection and reorders tracks', () {
    final service = RoomModeService(_plan(tracks));

    expect(service.goToTrack(2), isFalse);
    expect(service.reorderTracks(0, 2).map((track) => track.id), ['two', 'one']);
    expect(service.reorderTracks(-1, 0).map((track) => track.id), ['one', 'two']);
  });

  test('calculates total duration and intensity curve', () {
    final plan = _plan(tracks);

    expect(plan.totalDuration, const Duration(minutes: 7));
    expect(plan.intensityCurve, [
      CardioIntensity.warmUp,
      CardioIntensity.high,
    ]);
  });
}

Track _track(String id, int seconds) => Track(
      id: id,
      title: id,
      artist: 'Artist',
      style: DanceStyle.salsa,
      duration: Duration(seconds: seconds),
      intensity: id == 'one' ? CardioIntensity.warmUp : CardioIntensity.high,
    );

SessionPlan _plan(List<Track> tracks) => SessionPlan(
      id: 'session',
      title: 'Test',
      startsAt: DateTime.utc(2026),
      tracks: tracks,
    );
