class Member {
  const Member({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.isActive,
    this.phone,
    this.email,
    this.birthDate,
    this.photoUrl,
    this.membershipValidUntil,
    this.medicalCertificateUrl,
    this.medicalCertificateValidUntil,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.notes,
    this.remainingPasses = 0,
    this.subscriptionUntil,
    this.cardExpiringAt,
    this.cardHasLastClass = false,
    this.activityIds = const [],
    this.activityNames = const [],
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? phone;
  final String? email;
  final DateTime? birthDate;
  final String? photoUrl;
  final DateTime? membershipValidUntil;
  final String? medicalCertificateUrl;
  final DateTime? medicalCertificateValidUntil;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? notes;
  final bool isActive;
  final int remainingPasses;
  final DateTime? subscriptionUntil;
  final DateTime? cardExpiringAt;
  final bool cardHasLastClass;
  final List<String> activityIds;
  final List<String> activityNames;

  String get fullName => '$firstName $lastName';
  int? get membershipDaysRemaining =>
      _daysUntil(membershipValidUntil);
  int? get subscriptionDaysRemaining => _daysUntil(subscriptionUntil);

  bool get membershipIsCurrent {
    final validUntil = membershipValidUntil;
    if (validUntil == null) return false;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return !validUntil.isBefore(todayDate);
  }

  int? _daysUntil(DateTime? expiryDate) {
    if (expiryDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(
      expiryDate.year,
      expiryDate.month,
      expiryDate.day,
    );
    return expiry.difference(today).inDays;
  }

  factory Member.fromMap(
    Map<String, dynamic> map, {
    int remainingPasses = 0,
    DateTime? subscriptionUntil,
    DateTime? cardExpiringAt,
    bool cardHasLastClass = false,
  }) {
    DateTime? date(String key) {
      final value = map[key] as String?;
      return value == null ? null : DateTime.tryParse(value);
    }

    return Member(
      id: map['id'] as String,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      birthDate: date('birth_date'),
      photoUrl: map['photo_url'] as String?,
      membershipValidUntil: date('membership_valid_until'),
      medicalCertificateUrl: map['medical_certificate_url'] as String?,
      medicalCertificateValidUntil: date('medical_certificate_valid_until'),
      emergencyContactName: map['emergency_contact_name'] as String?,
      emergencyContactPhone: map['emergency_contact_phone'] as String?,
      notes: map['notes'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      remainingPasses: remainingPasses,
      subscriptionUntil: subscriptionUntil,
      cardExpiringAt: cardExpiringAt,
      cardHasLastClass: cardHasLastClass,
      activityIds: (map['activity_ids'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(growable: false),
      activityNames: (map['activity_names'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toMap() => {
    if (id.isNotEmpty) 'id': id,
    'first_name': firstName.trim(),
    'last_name': lastName.trim(),
    'phone': _nullIfEmpty(phone),
    'email': _nullIfEmpty(email),
    'birth_date': birthDate?.toIso8601String().split('T').first,
    'photo_url': photoUrl,
    'membership_valid_until': membershipValidUntil
        ?.toIso8601String()
        .split('T')
        .first,
    'medical_certificate_url': medicalCertificateUrl,
    'medical_certificate_valid_until': medicalCertificateValidUntil
        ?.toIso8601String()
        .split('T')
        .first,
    'emergency_contact_name': _nullIfEmpty(emergencyContactName),
    'emergency_contact_phone': _nullIfEmpty(emergencyContactPhone),
    'notes': _nullIfEmpty(notes),
    'is_active': isActive,
  };
}

String? _nullIfEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
