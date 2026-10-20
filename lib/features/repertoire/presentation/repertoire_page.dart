import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/repertoire_song.dart';

class RepertoirePage extends ConsumerStatefulWidget {
  const RepertoirePage({required this.activityId, super.key});

  final String activityId;

  @override
  ConsumerState<RepertoirePage> createState() => _RepertoirePageState();
}

class _RepertoirePageState extends ConsumerState<RepertoirePage> {
  String _query = '';
  bool _saving = false;

  Future<void> _edit([RepertoireSong? song]) async {
    final edited = await showDialog<RepertoireSong>(
      context: context,
      builder: (_) => _SongDialog(song: song, activityId: widget.activityId),
    );
    if (edited == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(repertoireServiceProvider).saveSong(edited);
      ref.invalidate(repertoireSongsProvider(widget.activityId));
    } catch (error) {
      if (mounted) _showError('Enregistrement impossible', error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _attachDocument(RepertoireSong song) async {
    final authorized = await showDialog<bool>(
      context: context,
      builder: (_) => const _DocumentRightsDialog(),
    );
    if (authorized != true || !mounted) return;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );
      if (result.isEmpty) return;
      final saved = await ref
          .read(repertoireServiceProvider)
          .uploadDocument(song: song, file: result.single);
      ref.invalidate(repertoireSongsProvider(widget.activityId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Document ajouté à « ${saved.title} ».')),
        );
      }
    } catch (error) {
      if (mounted) _showError('Ajout du document impossible', error);
    }
  }

  Future<void> _openDocument(RepertoireSong song) async {
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
      if (mounted) _showError('Ouverture impossible', error);
    }
  }

  Future<void> _delete(RepertoireSong song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce morceau ?'),
        content: Text(
          '« ${song.title} » sera retiré du répertoire. '
          'Il ne pourra plus être utilisé dans les prochaines répétitions.',
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
      await ref.read(repertoireServiceProvider).deleteSong(song);
      ref.invalidate(repertoireSongsProvider(widget.activityId));
    } catch (error) {
      if (mounted) _showError('Suppression impossible', error);
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
    final songs = ref.watch(repertoireSongsProvider(widget.activityId));
    final online = ref.watch(offlineStatusProvider).valueOrNull?.isOnline ?? false;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving || !online ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un morceau'),
      ),
      body: songs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          error: error,
          onRetry: () => ref.invalidate(repertoireSongsProvider(widget.activityId)),
        ),
        data: (allSongs) {
          final query = _query.trim().toLowerCase();
          final filtered = allSongs.where((song) {
            return query.isEmpty ||
                '${song.title} ${song.composer} ${song.vocalPart} ${song.keySignature}'
                    .toLowerCase()
                    .contains(query);
          }).toList(growable: false);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Titre, compositeur, tonalité ou pupitre',
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Chip(label: Text('${filtered.length} morceau(x)')),
                  ],
                ),
              ),
              if (!online)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Hors ligne : répertoire en lecture seule, documents indisponibles.',
                    ),
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          allSongs.isEmpty
                              ? 'Le répertoire de chant est vide.'
                              : 'Aucun morceau ne correspond à la recherche.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final song = filtered[index];
                          final details = <String>[
                            if (song.composer.isNotEmpty) song.composer,
                            if (song.keySignature.isNotEmpty)
                              'Tonalité ${song.keySignature}',
                            if (song.vocalPart.isNotEmpty) song.vocalPart,
                            if (song.vocalRange.isNotEmpty) song.vocalRange,
                            if (song.accompaniment.isNotEmpty)
                              'Accompagnement : ${song.accompaniment}',
                            if (song.durationSeconds > 0)
                              _duration(song.duration),
                            if (song.rehearsalNotes?.isNotEmpty ?? false)
                              song.rehearsalNotes!,
                          ];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Icon(
                                  song.documentPath == null
                                      ? Icons.music_note
                                      : Icons.description_outlined,
                                ),
                              ),
                              title: Text(song.title),
                              subtitle: Text(
                                details.isEmpty
                                    ? 'Partie vocale à compléter'
                                    : details.join(' · '),
                              ),
                              trailing: PopupMenuButton<String>(
                                enabled: online && !_saving,
                                onSelected: (value) {
                                  if (value == 'edit') _edit(song);
                                  if (value == 'attach') {
                                    _attachDocument(song);
                                  }
                                  if (value == 'open') _openDocument(song);
                                  if (value == 'delete') _delete(song);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Modifier'),
                                  ),
                                  PopupMenuItem(
                                    value: 'attach',
                                    child: Text(
                                      song.documentPath == null
                                          ? 'Joindre un document autorisé'
                                          : 'Remplacer le document',
                                    ),
                                  ),
                                  if (song.documentPath != null)
                                    const PopupMenuItem(
                                      value: 'open',
                                      child: Text('Ouvrir le document'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Supprimer'),
                                  ),
                                ],
                              ),
                              onTap: online ? () => _edit(song) : null,
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

class _SongDialog extends StatefulWidget {
  const _SongDialog({required this.activityId, this.song});

  final String activityId;
  final RepertoireSong? song;

  @override
  State<_SongDialog> createState() => _SongDialogState();
}

class _SongDialogState extends State<_SongDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _composer;
  late final TextEditingController _key;
  late final TextEditingController _range;
  late final TextEditingController _part;
  late final TextEditingController _accompaniment;
  late final TextEditingController _minutes;
  late final TextEditingController _seconds;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final song = widget.song;
    _title = TextEditingController(text: song?.title ?? '');
    _composer = TextEditingController(text: song?.composer ?? '');
    _key = TextEditingController(text: song?.keySignature ?? '');
    _range = TextEditingController(text: song?.vocalRange ?? '');
    _part = TextEditingController(text: song?.vocalPart ?? '');
    _accompaniment = TextEditingController(text: song?.accompaniment ?? '');
    _minutes = TextEditingController(
      text: ((song?.durationSeconds ?? 0) ~/ 60).toString(),
    );
    _seconds = TextEditingController(
      text: ((song?.durationSeconds ?? 0) % 60).toString(),
    );
    _notes = TextEditingController(text: song?.rehearsalNotes ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _composer.dispose();
    _key.dispose();
    _range.dispose();
    _part.dispose();
    _accompaniment.dispose();
    _minutes.dispose();
    _seconds.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final song = widget.song;
    Navigator.pop(
      context,
      RepertoireSong(
        id: song?.id ?? '',
        activityId: widget.activityId,
        title: _title.text.trim(),
        composer: _composer.text.trim(),
        keySignature: _key.text.trim(),
        vocalRange: _range.text.trim(),
        vocalPart: _part.text.trim(),
        accompaniment: _accompaniment.text.trim(),
        durationSeconds:
            (int.parse(_minutes.text) * 60) + int.parse(_seconds.text),
        rehearsalNotes: _notes.text,
        documentPath: song?.documentPath,
        lastPlayedAt: song?.lastPlayedAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.song == null ? 'Nouveau morceau' : 'Morceau de chant'),
    content: SizedBox(
      width: 520,
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
              TextFormField(
                controller: _composer,
                decoration: const InputDecoration(labelText: 'Auteur / compositeur'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _key,
                      decoration: const InputDecoration(labelText: 'Tonalité'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _part,
                      decoration: const InputDecoration(
                        labelText: 'Partie vocale',
                        hintText: 'Soprano, alto…',
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _range,
                      decoration: const InputDecoration(
                        labelText: 'Tessiture / niveau',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _accompaniment,
                      decoration: const InputDecoration(
                        labelText: 'Accompagnement',
                        hintText: 'Piano, bande-son…',
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minutes'),
                      validator: _nonNegativeInteger,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _seconds,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Secondes'),
                      validator: (value) {
                        final seconds = int.tryParse(value ?? '');
                        return seconds == null || seconds < 0 || seconds > 59
                            ? 'Saisissez une valeur de 0 à 59.'
                            : null;
                      },
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes de répétition',
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
}

class _DocumentRightsDialog extends StatefulWidget {
  const _DocumentRightsDialog();

  @override
  State<_DocumentRightsDialog> createState() => _DocumentRightsDialogState();
}

class _DocumentRightsDialogState extends State<_DocumentRightsDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Document de répétition'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Ne joignez que des paroles, partitions ou documents que '
          'l’association est autorisée à stocker et à partager.',
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _confirmed,
          title: const Text('Je confirme que nous avons ces droits.'),
          onChanged: (value) =>
              setState(() => _confirmed = value ?? false),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
        child: const Text('Continuer'),
      ),
    ],
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Impossible de charger le répertoire.'),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(error.toString()),
        ),
        OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    ),
  );
}

String? _nonNegativeInteger(String? value) {
  final parsed = int.tryParse(value ?? '');
  return parsed == null || parsed < 0 ? 'Durée invalide.' : null;
}

String _duration(Duration duration) =>
    '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
