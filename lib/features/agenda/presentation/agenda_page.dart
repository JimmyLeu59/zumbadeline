import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../staff/domain/app_user_profile.dart';
import '../data/session_service.dart';
import '../domain/class_session.dart';

class AgendaPage extends ConsumerStatefulWidget {
  const AgendaPage({super.key, this.onOpenAttendance});

  final ValueChanged<ClassSession>? onOpenAttendance;

  @override
  ConsumerState<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends ConsumerState<AgendaPage> {
  Future<void> _addSession() async {
    final staff = await _loadStaffProfiles();
    if (staff == null || !mounted) return;
    final session = await showDialog<ClassSession>(
      context: context,
      builder: (_) => _SessionFormDialog(instructors: staff),
    );
    if (session == null || !mounted) return;
    await _saveSession(session);
  }

  Future<void> _editSession(ClassSession existing) async {
    final staff = await _loadStaffProfiles();
    if (staff == null || !mounted) return;
    final session = await showDialog<ClassSession>(
      context: context,
      builder: (_) => _SessionFormDialog(
        session: existing,
        instructors: staff,
      ),
    );
    if (session == null) return;
    await _saveSession(session);
  }

  Future<List<AppUserProfile>?> _loadStaffProfiles() async {
    try {
      return await ref.read(staffProfilesProvider.future);
    } catch (error) {
      if (mounted) _showError(error);
      return null;
    }
  }

  Future<void> _saveSession(ClassSession session) async {
    try {
      await ref.read(sessionServiceProvider).saveSession(session);
      ref.invalidate(sessionsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              session.id.isEmpty
                  ? 'Séance planifiée.'
                  : 'Événement mis à jour.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _cancelSession(ClassSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler cette séance ?'),
        content: Text('La séance « ${session.title} » sera marquée annulée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler la séance'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(sessionServiceProvider).cancelSession(session.id);
      ref.invalidate(sessionsProvider);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _deleteEvent(ClassSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer définitivement cet événement ?'),
        content: Text(
          '« ${session.title} » et ses inscriptions extérieures, présences '
          'et playlists associées seront supprimées. Cette action est '
          'irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
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
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(sessionServiceProvider).deleteEvent(session.id);
      ref.invalidate(sessionsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Événement supprimé.')),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _manageGuests(ClassSession session) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _GuestRegistrationDialog(
        session: session,
        service: ref.read(sessionServiceProvider),
      ),
    );
  }

  void _showError(Object error) {
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

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);
    final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    final isAdmin = userId != null &&
        ref.watch(userProfileProvider(userId)).valueOrNull?.isAdmin == true;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSession,
        icon: const Icon(Icons.add),
        label: const Text('Planifier'),
      ),
      body: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _AgendaError(
          error: error,
          onRetry: () => ref.invalidate(sessionsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'Aucune séance planifiée. Ajoutez un cours ou un événement.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final session = items[index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    child: Icon(
                      session.isEvent
                          ? Icons.celebration_outlined
                          : Icons.calendar_month_outlined,
                    ),
                  ),
                  title: Text(session.title),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '${_dateLabel(session.startsAt)} · '
                      '${_timeLabel(session.startsAt)}'
                      '${session.location == null ? '' : ' · ${session.location}'}\n'
                      '${session.isEvent ? 'Événement' : 'Cours'} · '
                      '${_statusLabel(session.status)}'
                      '${session.capacity == null ? '' : ' · Capacité ${session.capacity}'}'
                      '${session.instructors.isEmpty ? '' : '\nÉquipe : ${session.instructors.map((instructor) => '${instructor.displayName} (${instructor.role})').join(', ')}'}',
                    ),
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    children: [
                      if (session.isEvent)
                        IconButton(
                          tooltip: 'Inscriptions extérieures',
                          onPressed: () => _manageGuests(session),
                          icon: const Icon(Icons.confirmation_number_outlined),
                        ),
                      IconButton(
                        tooltip: 'Pointage',
                        onPressed: () => widget.onOpenAttendance?.call(session),
                        icon: const Icon(Icons.how_to_reg_outlined),
                      ),
                      if (session.equipmentChecklist.isNotEmpty)
                        IconButton(
                          tooltip: 'Check-list matériel',
                          onPressed: () => _checkEquipment(session),
                          icon: Badge(
                            isLabelVisible: session.equipmentChecklist.any(
                              (item) => item['checked'] != true,
                            ),
                            child: const Icon(Icons.checklist_rounded),
                          ),
                        ),
                      if (session.status == 'scheduled' ||
                          (session.isEvent && isAdmin))
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') _editSession(session);
                            if (value == 'cancel') _cancelSession(session);
                            if (value == 'complete') _markCompleted(session);
                            if (value == 'delete') _deleteEvent(session);
                          },
                          itemBuilder: (_) => [
                            if (session.isEvent &&
                                session.status == 'scheduled')
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Modifier l’événement'),
                              ),
                            if (session.status == 'scheduled') ...[
                              const PopupMenuItem(
                                value: 'complete',
                                child: Text('Marquer terminé'),
                              ),
                              const PopupMenuItem(
                                value: 'cancel',
                                child: Text('Annuler'),
                              ),
                            ],
                            if (session.isEvent && isAdmin)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Supprimer définitivement (admin)'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _checkEquipment(ClassSession session) async {
    final checklist = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) =>
          _EquipmentChecklistDialog(items: session.equipmentChecklist),
    );
    if (checklist == null) return;
    try {
      await ref
          .read(sessionServiceProvider)
          .updateEquipmentChecklist(session.id, checklist);
      ref.invalidate(sessionsProvider);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _markCompleted(ClassSession session) async {
    try {
      await ref
          .read(sessionServiceProvider)
          .saveSession(
            ClassSession(
              id: session.id,
              title: session.title,
              type: session.type,
              startsAt: session.startsAt,
              endsAt: session.endsAt,
              status: 'completed',
              location: session.location,
              capacity: session.capacity,
              preparationNotes: session.preparationNotes,
              equipmentChecklist: session.equipmentChecklist,
              instructors: session.instructors,
            ),
          );
      ref.invalidate(sessionsProvider);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }
}

class _SessionFormDialog extends StatefulWidget {
  const _SessionFormDialog({required this.instructors, this.session});

  final ClassSession? session;
  final List<AppUserProfile> instructors;

  @override
  State<_SessionFormDialog> createState() => _SessionFormDialogState();
}

class _SessionFormDialogState extends State<_SessionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _capacity;
  late final TextEditingController _notes;
  late DateTime _startsAt;
  late TimeOfDay _startTime;
  late bool _isEvent;
  final Set<String> _equipment = {'Enceinte', 'Micro', 'Caisse'};
  final Map<String, String> _instructorRoles = {};

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    _title = TextEditingController(text: session?.title ?? '');
    _location = TextEditingController(text: session?.location ?? '');
    _capacity = TextEditingController(
      text: session?.capacity?.toString() ?? '',
    );
    _notes = TextEditingController(text: session?.preparationNotes ?? '');
    final startsAt =
        session?.startsAt.toLocal() ??
        DateTime.now().add(const Duration(days: 1));
    _startsAt = DateTime(startsAt.year, startsAt.month, startsAt.day);
    _startTime = TimeOfDay.fromDateTime(startsAt);
    _isEvent = session?.isEvent ?? false;
    for (final instructor in session?.instructors ?? const []) {
      _instructorRoles[instructor.profileId] = instructor.role;
    }
    for (final item in session?.equipmentChecklist ?? const []) {
      final label = item['label'];
      if (label is String && label.isNotEmpty) _equipment.add(label);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _capacity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: _startsAt.isBefore(yesterday) ? _startsAt : yesterday,
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date != null) setState(() => _startsAt = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (time != null) setState(() => _startTime = time);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final previousChecklist = {
      for (final item in widget.session?.equipmentChecklist ?? const [])
        if (item['label'] is String) item['label'] as String: item['checked'],
    };
    final start = DateTime(
      _startsAt.year,
      _startsAt.month,
      _startsAt.day,
      _startTime.hour,
      _startTime.minute,
    );
    final originalDuration = widget.session?.endsAt?.difference(
      widget.session!.startsAt,
    );
    Navigator.pop(
      context,
      ClassSession(
        id: widget.session?.id ?? '',
        title: _title.text,
        type: _isEvent ? 'event' : 'class',
        startsAt: start,
        endsAt: start.add(originalDuration ?? const Duration(hours: 1)),
        status: widget.session?.status ?? 'scheduled',
        location: _location.text,
        capacity: _capacity.text.isEmpty ? null : int.parse(_capacity.text),
        preparationNotes: _notes.text,
        equipmentChecklist: [
          for (final item in _equipment)
            {'label': item, 'checked': previousChecklist[item] == true},
        ],
        instructors: _isEvent
            ? [
                for (final profile in widget.instructors)
                  if (_instructorRoles.containsKey(profile.id))
                    SessionInstructor(
                      profileId: profile.id,
                      displayName: profile.displayName,
                      role: _instructorRoles[profile.id]!.trim(),
                    ),
              ]
            : const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.session == null ? 'Planifier une séance' : 'Modifier l’événement',
    ),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Titre *'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Saisissez un titre.'
                    : null,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Événement / stage'),
                value: _isEvent,
                onChanged: widget.session == null
                    ? (value) => setState(() => _isEvent = value)
                    : null,
              ),
              if (_isEvent) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Instructeurs et rôles',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (widget.instructors.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Aucun instructeur disponible. Renseignez d’abord '
                      'l’équipe pédagogique dans les paramètres.',
                    ),
                  )
                else
                  ...widget.instructors.map((profile) {
                    final selected = _instructorRoles.containsKey(profile.id);
                    return Column(
                      children: [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selected,
                          title: Text(
                            profile.displayName.isEmpty
                                ? 'Animateur·trice'
                                : profile.displayName,
                          ),
                          subtitle: profile.teachingDances.isEmpty
                              ? null
                              : Text(profile.teachingDances.join(', ')),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _instructorRoles[profile.id] =
                                  _instructorRoles[profile.id] ?? 'Animation';
                            } else {
                              _instructorRoles.remove(profile.id);
                            }
                          }),
                        ),
                        if (selected)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TextFormField(
                              key: ValueKey('role-${profile.id}'),
                              initialValue: _instructorRoles[profile.id],
                              decoration: const InputDecoration(
                                labelText: 'Rôle sur cet événement',
                                hintText: 'Ex. Animation, accueil, coordination',
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Indiquez le rôle de cet instructeur.'
                                  : null,
                              onChanged: (value) =>
                                  _instructorRoles[profile.id] = value,
                            ),
                          ),
                      ],
                    );
                  }),
              ],
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_dateLabel(_startsAt)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(_startTime.format(context)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _location,
                decoration: const InputDecoration(labelText: 'Lieu'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _capacity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Capacité'),
                validator: (value) {
                  if (value == null || value.isEmpty) return null;
                  final number = int.tryParse(value);
                  return number == null || number < 0
                      ? 'Saisissez une capacité valide.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes de préparation',
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Matériel à vérifier',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final item in const [
                    'Enceinte',
                    'Micro',
                    'Caisse',
                    'Câbles',
                  ])
                    FilterChip(
                      label: Text(item),
                      selected: _equipment.contains(item),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _equipment.add(item);
                        } else {
                          _equipment.remove(item);
                        }
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Retour'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
    ],
  );
}

class _AgendaError extends StatelessWidget {
  const _AgendaError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Impossible de charger l’agenda'),
          SelectableText(error.toString(), textAlign: TextAlign.center),
          OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    ),
  );
}

class _GuestRegistrationDialog extends StatefulWidget {
  const _GuestRegistrationDialog({
    required this.session,
    required this.service,
  });

  final ClassSession session;
  final SessionService service;

  @override
  State<_GuestRegistrationDialog> createState() =>
      _GuestRegistrationDialogState();
}

class _GuestRegistrationDialogState extends State<_GuestRegistrationDialog> {
  late Future<List<Map<String, dynamic>>> _registrations;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _registrations = widget.service.eventRegistrations(widget.session.id);
  }

  Future<void> _add() async {
    final request = await showDialog<_GuestRequest>(
      context: context,
      builder: (_) => const _GuestFormDialog(),
    );
    if (request == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.service.addEventRegistration(
        sessionId: widget.session.id,
        fullName: request.name,
        amountPaid: request.amount,
        email: request.email,
        phone: request.phone,
        paymentMethod: request.paymentMethod,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await widget.service.deleteEventRegistration(id);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Inscriptions · ${widget.session.title}'),
    content: SizedBox(
      width: 540,
      height: 440,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _registrations,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Chargement impossible'),
                SelectableText(snapshot.error.toString()),
                OutlinedButton(
                  onPressed: () => setState(_reload),
                  child: const Text('Réessayer'),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          final total = rows.fold<double>(
            0,
            (sum, row) => sum + (row['amount_paid'] as num).toDouble(),
          );
          return Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${rows.length} participant(s)'),
                trailing: Text('${total.toStringAsFixed(2)} € encaissés'),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('Aucune inscription.'))
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(row['full_name'] as String),
                            subtitle: Text(
                              '${(row['amount_paid'] as num).toStringAsFixed(2)} €'
                              '${row['email'] == null ? '' : ' · ${row['email']}'}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Supprimer l’inscription',
                              onPressed: _saving
                                  ? null
                                  : () => _delete(row['id'] as String),
                              icon: const Icon(Icons.delete_outline),
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
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
      FilledButton.icon(
        onPressed: _saving ? null : _add,
        icon: const Icon(Icons.person_add_alt),
        label: Text(_saving ? 'Enregistrement…' : 'Inscrire'),
      ),
    ],
  );
}

class _GuestRequest {
  const _GuestRequest({
    required this.name,
    required this.amount,
    this.email,
    this.phone,
    this.paymentMethod,
  });
  final String name;
  final double amount;
  final String? email;
  final String? phone;
  final String? paymentMethod;
}

class _GuestFormDialog extends StatefulWidget {
  const _GuestFormDialog();

  @override
  State<_GuestFormDialog> createState() => _GuestFormDialogState();
}

class _GuestFormDialogState extends State<_GuestFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _amount = TextEditingController(text: '0');
  String? _paymentMethod;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Inscrire un participant extérieur'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom complet *'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Saisissez le nom.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Montant encaissé (€)',
                ),
                validator: (value) {
                  final amount = double.tryParse(
                    (value ?? '').replaceAll(',', '.'),
                  );
                  return amount == null || amount < 0
                      ? 'Montant invalide.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Moyen de paiement',
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Non précisé')),
                  DropdownMenuItem(value: 'cash', child: Text('Espèces')),
                  DropdownMenuItem(value: 'cheque', child: Text('Chèque')),
                  DropdownMenuItem(
                    value: 'bank_transfer',
                    child: Text('Virement'),
                  ),
                  DropdownMenuItem(value: 'card', child: Text('CB')),
                ],
                onChanged: (value) => setState(() => _paymentMethod = value),
              ),
            ],
          ),
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
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _GuestRequest(
              name: _name.text.trim(),
              amount: double.parse(_amount.text.replaceAll(',', '.')),
              email: _email.text,
              phone: _phone.text,
              paymentMethod: _paymentMethod,
            ),
          );
        },
        child: const Text('Inscrire'),
      ),
    ],
  );
}

class _EquipmentChecklistDialog extends StatefulWidget {
  const _EquipmentChecklistDialog({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  State<_EquipmentChecklistDialog> createState() =>
      _EquipmentChecklistDialogState();
}

class _EquipmentChecklistDialogState extends State<_EquipmentChecklistDialog> {
  late final List<Map<String, dynamic>> _items = widget.items
      .map((item) => {...item})
      .toList();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Matériel du cours'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < _items.length; index++)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_items[index]['label'] as String? ?? 'Matériel'),
            value: _items[index]['checked'] == true,
            onChanged: (checked) =>
                setState(() => _items[index]['checked'] = checked ?? false),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _items),
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _timeLabel(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _statusLabel(String status) => switch (status) {
  'completed' => 'Terminée',
  'cancelled' => 'Annulée',
  _ => 'Planifiée',
};
