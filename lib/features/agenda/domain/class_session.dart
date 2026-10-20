class ClassSession {
  const ClassSession({
    required this.id,
    required this.title,
    required this.type,
    required this.startsAt,
    required this.status,
    this.activityId,
    this.endsAt,
    this.location,
    this.capacity,
    this.preparationNotes,
    this.equipmentChecklist = const [],
    this.attendanceCount = 0,
    this.instructors = const [],
    this.recurringEventId,
    this.occurrenceKey,
    this.repeatsUntil,
    this.recurrenceInterval = 1,
  });

  final String id;
  final String title;
  final String type;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String status;
  final String? activityId;
  final String? location;
  final int? capacity;
  final String? preparationNotes;
  final List<Map<String, dynamic>> equipmentChecklist;
  final int attendanceCount;
  final List<SessionInstructor> instructors;
  final String? recurringEventId;
  final DateTime? occurrenceKey;
  final DateTime? repeatsUntil;
  final int recurrenceInterval;

  bool get isEvent => type == 'event';

  ClassSession copyWith({String? activityId}) => ClassSession(
    id: id,
    title: title,
    type: type,
    startsAt: startsAt,
    endsAt: endsAt,
    status: status,
    activityId: activityId ?? this.activityId,
    location: location,
    capacity: capacity,
    preparationNotes: preparationNotes,
    equipmentChecklist: equipmentChecklist,
    attendanceCount: attendanceCount,
    instructors: instructors,
    recurringEventId: recurringEventId,
    occurrenceKey: occurrenceKey,
    repeatsUntil: repeatsUntil,
    recurrenceInterval: recurrenceInterval,
  );

  factory ClassSession.fromMap(
    Map<String, dynamic> map, {
    int? attendanceCount,
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
      activityId: map['activity_id'] as String?,
      location: map['location'] as String?,
      capacity: map['capacity'] as int?,
      preparationNotes: map['preparation_notes'] as String?,
      equipmentChecklist: checklist,
      attendanceCount:
          attendanceCount ?? map['attendance_count'] as int? ?? 0,
      instructors: (map['instructors'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SessionInstructor.fromMap)
          .toList(growable: false),
      recurringEventId: map['recurring_event_id'] as String?,
      occurrenceKey: map['occurrence_key'] == null
          ? null
          : DateTime.parse(map['occurrence_key'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
    if (id.isNotEmpty) 'id': id,
    'title': title.trim(),
    'session_type': type,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
    'status': status,
    if (activityId != null) 'activity_id': activityId,
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
