import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/offline_store.dart';
import '../domain/class_session.dart';

class SessionService {
  SessionService(this._client, this._offlineStore);

  final SupabaseClient _client;
  final OfflineStore _offlineStore;

  Future<List<ClassSession>> listSessions({
    DateTime? from,
    DateTime? until,
    bool upcomingOnly = false,
    String? activityId,
  }) async {
    final cacheKey = activityId == null
        ? 'sessions_cache'
        : 'sessions_cache:$activityId';
    if (!await _offlineStore.isOnline()) {
      final cached = _offlineStore.readJsonList(cacheKey);
      if (cached == null) {
        throw StateError('Aucun agenda n’est disponible hors-ligne.');
      }
      return cached
          .map((row) => ClassSession.fromMap(row))
          .where((session) {
            if (from != null && session.startsAt.isBefore(from)) {
              return false;
            }
            if (until != null && !session.startsAt.isBefore(until)) {
              return false;
            }
            if (upcomingOnly && session.startsAt.isBefore(DateTime.now())) {
              return false;
            }
            return true;
          })
          .toList(growable: false);
    }
    var query = _client.from('sessions').select();
    if (activityId != null) {
      query = query.eq('activity_id', activityId);
    }
    final start = from ?? (upcomingOnly ? DateTime.now() : null);
    if (start != null) {
      query = query.gte('starts_at', start.toUtc().toIso8601String());
    }
    if (until != null) {
      query = query.lt('starts_at', until.toUtc().toIso8601String());
    }
    final rows = await query.order('starts_at');
    if (rows.isEmpty) {
      await _offlineStore.cacheJson(cacheKey, rows);
      return const [];
    }
    final assignments = await _client
        .from('session_instructors')
        .select('session_id, profile_id, role, profiles!inner(display_name)')
        .inFilter('session_id', rows.map((row) => row['id']).toList());
    final instructorsBySession = <String, List<Map<String, dynamic>>>{};
    for (final assignment in assignments) {
      (instructorsBySession[assignment['session_id'] as String] ??= []).add(
        assignment,
      );
    }
    final enrichedRows = rows
        .map(
          (row) => {
            ...row,
            'instructors': instructorsBySession[row['id']] ?? const [],
          },
        )
        .toList(growable: false);
    await _offlineStore.cacheJson(cacheKey, enrichedRows);
    return enrichedRows
        .map((row) => ClassSession.fromMap(row))
        .toList(growable: false);
  }

  Future<ClassSession> saveSession(ClassSession session) async {
    if (session.id.isEmpty && session.repeatsUntil != null) {
      final response = await _client.rpc(
        'create_recurring_event',
        params: {
          'p_session': session.toMap(),
          'p_repeats_until': session.repeatsUntil!
              .toIso8601String()
              .split('T')
              .first,
          'p_interval_weeks': session.recurrenceInterval,
          'p_time_zone': 'Europe/Paris',
          'p_assignments': session.instructors
              .map((instructor) => instructor.toAssignmentMap())
              .toList(),
        },
      );
      if (response is! String) {
        throw const FormatException(
          'La création de la série récurrente a retourné une réponse invalide.',
        );
      }
      final row = await _client
          .from('sessions')
          .select()
          .eq('recurring_event_id', response)
          .order('starts_at')
          .limit(1)
          .single();
      return ClassSession.fromMap(row);
    }
    if (session.isEvent) {
      final response = await _client.rpc(
        'save_event_with_instructors',
        params: {
          'p_session': session.toMap(),
          'p_assignments': session.instructors
              .map((instructor) => instructor.toAssignmentMap())
              .toList(),
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'La sauvegarde de l’événement a retourné une réponse invalide.',
        );
      }
      final row = Map<String, dynamic>.from(response);
      return ClassSession.fromMap({
        ...row,
        'instructors': session.instructors
            .map(
              (instructor) => {
                ...instructor.toAssignmentMap(),
                'profiles': {'display_name': instructor.displayName},
              },
            )
            .toList(),
      });
    }
    final row = await _client
        .from('sessions')
        .upsert(session.toMap())
        .select()
        .single();
    return ClassSession.fromMap(row);
  }

  Future<void> cancelSession(String sessionId) async {
    await _client
        .from('sessions')
        .update({'status': 'cancelled'})
        .eq('id', sessionId);
  }

  Future<void> deleteEvent(String eventId) async {
    await _client.rpc('delete_event', params: {'p_event_id': eventId});
  }

  Future<void> deleteRecurringOccurrence(
    String sessionId, {
    required bool deleteSeries,
  }) async {
    await _client.rpc(
      'delete_recurring_occurrence',
      params: {'p_session_id': sessionId, 'p_delete_series': deleteSeries},
    );
  }

  Future<void> updateEquipmentChecklist(
    String sessionId,
    List<Map<String, dynamic>> checklist,
  ) async {
    await _client
        .from('sessions')
        .update({'equipment_checklist': checklist})
        .eq('id', sessionId);
  }

  Future<List<Map<String, dynamic>>> attendanceForSession(
    String sessionId,
  ) async {
    if (!await _offlineStore.isOnline()) {
      return _offlineStore.cachedAttendance(sessionId);
    }
    final rows = await _client
        .from('attendances')
        .select(
          'id, member_id, card_id, checked_in_at, members!inner(first_name, last_name, phone, email), cards(remaining_passes)',
        )
        .eq('session_id', sessionId)
        .order('checked_in_at');
    await _offlineStore.cacheAttendance(
      sessionId,
      rows
          .map(
            (row) => {
              'id': row['id'],
              'session_id': sessionId,
              'member_id': row['member_id'],
              'card_id': row['card_id'],
              'checked_in_at': row['checked_in_at'],
              'offline_pending': false,
            },
          )
          .toList(),
    );
    return rows;
  }

  Future<List<String>> tracksForSession(String sessionId) async {
    if (!await _offlineStore.isOnline()) {
      final cached = _offlineStore.readJsonList('playlist:$sessionId');
      if (cached == null) return const [];
      return cached.map((row) => row['track_id'] as String).toList();
    }
    final rows = await _client
        .from('session_tracks')
        .select('track_id')
        .eq('session_id', sessionId)
        .order('position');
    await _offlineStore.cacheJson('playlist:$sessionId', rows);
    return rows.map((row) => row['track_id'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> eventRegistrations(
    String sessionId,
  ) async {
    return _client
        .from('event_registrations')
        .select()
        .eq('session_id', sessionId)
        .order('registered_at');
  }

  Future<void> addEventRegistration({
    required String sessionId,
    required String fullName,
    required double amountPaid,
    String? email,
    String? phone,
    String? paymentMethod,
  }) async {
    await _client.from('event_registrations').insert({
      'session_id': sessionId,
      'full_name': fullName.trim(),
      'email': _emptyToNull(email),
      'phone': _emptyToNull(phone),
      'amount_paid': amountPaid,
      'payment_method': paymentMethod,
    });
  }

  Future<void> deleteEventRegistration(String registrationId) async {
    await _client.from('event_registrations').delete().eq('id', registrationId);
  }

  Future<void> savePlaylist(String sessionId, List<String> trackIds) async {
    await _client.rpc(
      'save_session_playlist',
      params: {'p_session_id': sessionId, 'p_track_ids': trackIds},
    );
  }

  Future<void> checkIn({
    required String sessionId,
    required String memberId,
    String? cardId,
    required String paymentMethod,
    required String operationId,
  }) async {
    final operation = {
      'p_session_id': sessionId,
      'p_member_id': memberId,
      'p_card_id': cardId,
      'p_payment_method': paymentMethod,
      'p_offline_operation_id': operationId,
    };
    if (await _offlineStore.isOnline()) {
      try {
        await _client.rpc('check_in_member_with_payment', params: operation);
      } catch (error) {
        if (await _offlineStore.isOnline()) rethrow;
        await _offlineStore.enqueueCheckIn(operation);
      }
    } else {
      await _offlineStore.enqueueCheckIn(operation);
    }
  }

  Future<Map<String, dynamic>> purchaseCardAndCheckIn({
    required String sessionId,
    required String memberId,
    required String priceTier,
    required String paymentMethod,
    required String operationId,
    String? planCode,
  }) async {
    final response = await _client.rpc(
      'purchase_activity_card_and_check_in',
      params: {
        'p_session_id': sessionId,
        'p_member_id': memberId,
        'p_price_tier': priceTier,
        'p_payment_method': paymentMethod,
        'p_offline_operation_id': operationId,
        'p_plan_code': planCode,
      },
    );
    if (response is! Map) {
      throw const FormatException(
        'Réponse invalide lors du pointage avec vente de carte.',
      );
    }
    return Map<String, dynamic>.from(response);
  }
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
