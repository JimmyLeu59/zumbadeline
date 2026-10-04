import 'package:flutter_test/flutter_test.dart';
import 'package:zumbadeline/features/agenda/domain/class_session.dart';
import 'package:zumbadeline/features/choreography/domain/track.dart';
import 'package:zumbadeline/features/choreography/domain/spotify_link.dart';
import 'package:zumbadeline/features/finances/domain/payment.dart';
import 'package:zumbadeline/features/members/domain/member.dart';
import 'package:zumbadeline/features/staff/domain/app_user_profile.dart';

void main() {
  group('Supabase model mappings', () {
    test('member maps database dates and privacy fields', () {
      final member = Member.fromMap({
        'id': 'member-id',
        'first_name': 'Camille',
        'last_name': 'Danse',
        'membership_valid_until': '2026-12-31',
        'is_active': true,
      }, remainingPasses: 7);

      expect(member.fullName, 'Camille Danse');
      expect(member.remainingPasses, 7);
      expect(member.toMap()['membership_valid_until'], '2026-12-31');
      expect(member.toMap()['first_name'], 'Camille');
    });

    test('staff profile maps multiple dance disciplines', () {
      final profile = AppUserProfile.fromMap({
        'id': 'staff-id',
        'display_name': 'Camille',
        'role': 'assistant',
        'teaching_dances': ['Line Dance', 'Danse celtique'],
        'photo_url': 'instructors/staff-id/photo.jpg',
      });

      expect(profile.teachingDances, ['Line Dance', 'Danse celtique']);
      expect(profile.photoUrl, 'instructors/staff-id/photo.jpg');
      expect(profile.isAdmin, isFalse);
    });

    test('track maps enum and duration fields to the tracks schema', () {
      final track = Track(
        id: 'track-id',
        title: 'Ritmo',
        artist: 'DJ',
        style: DanceStyle.reggaeton,
        duration: const Duration(minutes: 3, seconds: 30),
        intensity: CardioIntensity.high,
        spotifyUrl: 'https://open.spotify.com/track/AbCd1234',
      );
      final mapped = track.toMap();
      final restored = Track.fromMap(mapped);

      expect(mapped['duration_seconds'], 210);
      expect(mapped['intensity'], 'high');
      expect(restored.duration, const Duration(seconds: 210));
      expect(restored.style, DanceStyle.reggaeton);
      expect(restored.spotifyUrl, 'https://open.spotify.com/track/AbCd1234');
    });

    test('Spotify links accept track links and reject unrelated URLs', () {
      expect(
        SpotifyLink.validate('https://open.spotify.com/track/AbCd1234?si=xyz'),
        isNull,
      );
      expect(
        SpotifyLink.validate('https://example.com/track/AbCd1234'),
        isNotNull,
      );
      expect(
        SpotifyLink.validate('https://open.spotify.com/playlist/AbCd1234'),
        isNotNull,
      );
    });

    test(
      'Spotify action searches by title and artist when no link is saved',
      () {
        final track = Track(
          id: 'track-id',
          title: 'Ritmo alegre',
          artist: 'DJ Sol',
          style: DanceStyle.salsa,
          duration: const Duration(minutes: 3),
          intensity: CardioIntensity.moderate,
        );

        expect(
          SpotifyLink.forTrack(track).toString(),
          'https://open.spotify.com/search/Ritmo%20alegre%20DJ%20Sol',
        );
      },
    );

    test('new tracks omit an empty id so PostgreSQL generates its UUID', () {
      final track = Track(
        id: '',
        title: 'Ritmo',
        artist: '',
        style: DanceStyle.salsa,
        duration: const Duration(minutes: 3),
        intensity: CardioIntensity.moderate,
      );

      expect(track.toMap().containsKey('id'), isFalse);
    });

    test('session maps status, dates and equipment checklist', () {
      final session = ClassSession.fromMap({
        'id': 'session-id',
        'title': 'Zumba',
        'session_type': 'class',
        'starts_at': '2026-10-04T17:00:00.000Z',
        'status': 'scheduled',
        'equipment_checklist': [
          {'label': 'Enceinte', 'checked': false},
        ],
        'instructors': [
          {
            'profile_id': 'instructor-id',
            'role': 'Coordination',
            'profiles': {'display_name': 'Camille'},
          },
        ],
      });

      expect(session.equipmentChecklist.single['label'], 'Enceinte');
      expect(session.instructors.single.profileId, 'instructor-id');
      expect(session.instructors.single.displayName, 'Camille');
      expect(session.instructors.single.role, 'Coordination');
      expect(session.toMap()['status'], 'scheduled');
      expect(
        session.toMap()['equipment_checklist'],
        session.equipmentChecklist,
      );
    });

    test('pricing values use the exact pricing_settings column names', () {
      const pricing = PricingSettings(
        annualMembershipFee: 20,
        singleClassPrice: 5,
        firstCardPrice: 50,
        renewalCardPrice: 45,
        cardPassCount: 10,
        currency: 'EUR',
      );

      expect(pricing.toMap(), {
        'id': 1,
        'annual_membership_fee': 20,
        'single_class_price': 5,
        'first_card_price': 50,
        'renewal_card_price': 45,
        'card_pass_count': 10,
        'currency': 'EUR',
      });
    });
  });
}
