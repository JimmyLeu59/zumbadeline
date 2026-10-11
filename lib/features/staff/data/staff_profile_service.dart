import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_user_profile.dart';

class StaffProfileService {
  StaffProfileService(this._client);

  final SupabaseClient _client;

  Future<List<AppUserProfile>> listProfiles() async {
    final rows = await _client
        .from('profiles')
        .select(
          'id, display_name, role, activity_id_access, teaching_dances, photo_url',
        )
        .order('display_name');
    return rows
        .map((row) => AppUserProfile.fromMap(row))
        .toList(growable: false);
  }

  Future<void> saveInstructorProfile({
    required String id,
    required String displayName,
    required List<String> teachingDances,
  }) async {
    final dances = teachingDances
        .map((dance) => dance.trim())
        .where((dance) => dance.isNotEmpty)
        .toSet()
        .toList(growable: false);
    await _client
        .from('profiles')
        .update({
          'display_name': displayName.trim(),
          'teaching_dances': dances,
        })
        .eq('id', id);
  }

  Future<String> uploadProfilePhoto({
    required String profileId,
    required Uint8List bytes,
    required String extension,
  }) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
        throw ArgumentError.value(bytes.length, 'bytes', 'Image exceeds 10 MB');
    }
    final safeExtension = extension.toLowerCase().replaceAll('.', '');
    final contentType = switch (safeExtension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => throw ArgumentError.value(extension, 'extension', 'Unsupported image type'),
    };
    final path =
          'instructors/$profileId/${DateTime.now().microsecondsSinceEpoch}.$safeExtension';
    await _client.storage.from('member_photos').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: false, contentType: contentType),
          );
    try {
        await _client
            .from('profiles')
            .update({'photo_url': path})
            .eq('id', profileId);
    } catch (_) {
        await _client.storage.from('member_photos').remove([path]);
        rethrow;
    }
    return path;
  }

  Future<void> deleteProfilePhoto(String? path) async {
    if (path == null || path.isEmpty || path.startsWith('http')) return;
    await _client.storage.from('member_photos').remove([path]);
  }

  Future<String?> signedPhotoUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return _client.storage.from('member_photos').createSignedUrl(path, 3600);
  }
}
