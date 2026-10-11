import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/offline_store.dart';
import '../domain/member.dart';

class MemberService {
  MemberService(this._client, this._offlineStore);

  final SupabaseClient _client;
  final OfflineStore _offlineStore;

  Future<List<Member>> listMembers({
    String search = '',
    String? activityId,
  }) async {
    final query = search.trim();
    late final List<Map<String, dynamic>> rows;
    late final List<Map<String, dynamic>> cardRows;
    final cacheKey = activityId == null
        ? 'members_cache'
        : 'members_cache:$activityId';
    if (await _offlineStore.isOnline()) {
      final membershipRows = await _client
          .from('member_activities')
          .select('member_id, activity_id, activities!inner(name)')
          .or(
            'ended_at.is.null,ended_at.gte.${DateTime.now().toIso8601String().split('T').first}',
          );
      final membershipsByMember = <String, List<Map<String, dynamic>>>{};
      for (final membership in membershipRows) {
        final memberId = membership['member_id'] as String;
        final activity = membership['activities'] as Map<String, dynamic>;
        (membershipsByMember[memberId] ??= []).add({
          'activity_id': membership['activity_id'],
          'name': activity['name'],
        });
      }
      final memberIds = activityId == null
          ? null
          : membershipsByMember.entries
              .where(
                (entry) => entry.value.any(
                  (membership) => membership['activity_id'] == activityId,
                ),
              )
              .map((entry) => entry.key)
              .toList(growable: false);
      await _offlineStore.cacheJson(
        'member_activities_cache',
        [
          for (final entry in membershipsByMember.entries)
            {'member_id': entry.key, 'memberships': entry.value},
        ],
      );
      final allRows = activityId != null && memberIds!.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _client.from('members').select().order('last_name');
      final matchingRows = (memberIds == null
              ? allRows
              : allRows.where((row) => memberIds.contains(row['id'])))
          .map((row) {
            final memberships =
                membershipsByMember[row['id'] as String] ?? const [];
            return {
              ...row,
              'activity_ids': memberships
                  .map((membership) => membership['activity_id'])
                  .toList(),
              'activity_names': memberships
                  .map((membership) => membership['name'])
                  .toList(),
            };
          })
          .toList(growable: false);
      cardRows = await _client
          .from('cards')
          .select(
            'id, member_id, activity_id, remaining_passes, total_passes, purchased_at, weekly_limit, expires_at',
          )
          .gt('remaining_passes', 0);
      await _offlineStore.cacheJson(
        cacheKey,
        matchingRows.map(_offlineSafeMember).toList(),
      );
      await _offlineStore.cacheJson('cards_cache', cardRows);
      rows = matchingRows;
    } else {
      final cachedMembers = _offlineStore.readJsonList(cacheKey);
      cardRows = _offlineStore.readJsonList('cards_cache') ?? [];
      if (cachedMembers == null) {
        throw StateError(
          'Aucune fiche adhÃ©rent hors-ligne nâ€™est enregistrÃ©e. '
          'Connectez-vous une premiÃ¨re fois pour synchroniser les donnÃ©es.',
        );
      }
      rows = cachedMembers.where((member) {
        if (query.isEmpty) return true;
        return '${member['first_name']} ${member['last_name']}'
            .toLowerCase()
            .contains(query.toLowerCase());
      }).toList();
    }
    final passCounts = <String, int>{};
    final subscriptionEnds = <String, DateTime>{};
    final cardExpirations = <String, DateTime>{};
    final membersWithLastClass = <String>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final reminderDeadline = today.add(const Duration(days: 7));
    for (final card in cardRows) {
      if (_cardIsExpired(card)) continue;
      final id = card['member_id'] as String;
      if (activityId != null && card['activity_id'] != activityId) continue;
      final expiresAt = card['expires_at'] as String?;
      if (expiresAt != null) {
        final end = DateTime.parse(expiresAt).toLocal();
        final endDate = DateTime(end.year, end.month, end.day);
        if (!endDate.isBefore(today) && !endDate.isAfter(reminderDeadline)) {
          cardExpirations.update(
            id,
            (current) => end.isBefore(current) ? end : current,
            ifAbsent: () => end,
          );
        }
        subscriptionEnds.update(
          id,
          (current) => end.isAfter(current) ? end : current,
          ifAbsent: () => end,
        );
      }
      final remainingPasses = card['remaining_passes'] as int;
      if (remainingPasses == 1) membersWithLastClass.add(id);
      if (expiresAt == null) {
        passCounts.update(
          id,
          (current) => current + remainingPasses,
          ifAbsent: () => remainingPasses,
        );
      }
    }

    final members = rows
        .map(
          (row) => Member.fromMap(
            row,
            remainingPasses: passCounts[row['id'] as String] ?? 0,
            subscriptionUntil: subscriptionEnds[row['id'] as String],
            cardExpiringAt: cardExpirations[row['id'] as String],
            cardHasLastClass: membersWithLastClass.contains(row['id']),
          ),
        )
        .toList(growable: false);
    if (query.isEmpty) return members;
    return members
        .where(
          (member) =>
              member.fullName.toLowerCase().contains(query.toLowerCase()) ||
              (member.email?.toLowerCase().contains(query.toLowerCase()) ??
                  false) ||
              (member.phone?.contains(query) ?? false),
        )
        .toList(growable: false);
  }

  Map<String, dynamic> _offlineSafeMember(Map<String, dynamic> row) => {
    'id': row['id'],
    'first_name': row['first_name'],
    'last_name': row['last_name'],
    'membership_valid_until': row['membership_valid_until'],
    'is_active': row['is_active'],
    'activity_ids': row['activity_ids'] ?? const [],
    'activity_names': row['activity_names'] ?? const [],
  };

  Future<Member> saveMember(
    Member member, {
    List<String>? activityIds,
  }) async {
    if (activityIds != null && activityIds.isEmpty) {
      throw ArgumentError(
        'A member must be assigned to at least one activity.',
      );
    }
    if (member.id.isEmpty && activityIds == null) {
      throw ArgumentError('A new member must be assigned to an activity.');
    }
    final row = await _client
        .from('members')
        .upsert(member.toMap())
        .select()
        .single();
    if (activityIds != null) {
      await _client.rpc(
        'set_member_activities',
        params: {
          'p_member_id': row['id'],
          'p_activity_ids': activityIds.toSet().toList(),
        },
      );
    }
    return Member.fromMap(
      row,
      remainingPasses: member.remainingPasses,
      subscriptionUntil: member.subscriptionUntil,
      cardExpiringAt: member.cardExpiringAt,
      cardHasLastClass: member.cardHasLastClass,
    );
  }

  Future<void> archiveMember(String memberId) async {
    await _client
        .from('members')
        .update({'is_active': false})
        .eq('id', memberId);
  }

  Future<void> setMemberActive(String memberId, bool isActive) async {
    await _client
        .from('members')
        .update({'is_active': isActive})
        .eq('id', memberId);
  }

  Future<List<Map<String, dynamic>>> usableCards(
    String memberId, {
    String? activityId,
  }) async {
    if (!await _offlineStore.isOnline()) {
      final cached = _offlineStore.readJsonList('cards_cache');
      if (cached == null) {
        throw StateError('Aucune carte nâ€™est disponible hors-ligne.');
      }
      return cached
          .where(
            (card) =>
                card['member_id'] == memberId &&
                (activityId == null || card['activity_id'] == activityId) &&
                (card['remaining_passes'] as int) > 0 &&
                !_cardIsExpired(card),
          )
          .map(
            (card) => {
              'id': card['id'],
              'activity_id': card['activity_id'],
              'remaining_passes': card['remaining_passes'],
              'purchased_at': card['purchased_at'],
              'weekly_limit': card['weekly_limit'],
              'expires_at': card['expires_at'],
            },
          )
          .toList(growable: false);
    }
    var query = _client
        .from('cards')
        .select(
          'id, activity_id, remaining_passes, purchased_at, weekly_limit, expires_at',
        )
        .eq('member_id', memberId)
        .gt('remaining_passes', 0)
        .or('expires_at.is.null,expires_at.gt.${DateTime.now().toUtc().toIso8601String()}');
    if (activityId != null) query = query.eq('activity_id', activityId);
    return query.order('purchased_at');
  }

  Future<List<Map<String, dynamic>>> cardsForMember(String memberId) async {
    if (!await _offlineStore.isOnline()) {
      throw StateError('La gestion des cartes nÃ©cessite une connexion.');
    }
    return _client
        .from('cards')
        .select(
          'id, purchase_number, total_passes, remaining_passes, purchased_at, plan_code, expires_at',
        )
        .eq('member_id', memberId)
        .order('purchased_at', ascending: false);
  }

  Future<void> adjustCardPasses({
    required String cardId,
    required int remainingPasses,
    required String reason,
  }) async {
    await _client.rpc(
      'adjust_member_card_passes',
      params: {
        'p_card_id': cardId,
        'p_remaining_passes': remainingPasses,
        'p_reason': reason.trim(),
      },
    );
  }

  Future<String> uploadMemberPhoto({
    required String memberId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final safeExtension = extension.toLowerCase().replaceAll('.', '');
    if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(safeExtension)) {
      throw ArgumentError.value(
        extension,
        'extension',
        'Unsupported image type',
      );
    }
    final path =
        '$memberId/${DateTime.now().microsecondsSinceEpoch}.$safeExtension';
    await _client.storage
        .from('member_photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: switch (safeExtension) {
              'jpg' || 'jpeg' => 'image/jpeg',
              'png' => 'image/png',
              'webp' => 'image/webp',
              _ => throw ArgumentError.value(extension, 'extension'),
            },
          ),
        );
    return path;
  }

  Future<void> deleteMemberPhoto(String? path) async {
    if (path == null || path.isEmpty || path.startsWith('http')) return;
    await _client.storage.from('member_photos').remove([path]);
  }

  Future<String?> signedPhotoUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return _client.storage.from('member_photos').createSignedUrl(path, 3600);
  }
}

bool _cardIsExpired(Map<String, dynamic> card) {
  final expiresAt = card['expires_at'] as String?;
  return expiresAt != null && DateTime.parse(expiresAt).isBefore(DateTime.now());
}
