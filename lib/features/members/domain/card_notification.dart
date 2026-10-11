class CardNotification {
  const CardNotification({
    required this.id,
    required this.cardId,
    required this.kind,
    required this.memberName,
    required this.activityName,
    required this.createdAt,
    this.expiresAt,
    this.readAt,
  });

  final String id;
  final String cardId;
  final String kind;
  final String memberName;
  final String activityName;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  String get title => switch (kind) {
    'expiry' => 'Carte bientôt expirée',
    'last_class' => 'Dernier cours sur la carte',
    _ => 'Rappel de carte',
  };

  String get message => switch (kind) {
    'expiry' =>
      '$memberName : la carte pour $activityName expire'
          '${expiresAt == null ? ' bientôt' : ' le ${_date(expiresAt!)}'}.',
    'last_class' =>
      '$memberName : il ne reste qu’un cours sur la carte pour $activityName.',
    _ => '$memberName · $activityName',
  };

  factory CardNotification.fromMap(Map<String, dynamic> map) {
    DateTime? date(String key) {
      final value = map[key] as String?;
      return value == null ? null : DateTime.parse(value).toLocal();
    }

    return CardNotification(
      id: map['id'] as String,
      cardId: map['card_id'] as String,
      kind: map['kind'] as String,
      memberName: map['member_name'] as String,
      activityName: map['activity_name'] as String,
      createdAt: date('created_at')!,
      expiresAt: date('expires_at'),
      readAt: date('read_at'),
    );
  }
}

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';
