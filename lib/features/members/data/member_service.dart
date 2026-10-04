import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/offline_store.dart';
import '../domain/member.dart';

class MemberService {
  MemberService(this._client, this._offlineStore);

  final SupabaseClient _client;
  final OfflineStore _offlineStore;

  Future<List<Member>> listMembers({String search = ''}) async {
    final query = search.trim();
    late final List<Map<String, dynamic>> rows;
    late final List<Map<String, dynamic>> cardRows;
    if (await _offlineStore.isOnline()) {
      rows = await _client.from('members').select().order('last_name');
      cardRows = await _client
          .from('cards')
          .select('id, member_id, remaining_passes, total_passes, purchased_at')
          .gt('remaining_passes', 0);
      await _offlineStore.cacheJson(
        'members_cache',
        rows.map(_offlineSafeMember).toList(),
      );
      await _offlineStore.cacheJson('cards_cache', cardRows);
    } else {
      final cachedMembers = _offlineStore.readJsonList('members_cache');
      cardRows = _offlineStore.readJsonList('cards_cache') ?? [];
      if (cachedMembers == null) {
        throw StateError(
          'Aucune fiche adhérent hors-ligne n’est enregistrée. '
          'Connectez-vous une première fois pour synchroniser les données.',
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
    for (final card in cardRows) {
      final id = card['member_id'] as String;
      passCounts.update(
        id,
        (current) => current + (card['remaining_passes'] as int),
        ifAbsent: () => card['remaining_passes'] as int,
      );
    }

    final members = rows
        .map(
          (row) => Member.fromMap(
            row,
            remainingPasses: passCounts[row['id'] as String] ?? 0,
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
  };

  Future<Member> saveMember(Member member) async {
    final row = await _client
        .from('members')
        .upsert(member.toMap())
        .select()
        .single();
    return Member.fromMap(row, remainingPasses: member.remainingPasses);
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

  Future<List<Map<String, dynamic>>> usableCards(String memberId) async {
    if (!await _offlineStore.isOnline()) {
      final cached = _offlineStore.readJsonList('cards_cache');
      if (cached == null) {
        throw StateError('Aucune carte n’est disponible hors-ligne.');
      }
      return cached
          .where(
            (card) =>
                card['member_id'] == memberId &&
                (card['remaining_passes'] as int) > 0,
          )
          .map(
            (card) => {
              'id': card['id'],
              'remaining_passes': card['remaining_passes'],
              'purchased_at': card['purchased_at'],
            },
          )
          .toList(growable: false);
    }
    return _client
        .from('cards')
        .select('id, remaining_passes, purchased_at')
        .eq('member_id', memberId)
        .gt('remaining_passes', 0)
        .order('purchased_at');
  }

  Future<List<Map<String, dynamic>>> cardsForMember(String memberId) async {
    if (!await _offlineStore.isOnline()) {
      throw StateError('La gestion des cartes nécessite une connexion.');
    }
    return _client
        .from('cards')
        .select(
          'id, purchase_number, total_passes, remaining_passes, purchased_at',
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
