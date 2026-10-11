class Payment {
  const Payment({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.amount,
    required this.type,
    required this.method,
    required this.paidAt,
    this.receiptNumber,
    this.receiptUrl,
    this.notes,
  });

  final String id;
  final String memberId;
  final String memberName;
  final double amount;
  final String type;
  final String method;
  final DateTime paidAt;
  final String? receiptNumber;
  final String? receiptUrl;
  final String? notes;

  factory Payment.fromMap(Map<String, dynamic> map) {
    final member = map['members'] as Map<String, dynamic>?;
    return Payment(
      id: map['id'] as String,
      memberId: map['member_id'] as String,
      memberName: member == null
          ? 'Adhérent'
          : '${member['first_name']} ${member['last_name']}',
      amount: (map['amount'] as num).toDouble(),
      type: map['payment_type'] as String,
      method: map['payment_method'] as String,
      paidAt: DateTime.parse(map['paid_at'] as String),
      receiptNumber: map['receipt_number'] as String?,
      receiptUrl: map['receipt_url'] as String?,
      notes: map['notes'] as String?,
    );
  }
}

class PricingSettings {
  const PricingSettings({
    required this.annualMembershipFee,
    required this.singleClassPrice,
    required this.firstCardPrice,
    required this.renewalCardPrice,
    required this.cardPassCount,
    required this.currency,
  });

  final double annualMembershipFee;
  final double singleClassPrice;
  final double firstCardPrice;
  final double renewalCardPrice;
  final int cardPassCount;
  final String currency;

  factory PricingSettings.fromMap(Map<String, dynamic> map) => PricingSettings(
        annualMembershipFee:
            (map['annual_membership_fee'] as num).toDouble(),
        singleClassPrice: (map['single_class_price'] as num).toDouble(),
        firstCardPrice: (map['first_card_price'] as num).toDouble(),
        renewalCardPrice: (map['renewal_card_price'] as num).toDouble(),
        cardPassCount: map['card_pass_count'] as int,
        currency: map['currency'] as String? ?? 'EUR',
      );

  Map<String, dynamic> toMap() => {
        'id': 1,
        'annual_membership_fee': annualMembershipFee,
        'single_class_price': singleClassPrice,
        'first_card_price': firstCardPrice,
        'renewal_card_price': renewalCardPrice,
        'card_pass_count': cardPassCount,
        'currency': currency,
      };
}

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.code,
    required this.label,
    required this.period,
    required this.weeklyLimit,
    required this.price,
  });

  final String code;
  final String label;
  final String period;
  final int weeklyLimit;
  final double price;

  String get validityLabel => period == 'month' ? '30 jours' : '3 mois';

  factory SubscriptionPlan.fromMap(Map<String, dynamic> map) =>
      SubscriptionPlan(
        code: map['code'] as String,
        label: map['label'] as String,
        period: map['period'] as String,
        weeklyLimit: map['weekly_limit'] as int,
        price: (map['price'] as num).toDouble(),
      );
}
