import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OfflineStatus {
  const OfflineStatus({
    required this.isOnline,
    required this.pendingCheckIns,
    this.lastError,
  });

  final bool isOnline;
  final int pendingCheckIns;
  final String? lastError;
}

class OfflineStore {
  OfflineStore._(this._box, this._connectivity);

  final Box<String> _box;
  final Connectivity _connectivity;
  final _statusController = StreamController<OfflineStatus>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _retryTimer;
  bool _syncing = false;
  String? _userId;
  OfflineStatus _status = const OfflineStatus(
    isOnline: false,
    pendingCheckIns: 0,
  );

  static Future<OfflineStore> open() async {
    await Hive.initFlutter();
    const secureStorage = FlutterSecureStorage();
    var encodedKey = await secureStorage.read(key: 'zumba_offline_key');
    if (encodedKey == null) {
      final random = Random.secure();
      encodedKey = base64UrlEncode(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      await secureStorage.write(key: 'zumba_offline_key', value: encodedKey);
    }
    final key = base64Url.decode(base64Url.normalize(encodedKey));
    final box = await Hive.openBox<String>(
      'zumba_offline_v1',
      encryptionCipher: HiveAesCipher(key),
    );
    return OfflineStore._(box, Connectivity());
  }

  OfflineStatus get status => _status;
  Stream<OfflineStatus> get statusChanges => _statusController.stream;
  Stream<OfflineStatus> get watchStatus async* {
    yield _status;
    yield* _statusController.stream;
  }

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }

  bool setUser(String? userId) {
    if (_userId == userId) return false;
    _userId = userId;
    unawaited(_publishStatus(isOnline: _status.isOnline, error: null));
    return true;
  }

  Future<void> cacheJson(String key, Object value) async {
    await _box.put(_scopedKey(key), jsonEncode(value));
  }

  Future<void> saveString(String key, String value) =>
      _box.put(_scopedKey(key), value);

  Future<void> delete(String key) => _box.delete(_scopedKey(key));

  String? readString(String key) => _box.get(_scopedKey(key));

  List<Map<String, dynamic>>? readJsonList(String key) {
    final value = _box.get(_scopedKey(key));
    if (value == null) return null;
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      throw FormatException('Local cache "$key" is not a list.');
    }
    return decoded
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> cachedAttendance(String sessionId) async {
    return readJsonList('attendance:$sessionId') ?? const [];
  }

  Future<void> cacheAttendance(
    String sessionId,
    List<Map<String, dynamic>> rows,
  ) => cacheJson('attendance:$sessionId', rows);

  Future<void> enqueueCheckIn(Map<String, dynamic> operation) async {
    final queue = readJsonList('pending_checkins') ?? [];
    final operationId = operation['p_offline_operation_id'] as String;
    if (queue.any((item) => item['p_offline_operation_id'] == operationId)) {
      return;
    }
    final sessionId = operation['p_session_id'] as String;
    final memberId = operation['p_member_id'] as String;
    final attendance = await cachedAttendance(sessionId);
    if (attendance.any((row) => row['member_id'] == memberId)) {
      throw StateError('La présence de cet adhérent est déjà enregistrée.');
    }

    final cardId = operation['p_card_id'] as String?;
    List<Map<String, dynamic>>? cardsToUpdate;
    Map<String, dynamic>? cardToUpdate;
    if (cardId != null) {
      cardsToUpdate = readJsonList('cards_cache');
      if (cardsToUpdate == null) {
        throw StateError(
          'Aucune carte n’est disponible dans le cache hors-ligne.',
        );
      }
      for (final card in cardsToUpdate) {
        if (card['id'] == cardId) {
          cardToUpdate = card;
          break;
        }
      }
      if (cardToUpdate == null ||
          (cardToUpdate['remaining_passes'] as int) <= 0) {
        throw StateError('Cette carte ne contient plus de passages.');
      }
    }

    queue.add(operation);
    await cacheJson('pending_checkins', queue);
    attendance.add({
      'session_id': sessionId,
      'member_id': memberId,
      'card_id': cardId,
      'checked_in_at': DateTime.now().toUtc().toIso8601String(),
      'offline_pending': true,
    });
    await cacheAttendance(sessionId, attendance);
    if (cardToUpdate != null) {
      cardToUpdate['remaining_passes'] =
          (cardToUpdate['remaining_passes'] as int) - 1;
      await cacheJson('cards_cache', cardsToUpdate!);
    }
    await _publishStatus(isOnline: false, error: null);
  }

  Future<void> startSync(SupabaseClient client) async {
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      final connected = results.any(
        (result) => result != ConnectivityResult.none,
      );
      _publishStatus(isOnline: connected);
      if (connected) unawaited(syncPending(client));
    });
    _retryTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(syncPending(client)),
    );
    await syncPending(client);
  }

  Future<void> syncPending(SupabaseClient client) async {
    if (_syncing || !await isOnline()) {
      await _publishStatus(isOnline: false);
      return;
    }
    _syncing = true;
    try {
      final pending = readJsonList('pending_checkins') ?? [];
      String? syncError;
      for (final operation in pending) {
        try {
          await client.rpc('check_in_member_with_payment', params: operation);
          await _completeCheckIn(operation);
        } catch (error) {
          syncError = error.toString();
        }
      }
      if (syncError == null) {
        await _box.delete(_scopedKey('offline_sync_error'));
      } else {
        await _box.put(_scopedKey('offline_sync_error'), syncError);
      }
      await _publishStatus(isOnline: true, error: syncError);
    } catch (error) {
      await _box.put(_scopedKey('offline_sync_error'), error.toString());
      await _publishStatus(isOnline: true, error: error.toString());
    } finally {
      _syncing = false;
    }
  }

  Future<void> _completeCheckIn(Map<String, dynamic> operation) async {
    final queue = readJsonList('pending_checkins') ?? [];
    final operationId = operation['p_offline_operation_id'];
    queue.removeWhere((item) => item['p_offline_operation_id'] == operationId);
    await cacheJson('pending_checkins', queue);

    final sessionId = operation['p_session_id'] as String;
    final memberId = operation['p_member_id'] as String;
    final rows = await cachedAttendance(sessionId);
    for (final row in rows) {
      if (row['member_id'] == memberId) row['offline_pending'] = false;
    }
    await cacheAttendance(sessionId, rows);
  }

  Future<void> _publishStatus({required bool isOnline, String? error}) async {
    final queue = readJsonList('pending_checkins') ?? [];
    _status = OfflineStatus(
      isOnline: isOnline,
      pendingCheckIns: queue.length,
      lastError: error ?? _box.get(_scopedKey('offline_sync_error')),
    );
    if (!_statusController.isClosed) _statusController.add(_status);
  }

  String _scopedKey(String key) => '${_userId ?? 'anonymous'}:$key';

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _retryTimer?.cancel();
    await _statusController.close();
    await _box.close();
  }
}
