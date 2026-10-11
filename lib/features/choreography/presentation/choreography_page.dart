import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/spotify_launcher.dart';
import '../domain/spotify_link.dart';
import '../domain/track.dart';

class ChoreographyPage extends ConsumerStatefulWidget {
  const ChoreographyPage({this.activityId, super.key});

  final String? activityId;

  @override
  ConsumerState<ChoreographyPage> createState() => _ChoreographyPageState();
}

class _ChoreographyPageState extends ConsumerState<ChoreographyPage> {
  String _query = '';
  DanceStyle? _style;
  CardioIntensity? _intensity;
  bool _forgottenOnly = false;

  Future<void> _edit([Track? track]) async {
    if (track == null && widget.activityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choisissez une activité avant d’ajouter un morceau.'),
        ),
      );
      return;
    }
    final edited = await showDialog<Track>(
      context: context,
      builder: (_) => _TrackDialog(track: track),
    );
    if (edited == null) return;
    try {
      await ref
          .read(choreographyServiceProvider)
          .saveTrack(edited.copyWith(activityId: widget.activityId));
      ref.invalidate(tracksForActivityProvider(widget.activityId));
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _delete(Track track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce morceau ?'),
        content: Text(
          '« ${track.title} » ne peut pas être supprimé s’il figure dans une playlist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(choreographyServiceProvider)
          .deleteTrack(track.id, localDocumentPath: track.localDocumentPath);
      ref.invalidate(tracksForActivityProvider(widget.activityId));
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _attachDocument(Track track) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );
      if (files.isEmpty) return;
      final file = files.single;
      final bytes = await file.readAsBytes();
      await ref
          .read(choreographyServiceProvider)
          .saveLocalDocument(
            track: track,
            bytes: bytes,
            fileName: file.name,
            activityId: widget.activityId,
          );
      ref.invalidate(tracksForActivityProvider(widget.activityId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document associé au morceau.')),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _openDocument(Track track) async {
    try {
      final localPath = track.localDocumentPath;
      if (localPath != null && localPath.isNotEmpty) {
        final bytes = await ref
            .read(choreographyServiceProvider)
            .readLocalDocument(localPath);
        if (!mounted) return;
        final isPdf = localPath.toLowerCase().endsWith('.pdf');
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * .94,
                height: MediaQuery.sizeOf(context).height * .9,
                child: isPdf
                    ? PdfPreview(
                        build: (_) async => bytes,
                        allowPrinting: false,
                        allowSharing: false,
                      )
                    : InteractiveViewer(
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
              ),
            ),
          ),
        );
        return;
      }
      final path = track.documentUrl;
      if (path == null || path.isEmpty) return;
      final signedUrl = await ref
          .read(choreographyServiceProvider)
          .signedDocumentUrl(path);
      final launched = await launchUrl(
        Uri.parse(signedUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('Aucune application ne peut ouvrir ce document.');
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _openSpotify(Track track) async {
    try {
      await openTrackInSpotify(track);
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
  Widget build(BuildContext context) {
    final tracks = ref.watch(tracksForActivityProvider(widget.activityId));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.library_add),
        label: const Text('Ajouter un morceau'),
      ),
      body: tracks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _RetryState(
          error: error,
          onRetry: () =>
              ref.invalidate(tracksForActivityProvider(widget.activityId)),
        ),
        data: (allTracks) {
          final query = _query.toLowerCase().trim();
          final filtered = allTracks.where((track) {
            final matchesStyle = _style == null || track.style == _style;
            final matchesIntensity =
                _intensity == null || track.intensity == _intensity;
            final matchesSearch =
                query.isEmpty ||
                track.title.toLowerCase().contains(query) ||
                track.artist.toLowerCase().contains(query);
            final matchesForgotten =
                !_forgottenOnly ||
                track.lastPlayedAt == null ||
                track.lastPlayedAt!.isBefore(
                  DateTime.now().subtract(const Duration(days: 180)),
                );
            return matchesStyle &&
                matchesIntensity &&
                matchesSearch &&
                matchesForgotten;
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 300,
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Titre ou artiste',
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    DropdownButton<DanceStyle?>(
                      value: _style,
                      hint: const Text('Tous les styles'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Tous les styles'),
                        ),
                        for (final style in DanceStyle.values)
                          DropdownMenuItem(
                            value: style,
                            child: Text(_styleLabel(style)),
                          ),
                      ],
                      onChanged: (value) => setState(() => _style = value),
                    ),
                    DropdownButton<CardioIntensity?>(
                      value: _intensity,
                      hint: const Text('Toutes intensités'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Toutes intensités'),
                        ),
                        for (final intensity in CardioIntensity.values)
                          DropdownMenuItem(
                            value: intensity,
                            child: Text(_intensityLabel(intensity)),
                          ),
                      ],
                      onChanged: (value) => setState(() => _intensity = value),
                    ),
                    FilterChip(
                      label: const Text('Oubliés · 6 mois'),
                      selected: _forgottenOnly,
                      onSelected: (value) =>
                          setState(() => _forgottenOnly = value),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${filtered.length} morceau(x)'),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucun morceau. Ajoutez votre première chorégraphie.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final track = filtered[index];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Icon(_intensityIcon(track.intensity)),
                              ),
                              title: Text(track.title),
                              subtitle: Text(
                                '${track.artist} · ${_styleLabel(track.style)} · '
                                '${_durationLabel(track.duration)} · '
                                '${_intensityLabel(track.intensity)}',
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') _edit(track);
                                  if (value == 'delete') _delete(track);
                                  if (value == 'document') {
                                    _attachDocument(track);
                                  }
                                  if (value == 'open') _openDocument(track);
                                  if (value == 'spotify') _openSpotify(track);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Modifier'),
                                  ),
                                  PopupMenuItem(
                                    value: 'spotify',
                                    child: Text('Ouvrir dans Spotify'),
                                  ),
                                  PopupMenuItem(
                                    value: 'document',
                                    child: Text(
                                      track.localDocumentPath == null &&
                                              track.documentUrl == null
                                          ? 'Joindre une fiche locale PDF/photo'
                                          : 'Remplacer la fiche PDF/photo',
                                    ),
                                  ),
                                  if (track.localDocumentPath != null ||
                                      track.documentUrl != null)
                                    const PopupMenuItem(
                                      value: 'open',
                                      child: Text('Ouvrir la fiche'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Supprimer'),
                                  ),
                                ],
                              ),
                              onTap: () => _edit(track),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrackDialog extends StatefulWidget {
  const _TrackDialog({this.track});

  final Track? track;

  @override
  State<_TrackDialog> createState() => _TrackDialogState();
}

class _TrackDialogState extends State<_TrackDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _minutes;
  late final TextEditingController _seconds;
  late final TextEditingController _notes;
  late final TextEditingController _spotifyUrl;
  late DanceStyle _style;
  late CardioIntensity _intensity;

  @override
  void initState() {
    super.initState();
    final track = widget.track;
    _title = TextEditingController(text: track?.title ?? '');
    _artist = TextEditingController(text: track?.artist ?? '');
    _minutes = TextEditingController(
      text: ((track?.duration.inSeconds ?? 0) ~/ 60).toString(),
    );
    _seconds = TextEditingController(
      text: ((track?.duration.inSeconds ?? 0) % 60).toString(),
    );
    _notes = TextEditingController(text: track?.teachingNotes ?? '');
    _spotifyUrl = TextEditingController(text: track?.spotifyUrl ?? '');
    _style = track?.style ?? DanceStyle.salsa;
    _intensity = track?.intensity ?? CardioIntensity.moderate;
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _minutes.dispose();
    _seconds.dispose();
    _notes.dispose();
    _spotifyUrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Track(
        id: widget.track?.id ?? '',
        title: _title.text.trim(),
        artist: _artist.text.trim(),
        style: _style,
        duration: Duration(
          minutes: int.parse(_minutes.text),
          seconds: int.parse(_seconds.text),
        ),
        intensity: _intensity,
        documentUrl: widget.track?.documentUrl,
        documentType: widget.track?.documentType,
        teachingNotes: _notes.text,
        lastPlayedAt: widget.track?.lastPlayedAt,
        spotifyUrl: _spotifyUrl.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.track == null ? 'Nouveau morceau' : 'Modifier le morceau',
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
                    ? 'Saisissez le titre.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _artist,
                decoration: const InputDecoration(labelText: 'Artiste'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _spotifyUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Lien Spotify (facultatif)',
                  hintText: 'https://open.spotify.com/track/…',
                  prefixIcon: Icon(Icons.music_note),
                  helperText:
                      'Sans lien, Spotify recherchera le titre et l’artiste.',
                ),
                validator: SpotifyLink.validate,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<DanceStyle>(
                initialValue: _style,
                decoration: const InputDecoration(labelText: 'Style'),
                items: [
                  for (final value in DanceStyle.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_styleLabel(value)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _style = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CardioIntensity>(
                initialValue: _intensity,
                decoration: const InputDecoration(labelText: 'Intensité'),
                items: [
                  for (final value in CardioIntensity.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_intensityLabel(value)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _intensity = value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minutes'),
                      validator: _validateDuration,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _seconds,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Secondes'),
                      validator: (value) {
                        final parsed = int.tryParse(value ?? '');
                        if (parsed == null || parsed < 0 || parsed > 59) {
                          return '0–59';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes pédagogiques',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
    ],
  );

  String? _validateDuration(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed == null || parsed < 0 ? 'Durée invalide.' : null;
  }
}

class _RetryState extends StatelessWidget {
  const _RetryState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Erreur de chargement'),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(error.toString()),
        ),
        OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    ),
  );
}

String _styleLabel(DanceStyle style) => switch (style) {
  DanceStyle.salsa => 'Salsa',
  DanceStyle.merengue => 'Merengue',
  DanceStyle.reggaeton => 'Reggaeton',
  DanceStyle.bachata => 'Bachata',
  DanceStyle.cumbia => 'Cumbia',
  DanceStyle.other => 'Autre',
};

String _intensityLabel(CardioIntensity value) => switch (value) {
  CardioIntensity.warmUp => 'Échauffement',
  CardioIntensity.moderate => 'Modérée',
  CardioIntensity.high => 'Élevée',
  CardioIntensity.coolDown => 'Retour au calme',
};

IconData _intensityIcon(CardioIntensity value) => switch (value) {
  CardioIntensity.warmUp => Icons.wb_sunny_outlined,
  CardioIntensity.moderate => Icons.favorite_border,
  CardioIntensity.high => Icons.local_fire_department_outlined,
  CardioIntensity.coolDown => Icons.spa_outlined,
};

String _durationLabel(Duration duration) =>
    '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
