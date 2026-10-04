class AppUserProfile {
  const AppUserProfile({
    required this.id,
    required this.displayName,
    required this.role,
    this.teachingDances = const [],
    this.photoUrl,
  });

  final String id;
  final String displayName;
  final String role;
  final List<String> teachingDances;
  final String? photoUrl;

  bool get isAdmin => role == 'admin';

  factory AppUserProfile.fromMap(Map<String, dynamic> map) {
    final role = map['role'] as String;
    if (role != 'admin' && role != 'assistant') {
      throw FormatException('Rôle utilisateur inconnu : $role');
    }
    return AppUserProfile(
      id: map['id'] as String,
      displayName: map['display_name'] as String? ?? '',
      role: role,
      teachingDances: (map['teaching_dances'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(growable: false),
      photoUrl: map['photo_url'] as String?,
    );
  }
}
