import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/offline/offline_store.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../attendance/presentation/attendance_page.dart';
import '../../choreography/domain/track.dart';
import '../../members/domain/member.dart';
import '../../repertoire/domain/repertoire_song.dart';
import '../data/session_service.dart';
import '../domain/class_session.dart';

class SessionWorkflowPage extends ConsumerStatefulWidget {
  const SessionWorkflowPage({
    required this.session,
    required this.activityId,
    required this.isSinging,
    super.key,
  });

  final ClassSession session;
  final String? activityId;
  final bool isSinging;

  @override
  ConsumerState<SessionWorkflowPage> createState() =>
      _SessionWorkflowPageState();
}

class _SessionWorkflowPageState extends ConsumerState<SessionWorkflowPage> {
  late final TextEditingController _preparationNotes;
  late final TextEditingController _followUpNotes;
  late List<Map<String, dynamic>> _equipment;
  late Future<void> _planLoad;
  late Future<_ClosureData> _closureLoad;
  List<String>? _plannedIds;
  Set<String>? _playedIds;
  Set<String>? _absentIds;
  bool _savingPreparation = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _preparationNotes = TextEditingController(
      text: widget.session.preparationNotes ?? '',
    );
    _followUpNotes = TextEditingController();
    _equipment = widget.session.equipmentChecklist
        .map((item) => {...item})
        .toList();
    _planLoad = _loadPlan();
    _closureLoad = _loadClosureData();
  }

  @override
  void dispose() {
    _preparationNotes.dispose();
    _followUpNotes.dispose();
    super.dispose();
  }

  SessionService get _service => ref.read(sessionServiceProvider);
  bool get _isCompleted => widget.session.status == 'completed';

  Future<void> _loadPlan() async {
    final ids = widget.isSinging
        ? await _service.repertoireForSession(widget.session.id)
        : await _service.tracksForSession(widget.session.id);
    final played = _isCompleted
        ? widget.isSinging
              ? await _service.playedSongsForSession(widget.session.id)
              : await _service.playedTracksForSession(widget.session.id)
        : ids;
    if (!mounted) return;
    setState(() {
      _plannedIds = ids;
      _playedIds = played.toSet();
    });
  }

  Future<_ClosureData> _loadClosureData() async {
    final activityId = widget.activityId;
    if (activityId == null) {
      throw StateError('La séance n’est rattachée à aucune activité.');
    }
    final members = await ref.read(
      membersForActivityProvider(activityId).future,
    );
    final attendance = await _service.attendanceForSession(widget.session.id);
    final closure = await _service.sessionClosure(widget.session.id);
    if (closure != null && _followUpNotes.text.isEmpty) {
      _followUpNotes.text = closure['follow_up_notes'] as String? ?? '';
    }
    return _ClosureData(
      members: members.where((member) => member.isActive).toList(),
      attendance: attendance,
      closure: closure,
    );
  }

  Future<void> _savePreparation() async {
    final online = await ref.read(offlineStoreProvider).isOnline();
    if (!online) {
      _showMessage('La préparation ne peut être enregistrée hors ligne.');
      return;
    }
    setState(() => _savingPreparation = true);
    try {
      final ids = _plannedIds ?? const [];
      await _service.savePreparation(
        sessionId: widget.session.id,
        notes: _preparationNotes.text,
        equipmentChecklist: _equipment,
        trackIds: widget.isSinging ? const [] : ids,
        songIds: widget.isSinging ? ids : const [],
      );
      ref.invalidate(sessionsProvider(widget.activityId));
      if (mounted) {
        _showMessage('Préparation enregistrée.');
        setState(() => _playedIds = ids.toSet());
      }
    } catch (error) {
      if (mounted) _showError('Enregistrement impossible', error);
    } finally {
      if (mounted) setState(() => _savingPreparation = false);
    }
  }

  Future<void> _chooseMaterial(List<Object> available) async {
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) => _MaterialPicker(
        title: widget.isSinging
            ? 'Choisir le répertoire'
            : 'Choisir la playlist',
        items: available,
        selectedIds: (_plannedIds ?? const []).toSet(),
        isSinging: widget.isSinging,
      ),
    );
    if (selected == null) return;
    setState(() {
      _plannedIds = selected;
      _playedIds = selected.toSet();
    });
  }

  Future<void> _closeSession(_ClosureData data, OfflineStatus? status) async {
    if (_isCompleted) return;
    if (status == null ||
        !status.isOnline ||
        status.pendingCheckIns > 0 ||
        status.lastError != null) {
      _showMessage(
        'Rétablissez la connexion et synchronisez les pointages avant la clôture.',
      );
      return;
    }
    final presentIds = data.attendance
        .where((row) => row['attendance_status'] != 'absent')
        .map((row) => row['member_id'] as String)
        .toSet();
    final absentMembers = data.members
        .where((member) => !presentIds.contains(member.id))
        .toList(growable: false);
    final eligibleAbsenceIds = absentMembers.map((member) => member.id).toSet();
    final absentMemberIds = (_absentIds ?? eligibleAbsenceIds)
        .intersection(eligibleAbsenceIds)
        .toList(growable: false);
    final playedIds = (_playedIds ?? {}).toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clôturer cette séance ?'),
        content: Text(
          '${absentMemberIds.length} absence(s) seront enregistrées et '
          '${playedIds.length} morceau(x) noté(s) comme joué(s). '
          'Cette action terminera la séance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer la séance'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer la clôture'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _closing = true);
    try {
      await _service.closeSessionWithSummary(
        sessionId: widget.session.id,
        absentMemberIds: absentMemberIds,
        playedTrackIds: widget.isSinging ? const [] : playedIds,
        playedSongIds: widget.isSinging ? playedIds : const [],
        followUpNotes: _followUpNotes.text,
      );
      ref.invalidate(sessionsProvider(widget.activityId));
      setState(() {
        _absentIds = absentMemberIds.toSet();
        _playedIds = playedIds.toSet();
        _closureLoad = _loadClosureData();
      });
      if (mounted) _showMessage('Séance clôturée.');
    } catch (error) {
      if (mounted) _showError('Clôture impossible', error);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSongDocument(RepertoireSong song) async {
    final path = song.documentPath;
    if (path == null || path.isEmpty) return;
    try {
      final url = await ref
          .read(repertoireServiceProvider)
          .signedDocumentUrl(path);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('Aucune application ne peut ouvrir ce document.');
      }
    } catch (error) {
      if (mounted) _showError('Ouverture du document impossible', error);
    }
  }

  void _showError(String title, Object error) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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
    final materialState = widget.isSinging
        ? widget.activityId == null
              ? AsyncError<List<Object>>(
                  StateError('Activité manquante.'),
                  StackTrace.empty,
                )
              : ref
                    .watch(repertoireSongsProvider(widget.activityId!))
                    .when(
                      data: (songs) => AsyncData<List<Object>>(songs),
                      error: AsyncError<List<Object>>.new,
                      loading: () => const AsyncLoading<List<Object>>(),
                    )
        : ref
              .watch(tracksForActivityProvider(widget.activityId))
              .when(
                data: (tracks) => AsyncData<List<Object>>(tracks),
                error: AsyncError<List<Object>>.new,
                loading: () => const AsyncLoading<List<Object>>(),
              );
    final status = ref.watch(offlineStatusProvider).valueOrNull;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.session.title),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.event_note_outlined), text: 'Préparer'),
              Tab(icon: Icon(Icons.how_to_reg_outlined), text: 'Présences'),
              Tab(icon: Icon(Icons.task_alt_outlined), text: 'Clôturer'),
            ],
          ),
        ),
        body: Column(
          children: [
            _SessionSummary(
              session: widget.session,
              activityName: ref
                  .watch(activitiesProvider)
                  .valueOrNull
                  ?.where((activity) => activity.id == widget.activityId)
                  .firstOrNull
                  ?.name,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  FutureBuilder<void>(
                    future: _planLoad,
                    builder: (context, planSnapshot) {
                      if (planSnapshot.hasError) {
                        return _WorkflowError(
                          error: planSnapshot.error!,
                          onRetry: () =>
                              setState(() => _planLoad = _loadPlan()),
                        );
                      }
                      if (planSnapshot.connectionState !=
                          ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return materialState.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) => _WorkflowError(
                          error: error,
                          onRetry: () =>
                              setState(() => _planLoad = _loadPlan()),
                        ),
                        data: _preparationTab,
                      );
                    },
                  ),
                  AttendancePage(
                    key: ValueKey('attendance:${widget.session.id}'),
                    activityId: widget.activityId,
                    initialSession: widget.session,
                    onAttendanceChanged: () {
                      setState(() {
                        _absentIds = null;
                        _closureLoad = _loadClosureData();
                      });
                    },
                  ),
                  FutureBuilder<_ClosureData>(
                    future: _closureLoad,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _WorkflowError(
                          error: snapshot.error!,
                          onRetry: () =>
                              setState(() => _closureLoad = _loadClosureData()),
                        );
                      }
                      if (!snapshot.hasData ||
                          !materialState.hasValue ||
                          _plannedIds == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _closureTab(
                        snapshot.data!,
                        materialState.value!,
                        status,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preparationTab(List<Object> available) {
    final planned = _plannedIds ?? const <String>[];
    final byId = {for (final item in available) _itemId(item): item};
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        TextField(
          controller: _preparationNotes,
          minLines: 2,
          maxLines: 5,
          enabled: !_isCompleted,
          decoration: const InputDecoration(
            labelText: 'Consignes et notes de préparation',
            alignLabelWithHint: true,
            prefixIcon: Icon(Icons.sticky_note_2_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Matériel',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (var index = 0; index < _equipment.length; index++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _equipment[index]['label'] as String? ?? 'Matériel',
                    ),
                    value: _equipment[index]['checked'] == true,
                    onChanged: _isCompleted
                        ? null
                        : (value) => setState(
                            () => _equipment[index]['checked'] = value ?? false,
                          ),
                  ),
                if (_equipment.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Aucun matériel n’est prévu.'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.isSinging
                            ? 'Répertoire prévu'
                            : 'Playlist prévue',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (!_isCompleted)
                      OutlinedButton.icon(
                        onPressed: () => _chooseMaterial(available),
                        icon: const Icon(Icons.library_add_outlined),
                        label: const Text('Choisir'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (planned.isEmpty)
                  const Text('Aucun morceau prévu pour cette séance.')
                else
                  for (var index = 0; index < planned.length; index++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(
                        byId[planned[index]] == null
                            ? 'Morceau indisponible'
                            : _itemTitle(byId[planned[index]]!),
                      ),
                      subtitle: byId[planned[index]] == null
                          ? null
                          : Text(_itemSubtitle(byId[planned[index]]!)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (byId[planned[index]] case RepertoireSong song
                              when song.documentPath != null)
                            IconButton(
                              tooltip: 'Ouvrir le document de répétition',
                              onPressed: () => _openSongDocument(song),
                              icon: const Icon(Icons.description_outlined),
                            ),
                          if (_isCompleted)
                            Icon(
                              _playedIds?.contains(planned[index]) == true
                                  ? Icons.check_circle
                                  : Icons.remove_circle_outline,
                            )
                          else ...[
                            IconButton(
                              tooltip: 'Monter',
                              onPressed: index == 0
                                  ? null
                                  : () => _moveItem(index, index - 1),
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: 'Descendre',
                              onPressed: index == planned.length - 1
                                  ? null
                                  : () => _moveItem(index, index + 1),
                              icon: const Icon(Icons.arrow_downward),
                            ),
                            IconButton(
                              tooltip: 'Retirer',
                              onPressed: () =>
                                  setState(() => _plannedIds!.removeAt(index)),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _savingPreparation || _isCompleted
                ? null
                : _savePreparation,
            icon: _savingPreparation
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Enregistrer la préparation'),
          ),
        ),
      ],
    );
  }

  void _moveItem(int from, int to) {
    setState(() {
      final id = _plannedIds!.removeAt(from);
      _plannedIds!.insert(to, id);
    });
  }

  Widget _closureTab(
    _ClosureData data,
    List<Object> available,
    OfflineStatus? status,
  ) {
    final presentIds = data.attendance
        .where((row) => row['attendance_status'] != 'absent')
        .map((row) => row['member_id'] as String)
        .toSet();
    final absentMembers = data.members
        .where((member) => !presentIds.contains(member.id))
        .toList(growable: false);
    final alreadyClosed = data.closure != null || _isCompleted;
    if (_absentIds == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _absentIds == null) {
          setState(
            () => _absentIds = absentMembers.map((member) => member.id).toSet(),
          );
        }
      });
    }
    final visibleStatus = status;
    final needsSync =
        visibleStatus != null &&
        (visibleStatus.pendingCheckIns > 0 || visibleStatus.lastError != null);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        if (alreadyClosed)
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.task_alt),
              title: const Text('Séance clôturée'),
              subtitle: Text(
                data.closure?['closed_at'] is String
                    ? 'Clôturée le ${_dateTime(DateTime.parse(data.closure!['closed_at'] as String))}'
                    : 'Cette séance était déjà terminée.',
              ),
            ),
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Présences à confirmer',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${presentIds.length} présent(s) · '
                    '${absentMembers.length} non pointé(s)',
                  ),
                  const SizedBox(height: 8),
                  if (absentMembers.isEmpty)
                    const Text('Tous les membres actifs sont pointés.')
                  else
                    for (final member in absentMembers)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _absentIds?.contains(member.id) ?? true,
                        title: Text(member.fullName),
                        subtitle: const Text('Confirmer comme absent(e)'),
                        onChanged: (value) => setState(() {
                          final selected = {...?_absentIds};
                          if (value == true) {
                            selected.add(member.id);
                          } else {
                            selected.remove(member.id);
                          }
                          _absentIds = selected;
                        }),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isSinging ? 'Morceaux répétés' : 'Morceaux passés',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if ((_plannedIds ?? const []).isEmpty)
                    const Text('Aucun morceau prévu.')
                  else
                    for (final id in _plannedIds!)
                      if (available.any((item) => _itemId(item) == id))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _playedIds?.contains(id) ?? true,
                          title: Text(
                            _itemTitle(
                              available.firstWhere(
                                (item) => _itemId(item) == id,
                              ),
                            ),
                          ),
                          subtitle: Text(
                            _itemSubtitle(
                              available.firstWhere(
                                (item) => _itemId(item) == id,
                              ),
                            ),
                          ),
                          onChanged: (value) => setState(() {
                            final selected = {...?_playedIds};
                            if (value == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                            _playedIds = selected;
                          }),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _followUpNotes,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'À retenir pour la prochaine séance',
              alignLabelWithHint: true,
            ),
          ),
          if (needsSync)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Synchronisez les pointages en attente avant de clôturer.',
              ),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed:
                  _closing ||
                      visibleStatus == null ||
                      !visibleStatus.isOnline ||
                      needsSync
                  ? null
                  : () => _closeSession(data, visibleStatus),
              icon: _closing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.task_alt),
              label: const Text('Confirmer et clôturer'),
            ),
          ),
        ],
        if (alreadyClosed && data.closure?['follow_up_notes'] is String)
          Card(
            child: ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('À retenir pour la prochaine séance'),
              subtitle: Text(data.closure!['follow_up_notes'] as String),
            ),
          ),
        if (alreadyClosed &&
            data.attendance.any((row) => row['attendance_status'] == 'absent'))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Absences confirmées',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final row in data.attendance.where(
                    (row) => row['attendance_status'] == 'absent',
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_off_outlined),
                      title: Text(
                        '${(row['members'] as Map<String, dynamic>)['first_name']} '
                        '${(row['members'] as Map<String, dynamic>)['last_name']}',
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ClosureData {
  const _ClosureData({
    required this.members,
    required this.attendance,
    required this.closure,
  });

  final List<Member> members;
  final List<Map<String, dynamic>> attendance;
  final Map<String, dynamic>? closure;
}

class _MaterialPicker extends StatefulWidget {
  const _MaterialPicker({
    required this.title,
    required this.items,
    required this.selectedIds,
    required this.isSinging,
  });

  final String title;
  final List<Object> items;
  final Set<String> selectedIds;
  final bool isSinging;

  @override
  State<_MaterialPicker> createState() => _MaterialPickerState();
}

class _MaterialPickerState extends State<_MaterialPicker> {
  late final Set<String> _selected = {...widget.selectedIds};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      height: 440,
      child: widget.items.isEmpty
          ? const Center(child: Text('Aucun morceau disponible.'))
          : ListView(
              children: [
                for (final item in widget.items)
                  CheckboxListTile(
                    value: _selected.contains(_itemId(item)),
                    title: Text(_itemTitle(item)),
                    subtitle: Text(_itemSubtitle(item)),
                    onChanged: (value) => setState(() {
                      final id = _itemId(item);
                      if (value == true) {
                        _selected.add(id);
                      } else {
                        _selected.remove(id);
                      }
                    }),
                  ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          final ordered = [
            ...widget.selectedIds.where(_selected.contains),
            ..._selected.where((id) => !widget.selectedIds.contains(id)),
          ];
          Navigator.pop(context, ordered);
        },
        child: const Text('Valider'),
      ),
    ],
  );
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.session, this.activityName});

  final ClassSession session;
  final String? activityName;

  @override
  Widget build(BuildContext context) {
    final time =
        '${session.startsAt.hour.toString().padLeft(2, '0')}:'
        '${session.startsAt.minute.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(
            avatar: const Icon(Icons.event_outlined, size: 18),
            label: Text('${_date(session.startsAt)} · $time'),
          ),
          if (session.location?.isNotEmpty ?? false)
            Chip(
              avatar: const Icon(Icons.place_outlined, size: 18),
              label: Text(session.location!),
            ),
          for (final instructor in session.instructors)
            Chip(
              avatar: const Icon(Icons.person_outline, size: 18),
              label: Text(instructor.displayName),
            ),
          Chip(
            avatar: Icon(
              session.status == 'completed'
                  ? Icons.task_alt
                  : Icons.schedule_outlined,
              size: 18,
            ),
            label: Text(
              session.status == 'completed' ? 'Terminée' : 'À préparer',
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowError extends StatelessWidget {
  const _WorkflowError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Impossible de charger la séance.'),
            const SizedBox(height: 8),
            SelectableText(error.toString()),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    ),
  );
}

String _itemId(Object item) => switch (item) {
  Track track => track.id,
  RepertoireSong song => song.id,
  _ => throw ArgumentError.value(item, 'item'),
};

String _itemTitle(Object item) => switch (item) {
  Track track => track.title,
  RepertoireSong song => song.title,
  _ => throw ArgumentError.value(item, 'item'),
};

String _itemSubtitle(Object item) => switch (item) {
  Track track =>
    '${track.artist} · ${track.duration.inMinutes}:${(track.duration.inSeconds % 60).toString().padLeft(2, '0')}',
  RepertoireSong song => [
    if (song.composer.isNotEmpty) song.composer,
    if (song.keySignature.isNotEmpty) 'Tonalité ${song.keySignature}',
    if (song.vocalPart.isNotEmpty) song.vocalPart,
    if (song.vocalRange.isNotEmpty) song.vocalRange,
    if (song.accompaniment.isNotEmpty) song.accompaniment,
    if (song.durationSeconds > 0)
      '${song.duration.inMinutes}:${(song.duration.inSeconds % 60).toString().padLeft(2, '0')}',
  ].join(' · '),
  _ => throw ArgumentError.value(item, 'item'),
};

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

String _dateTime(DateTime date) =>
    '${_date(date.toLocal())} à '
    '${date.toLocal().hour.toString().padLeft(2, '0')}:'
    '${date.toLocal().minute.toString().padLeft(2, '0')}';
