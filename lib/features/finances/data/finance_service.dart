import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/payment.dart';

class FinanceService {
  FinanceService(this._client);

  final SupabaseClient _client;

  Future<List<Payment>> listPayments({
    int limit = 200,
    String? activityId,
  }) async {
    var query = _client
        .from('payments')
        .select(
          'id, member_id, amount, payment_type, payment_method, paid_at, receipt_number, receipt_url, notes, members!inner(first_name, last_name)',
        );
    if (activityId != null) query = query.eq('activity_id', activityId);
    final rows = await query.order('paid_at', ascending: false).limit(limit);
    return rows.map(Payment.fromMap).toList(growable: false);
  }

  Future<List<Payment>> listAllPayments({String? activityId}) async {
    const pageSize = 1000;
    final payments = <Payment>[];
    var offset = 0;
    while (true) {
      var query = _client
          .from('payments')
          .select(
            'id, member_id, amount, payment_type, payment_method, paid_at, receipt_number, receipt_url, notes, members!inner(first_name, last_name)',
          );
      if (activityId != null) query = query.eq('activity_id', activityId);
      final rows = await query
          .order('paid_at', ascending: false)
          .range(offset, offset + pageSize - 1);
      payments.addAll(rows.map(Payment.fromMap));
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    return payments;
  }

  Future<List<Payment>> paymentsForMember({
    required String memberId,
    required DateTime from,
    required DateTime through,
    String? activityId,
  }) async {
    if (through.isBefore(from)) {
      throw ArgumentError.value(through, 'through', 'Must not precede from');
    }
    final start = DateTime(from.year, from.month, from.day);
    final endExclusive = DateTime(through.year, through.month, through.day + 1);
    var query = _client
        .from('payments')
        .select(
          'id, member_id, amount, payment_type, payment_method, paid_at, receipt_number, receipt_url, notes, members!inner(first_name, last_name)',
        )
        .eq('member_id', memberId)
        .gte('paid_at', start.toUtc().toIso8601String())
        .lt('paid_at', endExclusive.toUtc().toIso8601String());
    if (activityId != null) query = query.eq('activity_id', activityId);
    final rows = await query.order('paid_at');
    return rows.map(Payment.fromMap).toList(growable: false);
  }

  Future<PricingSettings> getPricing() async {
    final row = await _client
        .from('pricing_settings')
        .select()
        .eq('id', 1)
        .single();
    return PricingSettings.fromMap(row);
  }

  Future<List<SubscriptionPlan>> listPlans() async {
    final rows = await _client
        .from('subscription_plans')
        .select()
        .eq('is_active', true)
        .order('period', ascending: false)
        .order('weekly_limit');
    return rows.map(SubscriptionPlan.fromMap).toList(growable: false);
  }

  Future<void> savePlanPrice(String code, double price) async {
    await _client
        .from('subscription_plans')
        .update({'price': price})
        .eq('code', code);
  }

  Future<void> savePricing(PricingSettings settings) async {
    await _client.from('pricing_settings').upsert(settings.toMap());
  }

  Future<Map<String, dynamic>> recordPayment({
    required String memberId,
    required String paymentType,
    required String paymentMethod,
    required double amount,
    required String operationId,
    String? notes,
  }) async {
    return _client.rpc(
      'record_payment',
      params: {
        'p_member_id': memberId,
        'p_payment_type': paymentType,
        'p_payment_method': paymentMethod,
        'p_amount': amount,
        'p_notes': notes,
        'p_offline_operation_id': operationId,
      },
    );
  }

  Future<Map<String, dynamic>> purchaseClassCard({
    required String memberId,
    required String paymentMethod,
    required String operationId,
  }) async {
    return _client.rpc(
      'purchase_class_card',
      params: {
        'p_member_id': memberId,
        'p_payment_method': paymentMethod,
        'p_offline_operation_id': operationId,
      },
    );
  }

  Future<Map<String, dynamic>> purchaseActivityCard({
    required String memberId,
    required String activityId,
    required String priceTier,
    required String paymentMethod,
    required String operationId,
    String? planCode,
  }) async {
    final response = await _client.rpc(
      'purchase_activity_card',
      params: {
        'p_member_id': memberId,
        'p_activity_id': activityId,
        'p_price_tier': priceTier,
        'p_payment_method': paymentMethod,
        'p_offline_operation_id': operationId,
        'p_plan_code': planCode,
      },
    );
    if (response is! Map) {
      throw const FormatException('Réponse invalide lors de la vente de carte.');
    }
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> recordActivityPayment({
    required String memberId,
    required String activityId,
    required String paymentType,
    required String paymentMethod,
    required double amount,
    required String operationId,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'record_activity_payment',
      params: {
        'p_member_id': memberId,
        'p_activity_id': activityId,
        'p_payment_type': paymentType,
        'p_payment_method': paymentMethod,
        'p_amount': amount,
        'p_notes': notes,
        'p_offline_operation_id': operationId,
      },
    );
    if (response is! Map) {
      throw const FormatException('Réponse invalide lors de l’encaissement.');
    }
    return Map<String, dynamic>.from(response);
  }

  Future<void> deletePayment(String paymentId) async {
    await _client.rpc('delete_payment', params: {'p_payment_id': paymentId});
  }
}
