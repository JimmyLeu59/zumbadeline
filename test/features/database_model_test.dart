import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zumbadeline/features/agenda/domain/class_session.dart';
import 'package:zumbadeline/features/agenda/domain/recurring_event.dart';
import 'package:zumbadeline/features/activities/domain/activity.dart';
import 'package:zumbadeline/features/choreography/domain/track.dart';
import 'package:zumbadeline/features/choreography/domain/spotify_link.dart';
import 'package:zumbadeline/features/finances/domain/expense_report.dart';
import 'package:zumbadeline/features/finances/domain/payment.dart';
import 'package:zumbadeline/features/members/domain/card_notification.dart';
import 'package:zumbadeline/features/members/domain/member.dart';
import 'package:zumbadeline/features/repertoire/domain/repertoire_song.dart';
import 'package:zumbadeline/features/staff/domain/app_user_profile.dart';

void main() {
  group('Supabase model mappings', () {
    test('card notifications map and format their reminder', () {
      final notification = CardNotification.fromMap({
        'id': 'notification-id',
        'card_id': 'card-id',
        'kind': 'expiry',
        'member_name': 'Camille Danse',
        'activity_name': 'Zumba',
        'expires_at': '2026-10-18T08:00:00.000Z',
        'created_at': '2026-10-11T08:00:00.000Z',
        'read_at': null,
      });

      expect(notification.isRead, isFalse);
      expect(notification.title, 'Carte bientôt expirée');
      expect(
        notification.message,
        contains('Camille Danse : la carte pour Zumba expire le'),
      );
    });

    test('activity maps its presentation color and icon', () {
      final activity = Activity.fromMap({
        'id': 'singing-id',
        'name': 'Chant',
        'color_code': '#7C4DFF',
        'icon': 'mic',
      });

      expect(activity.name, 'Chant');
      expect(activity.accentColor.toARGB32(), 0xFF7C4DFF);
      expect(activity.iconData, Icons.mic_rounded);
      expect(activity.isSinging, isTrue);
      expect(
        Activity.fromMap({
          'id': 'dance-id',
          'name': 'Danse',
          'icon': 'fitness_center',
        }).isSinging,
        isFalse,
      );
    });

    test('singing repertoire maps rehearsal and vocal metadata', () {
      final song = RepertoireSong.fromMap({
        'id': 'song-id',
        'activity_id': 'singing-id',
        'title': 'Chant de répétition',
        'composer': 'Auteur',
        'key_signature': 'Ré majeur',
        'vocal_range': 'Médium',
        'vocal_part': 'Alto',
        'accompaniment': 'Piano',
        'duration_seconds': 185,
        'rehearsal_notes': 'Travailler le deuxième couplet',
        'document_path': 'singing-id/song-id.pdf',
        'last_played_at': '2026-10-19T19:00:00.000Z',
      });

      expect(song.duration, const Duration(minutes: 3, seconds: 5));
      expect(song.vocalPart, 'Alto');
      expect(song.toMap()['rehearsal_notes'], 'Travailler le deuxième couplet');
      expect(song.toMap()['document_path'], 'singing-id/song-id.pdf');
    });

    test('member maps database dates and privacy fields', () {
      final today = DateTime.now();
      final expiry = DateTime(today.year, today.month, today.day + 8);
      final member = Member.fromMap(
        {
          'id': 'member-id',
          'first_name': 'Camille',
          'last_name': 'Danse',
          'membership_valid_until': '2026-12-31',
          'is_active': true,
          'activity_ids': ['zumba-id', 'singing-id'],
          'activity_names': ['Zumba', 'Chant'],
        },
        remainingPasses: 7,
        subscriptionUntil: expiry,
        cardExpiringAt: DateTime(2026, 11, 2),
        cardHasLastClass: true,
      );

      expect(member.fullName, 'Camille Danse');
      expect(member.remainingPasses, 7);
      expect(member.cardExpiringAt, DateTime(2026, 11, 2));
      expect(member.cardHasLastClass, isTrue);
      expect(member.subscriptionDaysRemaining, 8);
      expect(
        member.membershipDaysRemaining,
        DateTime(
          2026,
          12,
          31,
        ).difference(DateTime(today.year, today.month, today.day)).inDays,
      );
      expect(member.activityIds, ['zumba-id', 'singing-id']);
      expect(member.activityNames, ['Zumba', 'Chant']);
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

    test('instructor profiles map their single-activity access', () {
      final profile = AppUserProfile.fromMap({
        'id': 'instructor-id',
        'display_name': 'Camille',
        'role': 'instructor',
        'activity_id_access': 'zumba-id',
      });

      expect(profile.activityIdAccess, 'zumba-id');
      expect(profile.canViewGlobalFinances, isFalse);
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

    test('local preparation document paths never sync to Supabase', () {
      final track = Track(
        id: 'track-id',
        title: 'Ritmo',
        artist: '',
        style: DanceStyle.salsa,
        duration: const Duration(minutes: 3),
        intensity: CardioIntensity.moderate,
        activityId: 'zumba-id',
        localDocumentPath: 'C:\\app\\pedagogical_documents\\notes.pdf',
      );

      expect(track.toMap()['activity_id'], 'zumba-id');
      expect(track.toMap().containsKey('local_document_path'), isFalse);
    });

    test('session maps status, dates and equipment checklist', () {
      final session = ClassSession.fromMap({
        'id': 'session-id',
        'title': 'Zumba',
        'session_type': 'class',
        'starts_at': '2026-10-04T17:00:00.000Z',
        'status': 'scheduled',
        'attendance_count': 3,
        'recurring_event_id': 'series-id',
        'occurrence_key': '2026-10-04T17:00:00.000Z',
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
      expect(session.recurringEventId, 'series-id');
      expect(session.attendanceCount, 3);
      expect(session.occurrenceKey, DateTime.utc(2026, 10, 4, 17));
      expect(session.toMap()['status'], 'scheduled');
      expect(
        session.toMap()['equipment_checklist'],
        session.equipmentChecklist,
      );
    });

    test('recurring event maps its activity and recurrence rule', () {
      final event = RecurringEvent.fromMap({
        'id': 'series-id',
        'activity_id': 'zumba-id',
        'title': 'Cours du mardi',
        'session_type': 'class',
        'starts_at': '2026-10-06T17:00:00.000Z',
        'time_zone': 'Europe/Paris',
        'recurrence_rule': {
          'freq': 'weekly',
          'byWeekday': [2],
        },
        'repeats_until': '2026-12-31',
      });

      expect(event.activityId, 'zumba-id');
      expect(event.recurrenceRule['freq'], 'weekly');
      expect(event.toMap()['repeats_until'], '2026-12-31');
    });

    test('expense report maps its status and receipt reference', () {
      final report = ExpenseReport.fromMap({
        'id': 'expense-id',
        'user_id': 'staff-id',
        'activity_id': 'zumba-id',
        'amount': 24.5,
        'description': 'Piles pour micro',
        'status': 'pending',
        'receipt_path': 'staff-id/expense-id/receipt.jpg',
        'incurred_at': '2026-10-04',
      });

      expect(report.amount, 24.5);
      expect(report.status, ExpenseReportStatus.pending);
      expect(report.receiptPath, 'staff-id/expense-id/receipt.jpg');
      expect(report.toMap()['activity_id'], 'zumba-id');
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
