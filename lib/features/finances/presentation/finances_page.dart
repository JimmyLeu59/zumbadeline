import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../members/domain/member.dart';
import '../domain/payment.dart';

class FinancesPage extends ConsumerWidget {
  const FinancesPage({this.activityId, super.key});

  final String? activityId;

  Future<void> _newPayment(BuildContext context, WidgetRef ref) async {
    late final List<Member> activeMembers;
    late final PricingSettings pricing;
    late final List<SubscriptionPlan> plans;
    try {
      final members = await ref.read(
        membersForActivityProvider(activityId).future,
      );
      activeMembers = members.where((member) => member.isActive).toList();
      pricing = await ref.read(pricingProvider.future);
      plans = await ref.read(subscriptionPlansProvider.future);
    } catch (error) {
      if (context.mounted) _showError(context, error);
      return;
    }
    if (!context.mounted) return;
    if (activeMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoutez d’abord un adhérent actif.')),
      );
      return;
    }
    final result = await showDialog<_PaymentRequest>(
      context: context,
      builder: (_) => _PaymentDialog(
        members: activeMembers,
        pricing: pricing,
        plans: plans,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      final service = ref.read(financeServiceProvider);
      if (result.type == 'class_card') {
        if (activityId == null) {
          throw StateError(
            'Sélectionnez une activité avant de vendre une carte.',
          );
        }
        await service.purchaseActivityCard(
          memberId: result.member.id,
          activityId: activityId!,
          priceTier: result.priceTier!,
          planCode: result.planCode,
          paymentMethod: result.method,
          operationId: const Uuid().v4(),
        );
      } else if (activityId != null && result.type != 'membership') {
        await service.recordActivityPayment(
          memberId: result.member.id,
          activityId: activityId!,
          paymentType: result.type,
          paymentMethod: result.method,
          amount: result.amount!,
          notes: result.notes,
          operationId: const Uuid().v4(),
        );
      } else {
        await service.recordPayment(
          memberId: result.member.id,
          paymentType: result.type,
          paymentMethod: result.method,
          amount: result.amount!,
          notes: result.notes,
          operationId: const Uuid().v4(),
        );
      }
      ref.invalidate(paymentsProvider(activityId));
      ref.invalidate(membersForActivityProvider(activityId));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Paiement enregistré.')));
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _exportFinance(
    BuildContext context,
    WidgetRef ref, {
    required bool excel,
  }) async {
    try {
      final payments = await ref
          .read(financeServiceProvider)
          .listAllPayments(activityId: activityId);
      final reports = ref.read(reportServiceProvider);
      if (excel) {
        await reports.shareFinanceExcel(payments);
      } else {
        await reports.shareFinancePdf(payments);
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _createMemberInvoice(BuildContext context, WidgetRef ref) async {
    try {
      final members = await ref.read(
        membersForActivityProvider(activityId).future,
      );
      if (!context.mounted) return;
      if (members.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun adhérent disponible.')),
        );
        return;
      }
      final request = await showDialog<_InvoiceRequest>(
        context: context,
        builder: (_) => _InvoiceDialog(members: members),
      );
      if (request == null || !context.mounted) return;
      final payments = await ref
          .read(financeServiceProvider)
          .paymentsForMember(
            memberId: request.member.id,
            from: request.period.start,
            through: request.period.end,
            activityId: activityId,
          );
      if (!context.mounted) return;
      if (payments.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucun paiement enregistré sur cette période.'),
          ),
        );
        return;
      }
      await ref
          .read(reportServiceProvider)
          .shareMemberInvoicePdf(
            member: request.member,
            payments: payments,
            from: request.period.start,
            through: request.period.end,
          );
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _deletePayment(
    BuildContext context,
    WidgetRef ref,
    Payment payment,
  ) async {
    final isCardPurchase = payment.type == 'class_card';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce paiement ?'),
        content: Text(
          isCardPurchase
              ? 'Le paiement de ${_money(payment.amount)} associé à '
                    '${payment.memberName} sera supprimé. La carte liée sera '
                    'également supprimée uniquement si aucun passage n’a été '
                    'utilisé; sinon l’opération sera refusée.'
              : 'Le paiement de ${_money(payment.amount)} enregistré pour '
                    '${payment.memberName} sera définitivement supprimé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(financeServiceProvider).deletePayment(payment.id);
      ref.invalidate(paymentsProvider(activityId));
      ref.invalidate(membersForActivityProvider(activityId));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Paiement supprimé.')));
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(paymentsProvider(activityId));
    final pricing = ref.watch(pricingProvider);
    final plans = ref.watch(subscriptionPlansProvider);
    final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    final canManageFinance =
        userId != null &&
        ref
                .watch(userProfileProvider(userId))
                .valueOrNull
                ?.canViewGlobalFinances ==
            true;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newPayment(context, ref),
        icon: const Icon(Icons.add_card),
        label: const Text('Nouveau paiement'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: pricing.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Tarifs indisponibles'),
                  subtitle: Text(error.toString()),
                  trailing: IconButton(
                    onPressed: () => ref.invalidate(pricingProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ),
              data: (value) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _PriceChip(
                    label: 'Adhésion',
                    amount: value.annualMembershipFee,
                  ),
                  _PriceChip(label: 'Unité', amount: value.singleClassPrice),
                  _PriceChip(label: '1re carte', amount: value.firstCardPrice),
                  _PriceChip(
                    label: 'Renouvellement',
                    amount: value.renewalCardPrice,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: plans.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Forfaits indisponibles'),
                  subtitle: Text(error.toString()),
                  trailing: IconButton(
                    onPressed: () => ref.invalidate(subscriptionPlansProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ),
              data: (items) => items.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Forfaits disponibles',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final plan in items)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _PriceChip(
                                    label:
                                        '${plan.label} (${plan.validityLabel})',
                                    amount: plan.price,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _createMemberInvoice(context, ref),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Facture adhérent'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _exportFinance(context, ref, excel: false),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Bilan PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _exportFinance(context, ref, excel: true),
                    icon: const Icon(Icons.table_view_outlined),
                    label: const Text('Bilan Excel'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: payments.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _FinanceError(
                error: error,
                onRetry: () => ref.invalidate(paymentsProvider(activityId)),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Center(
                    child: Text('Aucun paiement enregistré.'),
                  );
                }
                final total = rows.fold<double>(
                  0,
                  (sum, payment) => sum + payment.amount,
                );
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Total des ${rows.length} derniers paiements : '
                          '${_money(total)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final payment = rows[index];
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.euro_rounded),
                              ),
                              title: Text(payment.memberName),
                              subtitle: Text(
                                '${_paymentTypeLabel(payment.type)} · '
                                '${_paymentMethodLabel(payment.method)} · '
                                '${_dateLabel(payment.paidAt)}'
                                '${payment.receiptNumber == null ? '' : '\nReçu ${payment.receiptNumber}'}',
                              ),
                              isThreeLine: payment.receiptNumber != null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _money(payment.amount),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  if (canManageFinance)
                                    PopupMenuButton<String>(
                                      tooltip: 'Actions paiement',
                                      onSelected: (value) {
                                        if (value == 'delete') {
                                          _deletePayment(context, ref, payment);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Supprimer le paiement'),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRequest {
  const _PaymentRequest({
    required this.member,
    required this.type,
    required this.method,
    this.amount,
    this.notes,
    this.priceTier,
    this.planCode,
  });

  final Member member;
  final String type;
  final String method;
  final double? amount;
  final String? notes;
  final String? priceTier;
  final String? planCode;
}

class _InvoiceRequest {
  const _InvoiceRequest({required this.member, required this.period});

  final Member member;
  final DateTimeRange period;
}

class _InvoiceDialog extends StatefulWidget {
  const _InvoiceDialog({required this.members});

  final List<Member> members;

  @override
  State<_InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<_InvoiceDialog> {
  late Member _member = widget.members.first;
  late DateTimeRange _period = _defaultPeriod();

  DateTimeRange _defaultPeriod() {
    final now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month), end: now);
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _period,
      helpText: 'Choisir la période de facturation',
      confirmText: 'Valider la période',
    );
    if (range != null) setState(() => _period = range);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Facture acquittée par adhérent'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<Member>(
            initialValue: _member,
            decoration: const InputDecoration(labelText: 'Adhérent'),
            items: [
              for (final member in widget.members)
                DropdownMenuItem(value: member, child: Text(member.fullName)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _member = value);
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickPeriod,
            icon: const Icon(Icons.date_range_outlined),
            label: Text('${_date(_period.start)} – ${_date(_period.end)}'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Le PDF reprend les paiements enregistrés dans cette période et '
            'leurs références de reçu.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(
          context,
          _InvoiceRequest(member: _member, period: _period),
        ),
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('Générer le PDF'),
      ),
    ],
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.members,
    required this.pricing,
    required this.plans,
  });
  final List<Member> members;
  final PricingSettings pricing;
  final List<SubscriptionPlan> plans;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late Member _member = widget.members.first;
  String _type = 'class_card';
  String _method = 'cash';
  String _offer = 'standard';
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enregistrer un paiement'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<Member>(
              initialValue: _member,
              decoration: const InputDecoration(labelText: 'Adhérent'),
              items: [
                for (final member in widget.members)
                  DropdownMenuItem(value: member, child: Text(member.fullName)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _member = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(
                  value: 'class_card',
                  child: Text('Carte de cours'),
                ),
                DropdownMenuItem(
                  value: 'membership',
                  child: Text('Cotisation annuelle'),
                ),
                DropdownMenuItem(
                  value: 'single_class',
                  child: Text('Cours à l’unité'),
                ),
                DropdownMenuItem(value: 'event', child: Text('Événement')),
                DropdownMenuItem(value: 'other', child: Text('Autre')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _type = value;
                    final configuredAmount = switch (value) {
                      'membership' => widget.pricing.annualMembershipFee,
                      'single_class' => widget.pricing.singleClassPrice,
                      _ => null,
                    };
                    if (configuredAmount != null) {
                      _amount.text = configuredAmount.toStringAsFixed(2);
                      _amountError = null;
                    }
                  });
                }
              },
            ),
            if (_type != 'class_card') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                readOnly: _type == 'membership' || _type == 'single_class',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _type == 'membership' || _type == 'single_class'
                      ? 'Tarif configuré (€)'
                      : 'Montant en euros',
                  errorText: _amountError,
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Moyen de paiement'),
              items: [
                for (final method in _paymentMethods)
                  DropdownMenuItem(value: method.$1, child: Text(method.$2)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Note (facultatif)'),
            ),
            if (_type == 'class_card') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _offer,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Formule'),
                items: [
                  DropdownMenuItem(
                    value: 'standard',
                    child: Text(
                      '${widget.pricing.cardPassCount} cours, sans limite de '
                      'date · ${_money(widget.pricing.firstCardPrice)}',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'loyalty',
                    child: Text(
                      '${widget.pricing.cardPassCount} cours, tarif fidélité · '
                      '${_money(widget.pricing.renewalCardPrice)}',
                    ),
                  ),
                  for (final plan in widget.plans)
                    DropdownMenuItem(
                      value: plan.code,
                      child: Text(
                        '${plan.label} (${plan.validityLabel}) · '
                        '${_money(plan.price)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _offer = value);
                },
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Les forfaits sont valables 30 jours (mensuel) ou 3 mois '
                  '(trimestriel) à partir de la vente.',
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Retour'),
      ),
      FilledButton(
        onPressed: () {
          if (_type != 'class_card') {
            final parsed = double.tryParse(_amount.text.replaceAll(',', '.'));
            if (parsed == null || parsed < 0) {
              setState(() => _amountError = 'Montant invalide.');
              return;
            }
            Navigator.pop(
              context,
              _PaymentRequest(
                member: _member,
                type: _type,
                method: _method,
                amount: parsed,
                notes: _notes.text,
              ),
            );
          } else {
            Navigator.pop(
              context,
              _PaymentRequest(
                member: _member,
                type: _type,
                method: _method,
                notes: _notes.text,
                priceTier: _offer == 'loyalty' ? 'loyalty' : 'standard',
                planCode: _offer == 'standard' || _offer == 'loyalty'
                    ? null
                    : _offer,
              ),
            );
          }
        },
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({required this.label, required this.amount});
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: const Icon(Icons.sell_outlined, size: 18),
    label: Text('$label · ${_money(amount)}'),
  );
}

class _FinanceError extends StatelessWidget {
  const _FinanceError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Impossible de charger les paiements'),
        Padding(
          padding: const EdgeInsets.all(8),
          child: SelectableText(error.toString()),
        ),
        OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    ),
  );
}

const _paymentMethods = [
  ('cash', 'Espèces'),
  ('cheque', 'Chèque'),
  ('bank_transfer', 'Virement'),
  ('card', 'Carte bancaire'),
];

void _showError(BuildContext context, Object error) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Opération impossible'),
      content: SelectableText(error.toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}

String _money(double amount) => '${amount.toStringAsFixed(2)} €';

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _paymentTypeLabel(String value) => switch (value) {
  'membership' => 'Cotisation',
  'single_class' => 'Cours à l’unité',
  'class_card' => 'Carte de cours',
  'event' => 'Événement',
  _ => 'Autre',
};

String _paymentMethodLabel(String value) => switch (value) {
  'cash' => 'Espèces',
  'cheque' => 'Chèque',
  'bank_transfer' => 'Virement',
  'card' => 'CB',
  _ => value,
};
