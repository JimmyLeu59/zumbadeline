enum DanceStyle { salsa, merengue, reggaeton, bachata, cumbia, other }

enum CardioIntensity { warmUp, moderate, high, coolDown }

enum ChoreographyDocumentType { photo, pdf }

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.style,
    required this.duration,
    required this.intensity,
    this.documentUrl,
    this.documentType,
    this.teachingNotes,
    this.lastPlayedAt,
    this.spotifyUrl,
    this.activityId,
    this.localDocumentPath,
  });

  final String id;
  final String title;
  final String artist;
  final DanceStyle style;
  final Duration duration;
  final CardioIntensity intensity;
  final String? documentUrl;
  final ChoreographyDocumentType? documentType;
  final String? teachingNotes;
  final DateTime? lastPlayedAt;
  final String? spotifyUrl;
  final String? activityId;
  final String? localDocumentPath;

  Track copyWith({String? activityId}) => Track(
    id: id,
    title: title,
    artist: artist,
    style: style,
    duration: duration,
    intensity: intensity,
    documentUrl: documentUrl,
    documentType: documentType,
    teachingNotes: teachingNotes,
    lastPlayedAt: lastPlayedAt,
    spotifyUrl: spotifyUrl,
    activityId: activityId ?? this.activityId,
    localDocumentPath: localDocumentPath,
  );

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String? ?? '',
      style: _enumByName(DanceStyle.values, map['style'] as String? ?? 'other'),
      duration: Duration(seconds: map['duration_seconds'] as int? ?? 0),
      intensity: _enumByName(
        CardioIntensity.values,
        map['intensity'] as String? ?? 'moderate',
      ),
      documentUrl: map['document_url'] as String?,
      documentType: _optionalEnumByName(
        ChoreographyDocumentType.values,
        map['document_type'] as String?,
      ),
      teachingNotes: map['teaching_notes'] as String?,
      lastPlayedAt: map['last_played_at'] == null
          ? null
          : DateTime.parse(map['last_played_at'] as String),
      spotifyUrl: map['spotify_url'] as String?,
      activityId: map['activity_id'] as String?,
      localDocumentPath: map['local_document_path'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id.isNotEmpty) 'id': id,
    'title': title,
    'artist': artist,
    'style': style.name,
    'duration_seconds': duration.inSeconds,
    'intensity': intensity.name,
    'document_url': documentUrl,
    'document_type': documentType?.name,
    'teaching_notes': teachingNotes,
    'last_played_at': lastPlayedAt?.toIso8601String(),
    'spotify_url': _emptyToNull(spotifyUrl),
    if (activityId != null) 'activity_id': activityId,
  };
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

T _enumByName<T extends Enum>(List<T> values, String? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Unknown ${T.toString()} value: $name');
}

T? _optionalEnumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  return _enumByName(values, name);
}
