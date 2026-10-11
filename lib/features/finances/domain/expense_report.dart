enum ExpenseReportStatus {
  pending,
  approved,
  rejected,
  reimbursed;

  static ExpenseReportStatus fromValue(String value) {
    return ExpenseReportStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => throw FormatException('Statut de frais inconnu : $value'),
    );
  }
}

class ExpenseReport {
  const ExpenseReport({
    required this.id,
    required this.userId,
    required this.amount,
    required this.description,
    required this.status,
    required this.incurredAt,
    this.activityId,
    this.receiptPath,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNotes,
  });

  final String id;
  final String userId;
  final String? activityId;
  final double amount;
  final String description;
  final ExpenseReportStatus status;
  final String? receiptPath;
  final DateTime incurredAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNotes;

  factory ExpenseReport.fromMap(Map<String, dynamic> map) => ExpenseReport(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    activityId: map['activity_id'] as String?,
    amount: (map['amount'] as num).toDouble(),
    description: map['description'] as String,
    status: ExpenseReportStatus.fromValue(map['status'] as String),
    receiptPath: map['receipt_path'] as String?,
    incurredAt: DateTime.parse(map['incurred_at'] as String),
    reviewedBy: map['reviewed_by'] as String?,
    reviewedAt: map['reviewed_at'] == null
        ? null
        : DateTime.parse(map['reviewed_at'] as String),
    reviewNotes: map['review_notes'] as String?,
  );

  Map<String, dynamic> toMap() => {
    if (id.isNotEmpty) 'id': id,
    'user_id': userId,
    'activity_id': activityId,
    'amount': amount,
    'description': description.trim(),
    'status': status.name,
    'receipt_path': receiptPath,
    'incurred_at': incurredAt.toIso8601String().split('T').first,
    'reviewed_by': reviewedBy,
    'reviewed_at': reviewedAt?.toUtc().toIso8601String(),
    'review_notes': reviewNotes,
  };
}
