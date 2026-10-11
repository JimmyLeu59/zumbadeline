import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/card_notification.dart';

class CardNotificationService {
  CardNotificationService(this._client);

  final SupabaseClient _client;

  Future<({String memberId, String activityId})> memberRouteForCard(
    String cardId,
  ) async {
    final row = await _client
        .from('cards')
        .select('member_id, activity_id')
        .eq('id', cardId)
        .single();
    return (
      memberId: row['member_id'] as String,
      activityId: row['activity_id'] as String,
    );
  }

  Future<({String firstName, String? email})> memberContactForCard(
    String cardId,
  ) async {
    final row = await _client
        .from('cards')
        .select('members!inner(first_name, email)')
        .eq('id', cardId)
        .single();
    final member = row['members'] as Map<String, dynamic>;
    return (
      firstName: member['first_name'] as String,
      email: member['email'] as String?,
    );
  }

  Stream<List<CardNotification>> watchForStaff(String staffId) {
    return _client
        .from('card_notifications')
        .stream(primaryKey: ['id'])
        .eq('recipient_id', staffId)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows.map(CardNotification.fromMap).toList(growable: false),
        );
  }

  Future<void> markAsRead({
    required String notificationId,
    required String staffId,
  }) async {
    await _client
        .from('card_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', notificationId)
        .eq('recipient_id', staffId);
  }
}
