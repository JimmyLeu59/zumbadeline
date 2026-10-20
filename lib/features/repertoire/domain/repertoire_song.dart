class RepertoireSong {
  const RepertoireSong({
    required this.id,
    required this.activityId,
    required this.title,
    this.composer = '',
    this.keySignature = '',
    this.vocalRange = '',
    this.vocalPart = '',
    this.accompaniment = '',
    this.durationSeconds = 0,
    this.rehearsalNotes,
    this.documentPath,
    this.lastPlayedAt,
  });

  final String id;
  final String activityId;
  final String title;
  final String composer;
  final String keySignature;
  final String vocalRange;
  final String vocalPart;
  final String accompaniment;
  final int durationSeconds;
  final String? rehearsalNotes;
  final String? documentPath;
  final DateTime? lastPlayedAt;

  Duration get duration => Duration(seconds: durationSeconds);

  factory RepertoireSong.fromMap(Map<String, dynamic> map) => RepertoireSong(
    id: map['id'] as String,
    activityId: map['activity_id'] as String,
    title: map['title'] as String,
    composer: map['composer'] as String? ?? '',
    keySignature: map['key_signature'] as String? ?? '',
    vocalRange: map['vocal_range'] as String? ?? '',
    vocalPart: map['vocal_part'] as String? ?? '',
    accompaniment: map['accompaniment'] as String? ?? '',
    durationSeconds: map['duration_seconds'] as int? ?? 0,
    rehearsalNotes: map['rehearsal_notes'] as String?,
    documentPath: map['document_path'] as String?,
    lastPlayedAt: map['last_played_at'] == null
        ? null
        : DateTime.parse(map['last_played_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    if (id.isNotEmpty) 'id': id,
    'activity_id': activityId,
    'title': title.trim(),
    'composer': composer.trim(),
    'key_signature': keySignature.trim(),
    'vocal_range': vocalRange.trim(),
    'vocal_part': vocalPart.trim(),
    'accompaniment': accompaniment.trim(),
    'duration_seconds': durationSeconds,
    'rehearsal_notes': _emptyToNull(rehearsalNotes),
    'document_path': documentPath,
  };
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
