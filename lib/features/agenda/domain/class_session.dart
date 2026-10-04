class ClassSession {
  const ClassSession({
    required this.id,
    required this.title,
    required this.type,
    required this.startsAt,
    required this.status,
    this.endsAt,
    this.location,
    this.capacity,
    this.preparationNotes,
    this.equipmentChecklist = const [],
    this.attendanceCount = 0,
    this.instructors = const [],
  });

  final String id;
  final String title;
  final String type;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String status;
  final String? location;
  final int? capacity;
  final String? preparationNotes;
  final List<Map<String, dynamic>> equipmentChecklist;
  final int attendanceCount;
  final List<SessionInstructor> instructors;

  bool get isEvent => type == 'event';

  factory ClassSession.fromMap(
    Map<String, dynamic> map, {
    int attendanceCount = 0,
  }) {
    final rawChecklist = map['equipment_checklist'];
    final checklist = rawChecklist is List
        ? rawChecklist.whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];
    return ClassSession(
      id: map['id'] as String,
      title: map['title'] as String,
      type: map['session_type'] as String? ?? 'class',
      startsAt: DateTime.parse(map['starts_at'] as String),
      endsAt: map['ends_at'] == null
          ? null
          : DateTime.parse(map['ends_at'] as String),
      status: map['status'] as String? ?? 'scheduled',
      location: map['location'] as String?,
      capacity: map['capacity'] as int?,
      preparationNotes: map['preparation_notes'] as String?,
      equipmentChecklist: checklist,
      attendanceCount: attendanceCount,
      instructors: (map['instructors'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SessionInstructor.fromMap)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id.isNotEmpty) 'id': id,
        'title': title.trim(),
        'session_type': type,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'status': status,
        'location': _emptyToNull(location),
        'capacity': capacity,
        'preparation_notes': _emptyToNull(preparationNotes),
        'equipment_checklist': equipmentChecklist,
      };
}

class SessionInstructor {
  const SessionInstructor({
    required this.profileId,
    required this.displayName,
    required this.role,
  });

  final String profileId;
  final String displayName;
  final String role;

  factory SessionInstructor.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>? ?? const {};
    return SessionInstructor(
      profileId: map['profile_id'] as String,
      displayName: profile['display_name'] as String? ?? '',
      role: map['role'] as String,
    );
  }

  Map<String, dynamic> toAssignmentMap() => {
        'profile_id': profileId,
        'role': role,
      };
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
