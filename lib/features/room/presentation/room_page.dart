import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../features/agenda/domain/class_session.dart';
import '../../../features/choreography/data/spotify_launcher.dart';
import '../../../features/choreography/domain/track.dart';
import '../application/room_mode_service.dart';
import '../domain/session_plan.dart';

class RoomPage extends ConsumerStatefulWidget {
  const RoomPage({this.activityId, super.key});

  final String? activityId;

  @override
  ConsumerState<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends ConsumerState<RoomPage> {
  String? _sessionId;
  Future<List<String>>? _playlistFuture;
  List<String> _trackIds = [];
  bool _saving = false;

  void _selectSession(String? id) {
    setState(() {
      _sessionId = id;
      _trackIds = [];
      _playlistFuture = id == null
          ? null
          : ref.read(sessionServiceProvider).tracksForSession(id);
    });
  }

  Future<void> _savePlaylist() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(sessionServiceProvider).savePlaylist(sessionId, _trackIds);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Playlist enregistrée.')));
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addTracks(List<Track> tracks) async {
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) => _AddTracksDialog(
        tracks: tracks,
        initiallySelected: _trackIds.toSet(),
      ),
    );
    if (selected != null) setState(() => _trackIds = selected);
  }

  Future<void> _startRoomMode(
    ClassSession session,
    List<Track> allTracks,
  ) async {
    final selectedTracks = _trackIds
        .map((id) => allTracks.where((track) => track.id == id).firstOrNull)
        .whereType<Track>()
        .toList();
    await showDialog<void>(
      context: context,
      builder: (_) => _RoomModeDialog(
        plan: SessionPlan(
          id: session.id,
          title: session.title,
          startsAt: session.startsAt,
          tracks: selectedTracks,
          preparationNotes: session.preparationNotes,
        ),
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
    final sessions = ref.watch(sessionsProvider(widget.activityId));
    final tracks = ref.watch(tracksForActivityProvider(widget.activityId));
    return sessions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        error: error,
        onRetry: () => ref.invalidate(sessionsProvider(widget.activityId)),
      ),
      data: (allSessions) => tracks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          error: error,
          onRetry: () => ref.invalidate(tracksProvider),
        ),
        data: (allTracks) => _buildRoom(allSessions, allTracks),
      ),
    );
  }

  Widget _buildRoom(List<ClassSession> sessions, List<Track> allTracks) {
    final sessionsForPlaylist = sessions
        .where((session) => session.status != 'cancelled')
        .toList();
    final selectedSession = sessionsForPlaylist
        .where((session) => session.id == _sessionId)
        .firstOrNull;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth > 540
                      ? constraints.maxWidth - 190
                      : constraints.maxWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: _sessionId,
                    decoration: const InputDecoration(labelText: 'Séance'),
                    items: [
                      for (final session in sessionsForPlaylist)
                        DropdownMenuItem(
                          value: session.id,
                          child: Text(
                            '${_dateLabel(session.startsAt)} · ${session.title}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _selectSession,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _sessionId == null || allTracks.isEmpty
                      ? null
                      : () => _addTracks(allTracks),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter des morceaux'),
                ),
              ],
            ),
          ),
        ),
        if (selectedSession != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(selectedSession.title),
                subtitle: Text(
                  '${_dateLabel(selectedSession.startsAt)} · '
                  '${selectedSession.preparationNotes ?? 'Aucune note'}',
                ),
                trailing: TextButton.icon(
                  onPressed: _trackIds.isEmpty
                      ? null
                      : () => _startRoomMode(selectedSession, allTracks),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Régie'),
                ),
              ),
            ),
          ),
        Expanded(
          child: _sessionId == null
              ? const Center(
                  child: Text(
                    'Choisissez une séance pour préparer sa playlist.',
                  ),
                )
              : FutureBuilder<List<String>>(
                  future: _playlistFuture,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _ErrorState(
                        error: snapshot.error!,
                        onRetry: () => _selectSession(_sessionId),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (_trackIds.isEmpty && snapshot.data!.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _trackIds.isEmpty) {
                          setState(() => _trackIds = snapshot.data!);
                        }
                      });
                    }
                    final playlist = _trackIds
                        .map(
                          (id) => allTracks
                              .where((track) => track.id == id)
                              .firstOrNull,
                        )
                        .whereType<Track>()
                        .toList();
                    if (playlist.isEmpty) {
                      return const Center(
                        child: Text(
                          'La playlist est vide. Ajoutez des morceaux.',
                        ),
                      );
                    }
                    final totalSeconds = playlist.fold<int>(
                      0,
                      (total, track) => total + track.duration.inSeconds,
                    );
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${playlist.length} morceaux · '
                                  '${totalSeconds ~/ 60} min ${(totalSeconds % 60).toString().padLeft(2, '0')} s',
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: _saving ? null : _savePlaylist,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: const Text('Enregistrer'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                            itemCount: playlist.length,
                            onReorderItem: (oldIndex, newIndex) {
                              setState(() {
                                final id = _trackIds.removeAt(oldIndex);
                                _trackIds.insert(newIndex, id);
                              });
                            },
                            itemBuilder: (context, index) {
                              final track = playlist[index];
                              return Card(
                                key: ValueKey(track.id),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text('${index + 1}'),
                                  ),
                                  title: Text(track.title),
                                  subtitle: Text(
                                    '${track.artist} · ${_duration(track.duration)} · ${_intensity(track.intensity)}',
                                  ),
                                  trailing: Wrap(
                                    children: [
                                      IconButton(
                                        tooltip: 'Ouvrir dans Spotify',
                                        onPressed: () =>
                                            _openInSpotify(context, track),
                                        icon: const Icon(Icons.music_note),
                                      ),
                                      IconButton(
                                        tooltip: 'Retirer',
                                        onPressed: () => setState(
                                          () => _trackIds.remove(track.id),
                                        ),
                                        icon: const Icon(Icons.close),
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
    );
  }
}

class _AddTracksDialog extends StatefulWidget {
  const _AddTracksDialog({
    required this.tracks,
    required this.initiallySelected,
  });
  final List<Track> tracks;
  final Set<String> initiallySelected;

  @override
  State<_AddTracksDialog> createState() => _AddTracksDialogState();
}

class _AddTracksDialogState extends State<_AddTracksDialog> {
  late final List<String> _ordered = [
    ...widget.initiallySelected.where(
      (id) => widget.tracks.any((track) => track.id == id),
    ),
  ];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choisir les morceaux'),
    content: SizedBox(
      width: 520,
      height: 440,
      child: ListView(
        children: [
          for (final track in widget.tracks)
            CheckboxListTile(
              value: _ordered.contains(track.id),
              title: Text(track.title),
              subtitle: Text(track.artist),
              onChanged: (selected) => setState(() {
                if (selected == true) {
                  _ordered.add(track.id);
                } else {
                  _ordered.remove(track.id);
                }
              }),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Retour'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _ordered),
        child: const Text('Appliquer'),
      ),
    ],
  );
}

class _RoomModeDialog extends StatefulWidget {
  const _RoomModeDialog({required this.plan});
  final SessionPlan plan;

  @override
  State<_RoomModeDialog> createState() => _RoomModeDialogState();
}

class _RoomModeDialogState extends State<_RoomModeDialog> {
  late final RoomModeService _service = RoomModeService(widget.plan);

  Future<void> _openCurrentInSpotify(Track track) async {
    try {
      await openTrackInSpotify(track);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Spotify impossible à ouvrir : $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _service.currentTrack;
    final next = _service.nextTrack;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.plan.title),
          leading: IconButton(
            tooltip: 'Fermer la régie',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        body: current == null
            ? const Center(child: Text('Aucun morceau dans cette playlist.'))
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'MORCEAU ${_service.currentNumber} / ${widget.plan.tracks.length}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 24),
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 86,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          current.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        Text(
                          current.artist,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Chip(
                          label: Text(
                            '${_duration(current.duration)} · ${_intensity(current.intensity)}',
                          ),
                        ),
                        const SizedBox(height: 32),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.skip_next_rounded),
                            title: const Text('Suivant'),
                            subtitle: Text(next?.title ?? 'Fin de la playlist'),
                          ),
                        ),
                        const SizedBox(height: 28),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(220, 56),
                          ),
                          onPressed: () => _openCurrentInSpotify(current),
                          icon: const Icon(Icons.music_note),
                          label: Text(
                            current.spotifyUrl == null
                                ? 'Chercher dans Spotify'
                                : 'Ouvrir dans Spotify',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(220, 64),
                          ),
                          onPressed: () => setState(_service.advance),
                          icon: const Icon(Icons.skip_next),
                          label: const Text('Morceau suivant'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

Future<void> _openInSpotify(BuildContext context, Track track) async {
  try {
    await openTrackInSpotify(track);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Spotify impossible à ouvrir : $error')),
      );
    }
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Erreur de chargement'),
          SelectableText(error.toString()),
          OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    ),
  );
}

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _duration(Duration duration) =>
    '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

String _intensity(CardioIntensity value) => switch (value) {
  CardioIntensity.warmUp => 'Échauffement',
  CardioIntensity.moderate => 'Modérée',
  CardioIntensity.high => 'Élevée',
  CardioIntensity.coolDown => 'Retour au calme',
};
