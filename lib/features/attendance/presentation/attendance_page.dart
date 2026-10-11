import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/offline/offline_store.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../features/agenda/domain/class_session.dart';
import '../../../features/members/domain/member.dart';
import '../../finances/domain/payment.dart';

class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key, this.activityId, this.initialSession});

  final String? activityId;
  final ClassSession? initialSession;

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  String? _sessionId;
  String _search = '';
  String? _initialLetter;
  String? _checkingMemberId;
  Future<List<Map<String, dynamic>>>? _attendanceFuture;
  static const _uuid = Uuid();

  @override
  void initState() {
    super.initState();
    _sessionId = widget.initialSession?.id;
    if (_sessionId != null) _loadAttendance();
  }

  @override
  void didUpdateWidget(covariant AttendancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activityId != widget.activityId) {
      _sessionId = widget.initialSession?.id;
      _loadAttendance();
    }
  }

  void _loadAttendance() {
    final sessionId = _sessionId;
    if (sessionId == null) {
      _attendanceFuture = null;
      return;
    }
    _attendanceFuture = ref
        .read(sessionServiceProvider)
        .attendanceForSession(sessionId);
  }

  Future<void> _checkIn(Member member) async {
    final sessionId = _sessionId;
    if (sessionId == null || _checkingMemberId != null) return;
    setState(() => _checkingMemberId = member.id);
    try {
      final sessions = await ref.read(sessionsProvider(widget.activityId).future);
      final session = widget.initialSession ??
          sessions.where((item) => item.id == sessionId).firstOrNull;
      if (session == null) {
        throw StateError('La séance sélectionnée n’est plus disponible.');
      }
      final activityId = session.activityId ?? widget.activityId;
      if (activityId == null) {
        throw StateError('La séance n’est rattachée à aucune activité.');
      }
      final cards = await ref
          .read(memberServiceProvider)
          .usableCards(member.id, activityId: activityId);
      if (!mounted) return;
      final isOnline = await ref.read(offlineStoreProvider).isOnline();
      var plans = const <SubscriptionPlan>[];
      PricingSettings? pricing;
      if (isOnline && cards.isEmpty) {
        try {
          plans = await ref.read(subscriptionPlansProvider.future);
          pricing = await ref.read(pricingProvider.future);
        } catch (error) {
          throw StateError('Chargement des tarifs impossible : $error');
        }
      }
      if (!mounted) return;
      final choice = cards.isNotEmpty
          ? _CheckInChoice(
              cardId: cards.first['id'] as String,
              paymentMethod: 'cash',
            )
          : await showDialog<_CheckInChoice>(
              context: context,
              builder: (_) => _QuickCheckInDialog(
                online: isOnline,
                plans: plans,
                pricing: pricing,
              ),
            );
      if (choice == null || !mounted) return;
      var cardId = choice.cardId;
      var alreadyCheckedIn = false;
      if (choice.priceTier != null) {
        final sale = await ref
            .read(sessionServiceProvider)
            .purchaseCardAndCheckIn(
              sessionId: sessionId,
              memberId: member.id,
              priceTier: choice.priceTier!,
              planCode: choice.planCode,
              paymentMethod: choice.paymentMethod,
              operationId: _uuid.v4(),
            );
        alreadyCheckedIn = sale['already_checked_in'] == true;
        if (!alreadyCheckedIn) {
          final card = sale['card'];
          if (card is! Map || card['id'] is! String) {
            throw const FormatException(
              'Le pointage n’a pas retourné la carte créée.',
            );
          }
          cardId = card['id'] as String;
        }
      } else {
        await ref
            .read(sessionServiceProvider)
            .checkIn(
              sessionId: sessionId,
              memberId: member.id,
              cardId: cardId,
              paymentMethod: choice.paymentMethod,
              operationId: _uuid.v4(),
            );
      }
      ref.invalidate(membersForActivityProvider(widget.activityId));
      if (!mounted) return;
      setState(_loadAttendance);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              alreadyCheckedIn
                  ? '${member.firstName} était déjà pointé(e) pour cette séance.'
                  : cardId == null
                  ? '${member.firstName} : présence enregistrée et cours payé.'
                  : choice.priceTier != null
                  ? '${member.firstName} : carte vendue et présence enregistrée.'
                  : '${member.firstName} : présence enregistrée, carte débitée.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _checkingMemberId = null);
    }
  }

  void _showError(Object error) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pointage impossible'),
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

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider(widget.activityId));
    final members = ref.watch(membersForActivityProvider(widget.activityId));
    final offlineStatus = ref.watch(offlineStatusProvider).valueOrNull;
    return sessions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          _Retry(
            error: error,
            onRetry: () =>
                ref.invalidate(sessionsProvider(widget.activityId)),
          ),
      data: (allSessions) {
        final options = allSessions
            .where((session) => session.status != 'cancelled')
            .toList();
        final selectedSession = options
            .where((session) => session.id == _sessionId)
            .firstOrNull;
        if (selectedSession == null && widget.initialSession == null) {
          return _selectSessionPrompt(options);
        }
        if (selectedSession == null && widget.initialSession != null) {
          return _attendanceForInitialSession(members, offlineStatus);
        }
        return _buildCheckIn(selectedSession!, members, offlineStatus);
      },
    );
  }

  Widget _selectSessionPrompt(List<ClassSession> sessions) {
    if (sessions.isEmpty) {
      return const Center(
        child: Text('Aucune séance disponible pour le pointage.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Choisir une séance'),
            items: [
              for (final session in sessions)
                DropdownMenuItem(
                  value: session.id,
                  child: Text(
                    '${_dateLabel(session.startsAt)} · ${session.title}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) {
              setState(() {
                _sessionId = id;
                _loadAttendance();
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _attendanceForInitialSession(
    AsyncValue<List<Member>> members,
    OfflineStatus? offlineStatus,
  ) {
    final session = widget.initialSession!;
    return Column(
      children: [
        _SessionHeader(session: session),
        _offlineBanner(offlineStatus),
        Expanded(child: _membersList(members, session.id)),
      ],
    );
  }

  Widget _buildCheckIn(
    ClassSession session,
    AsyncValue<List<Member>> members,
    OfflineStatus? offlineStatus,
  ) {
    return Column(
      children: [
        _SessionHeader(session: session),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Rechercher un adhérent',
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final letter in <String?>[
                null,
                ...List.generate(26, (index) => String.fromCharCode(65 + index)),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(letter ?? 'Tous'),
                    selected: _initialLetter == letter,
                    onSelected: (_) => setState(() => _initialLetter = letter),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        _offlineBanner(offlineStatus),
        Expanded(child: _membersList(members, session.id)),
      ],
    );
  }

  Widget _offlineBanner(OfflineStatus? status) {
    if (status == null ||
        (status.isOnline &&
            status.pendingCheckIns == 0 &&
            status.lastError == null)) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final message = !status.isOnline
        ? 'Hors-ligne · les pointages seront synchronisés au retour du réseau.'
        : status.pendingCheckIns > 0
        ? '${status.pendingCheckIns} pointage(s) en attente de synchronisation.'
        : 'Erreur de synchronisation : ${status.lastError}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (status.lastError == null ? colors.secondary : colors.error)
            .withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message),
    );
  }

  Widget _membersList(AsyncValue<List<Member>> members, String sessionId) {
    return members.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          _Retry(
            error: error,
            onRetry: () => ref.invalidate(
              membersForActivityProvider(widget.activityId),
            ),
          ),
      data: (allMembers) {
        final query = _search.trim().toLowerCase();
        final visible = allMembers.where((member) {
          return member.isActive &&
              (_initialLetter == null ||
                  member.lastName
                      .toUpperCase()
                      .startsWith(_initialLetter!)) &&
              (query.isEmpty ||
                  member.fullName.toLowerCase().contains(query) ||
                  (member.phone?.contains(query) ?? false));
        }).toList();
        return FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey(sessionId),
          future: _attendanceFuture ??= ref
              .read(sessionServiceProvider)
              .attendanceForSession(sessionId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _Retry(
                error: snapshot.error!,
                onRetry: () => setState(_loadAttendance),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final checkedInIds = snapshot.data!
                .map((row) => row['member_id'] as String)
                .toSet();
            final checkedInCount = checkedInIds.length;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$checkedInCount présent(s) · '
                          '${visible.length} adhérent(s)',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Exporter la feuille d’émargement PDF',
                        onPressed: () => _exportAttendance(
                          sessionId,
                          allMembers.where((member) => member.isActive).toList(),
                          snapshot.data!,
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final member = visible[index];
                      final isCheckedIn = checkedInIds.contains(member.id);
                      final isLoading = member.id == _checkingMemberId;
                      return Card(
                        child: ListTile(
                          minVerticalPadding: 14,
                          leading: CircleAvatar(
                            child: Text(member.firstName[0].toUpperCase()),
                          ),
                          title: Text(member.fullName),
                          subtitle: Text(
                            '${member.remainingPasses} passage(s) disponible(s)',
                          ),
                          trailing: isCheckedIn
                              ? const Chip(
                                  avatar: Icon(Icons.check, size: 18),
                                  label: Text('Présent'),
                                )
                              : FilledButton.tonalIcon(
                                  onPressed:
                                      _checkingMemberId == null && !isLoading
                                      ? () => _checkIn(member)
                                      : null,
                                  icon: isLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.how_to_reg),
                                  label: const Text('Pointer'),
                                ),
                          onTap: isCheckedIn || _checkingMemberId != null
                              ? null
                              : () => _checkIn(member),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportAttendance(
    String sessionId,
    List<Member> members,
    List<Map<String, dynamic>> attendees,
  ) async {
    final session = widget.initialSession ??
        (await ref.read(sessionsProvider(widget.activityId).future)).where(
              (item) => item.id == sessionId,
            ).firstOrNull;
    if (session == null) return;
    try {
      await ref.read(reportServiceProvider).shareAttendancePdf(
            session: session,
            members: members,
            attendances: attendees,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export PDF impossible : $error')),
        );
      }
    }
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({required this.session});
  final ClassSession session;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Text(
      '${session.title} · ${_dateLabel(session.startsAt)} '
      '${session.startsAt.hour.toString().padLeft(2, '0')}:'
      '${session.startsAt.minute.toString().padLeft(2, '0')}',
      style: Theme.of(context).textTheme.titleLarge,
    ),
  );
}

class _CheckInChoice {
  const _CheckInChoice({
    required this.cardId,
    required this.paymentMethod,
    this.priceTier,
    this.planCode,
  });

  final String? cardId;
  final String? priceTier;
  final String? planCode;
  final String paymentMethod;
}

class _QuickCheckInDialog extends StatefulWidget {
  const _QuickCheckInDialog({
    required this.online,
    required this.plans,
    required this.pricing,
  });

  final bool online;
  final List<SubscriptionPlan> plans;
  final PricingSettings? pricing;
  @override
  State<_QuickCheckInDialog> createState() => _QuickCheckInDialogState();
}

class _QuickCheckInDialogState extends State<_QuickCheckInDialog> {
  String _paymentMethod = 'cash';
  String? _planCode;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Plus de cours sur la carte'),
    content: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Text(
            widget.online
                ? 'Choisissez une carte ou réglez ce cours à l’unité.'
                : 'Hors-ligne : le cours à l’unité sera synchronisé plus tard. '
                    'La vente de carte nécessite une connexion.',
          ),
          const SizedBox(height: 18),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash', label: Text('Espèces')),
              ButtonSegment(value: 'cheque', label: Text('Chèque')),
              ButtonSegment(value: 'card', label: Text('CB')),
            ],
            selected: {_paymentMethod},
            onSelectionChanged: (value) =>
                setState(() => _paymentMethod = value.first),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: widget.online
                ? () => Navigator.pop(
                    context,
                    _CheckInChoice(
                      cardId: null,
                      priceTier: 'standard',
                      paymentMethod: _paymentMethod,
                    ),
                  )
                : null,
            icon: const Icon(Icons.local_activity_outlined),
            label: Text(
              widget.pricing == null
                  ? 'Carte standard · tarif indisponible'
                  : 'Carte standard · ${widget.pricing!.cardPassCount} cours · '
                        '${_money(widget.pricing!.firstCardPrice)}',
            ),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: widget.online
                ? () => Navigator.pop(
                    context,
                    _CheckInChoice(
                      cardId: null,
                      priceTier: 'loyalty',
                      paymentMethod: _paymentMethod,
                    ),
                  )
                : null,
            icon: const Icon(Icons.replay_rounded),
            label: Text(
              widget.pricing == null
                  ? 'Carte fidélité · tarif indisponible'
                  : 'Carte fidélité · ${widget.pricing!.cardPassCount} cours · '
                        '${_money(widget.pricing!.renewalCardPrice)}',
            ),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
          ),
          const SizedBox(height: 8),
          if (widget.online && widget.plans.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue: _planCode,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Forfait mensuel / trimestriel',
              ),
              items: [
                for (final plan in widget.plans)
                  DropdownMenuItem(
                    value: plan.code,
                    child: Text(
                      '${plan.label} · ${plan.price.toStringAsFixed(0)} €',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _planCode = value),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _planCode == null
                  ? null
                  : () => Navigator.pop(
                      context,
                      _CheckInChoice(
                        cardId: null,
                        priceTier: 'standard',
                        planCode: _planCode,
                        paymentMethod: _paymentMethod,
                      ),
                    ),
              icon: const Icon(Icons.event_repeat_outlined),
              label: const Text('Vendre le forfait'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(
              context,
              _CheckInChoice(
                cardId: null,
                paymentMethod: _paymentMethod,
              ),
            ),
            icon: const Icon(Icons.payments_outlined),
            label: Text(
              widget.pricing == null
                  ? 'Cours à l’unité · tarif serveur'
                  : 'Cours à l’unité · '
                        '${_money(widget.pricing!.singleClassPrice)}',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
            ),
          ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Retour'),
      ),
    ],
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(error.toString(), textAlign: TextAlign.center),
          OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    ),
  );
}

String _dateLabel(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _money(double amount) => '${amount.toStringAsFixed(2)} €';
