class RecurringEvent {
  const RecurringEvent({
    required this.id,
    required this.activityId,
    required this.title,
    required this.startsAt,
    required this.timeZone,
    required this.recurrenceRule,
    this.type = 'class',
    this.endsAt,
    this.repeatsUntil,
    this.location,
    this.capacity,
    this.preparationNotes,
  });

  final String id;
  final String activityId;
  final String title;
  final String type;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String timeZone;
  final Map<String, dynamic> recurrenceRule;
  final DateTime? repeatsUntil;
  final String? location;
  final int? capacity;
  final String? preparationNotes;

  factory RecurringEvent.fromMap(Map<String, dynamic> map) {
    final rawRule = map['recurrence_rule'];
    if (rawRule is! Map) {
      throw const FormatException('Règle de récurrence invalide.');
    }
    return RecurringEvent(
      id: map['id'] as String,
      activityId: map['activity_id'] as String,
      title: map['title'] as String,
      type: map['session_type'] as String? ?? 'class',
      startsAt: DateTime.parse(map['starts_at'] as String),
      endsAt: map['ends_at'] == null
          ? null
          : DateTime.parse(map['ends_at'] as String),
      timeZone: map['time_zone'] as String? ?? 'Europe/Paris',
      recurrenceRule: Map<String, dynamic>.from(rawRule),
      repeatsUntil: map['repeats_until'] == null
          ? null
          : DateTime.parse(map['repeats_until'] as String),
      location: map['location'] as String?,
      capacity: map['capacity'] as int?,
      preparationNotes: map['preparation_notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id.isNotEmpty) 'id': id,
        'activity_id': activityId,
        'title': title.trim(),
        'session_type': type,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'time_zone': timeZone,
        'recurrence_rule': recurrenceRule,
        'repeats_until': repeatsUntil?.toIso8601String().split('T').first,
        'location': _emptyToNull(location),
        'capacity': capacity,
        'preparation_notes': _emptyToNull(preparationNotes),
      };
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
