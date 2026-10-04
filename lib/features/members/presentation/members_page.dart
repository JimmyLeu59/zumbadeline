import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/member.dart';

class MembersPage extends ConsumerStatefulWidget {
  const MembersPage({super.key});

  @override
  ConsumerState<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends ConsumerState<MembersPage> {
  String _search = '';
  bool _activeOnly = true;

  Future<void> _editMember([Member? member]) async {
    final edited = await showDialog<Member>(
      context: context,
      builder: (_) => _MemberFormDialog(member: member),
    );
    if (edited == null || !mounted) return;
    try {
      await ref.read(memberServiceProvider).saveMember(edited);
      ref.invalidate(membersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${edited.fullName} enregistré(e).')),
        );
      }
    } catch (error) {
      if (mounted) _showError('Enregistrement impossible', error);
    }
  }

  Future<void> _archive(Member member) async {
    await _setActive(member, false);
  }

  Future<void> _reactivate(Member member) async {
    await _setActive(member, true);
  }

  Future<void> _adjustPasses(Member member) async {
    try {
      final cards = await ref
          .read(memberServiceProvider)
          .cardsForMember(member.id);
      if (!mounted) return;
      if (cards.isEmpty) {
        _showError(
          'Aucune carte',
          StateError('${member.fullName} ne possède aucune carte de cours.'),
        );
        return;
      }
      final request = await showDialog<_PassAdjustment>(
        context: context,
        builder: (_) => _PassAdjustmentDialog(
          memberName: member.fullName,
          cards: cards,
        ),
      );
      if (request == null || !mounted) return;
      await ref.read(memberServiceProvider).adjustCardPasses(
        cardId: request.cardId,
        remainingPasses: request.remainingPasses,
        reason: request.reason,
      );
      ref.invalidate(membersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solde de la carte mis à jour.')),
        );
      }
    } catch (error) {
      if (mounted) _showError('Modification des passages impossible', error);
    }
  }

  Future<void> _changePhoto(Member member) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (!kIsWeb &&
                defaultTargetPlatform != TargetPlatform.windows &&
                defaultTargetPlatform != TargetPlatform.macOS &&
                defaultTargetPlatform != TargetPlatform.linux)
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (image == null) return;
      final extension = image.name.split('.').last.toLowerCase();
      final service = ref.read(memberServiceProvider);
      final path = await service.uploadMemberPhoto(
        memberId: member.id,
        bytes: await image.readAsBytes(),
        extension: extension,
      );
      try {
        await service.saveMember(_withPhoto(member, path));
      } catch (_) {
        await service.deleteMemberPhoto(path);
        rethrow;
      }
      ref.invalidate(membersProvider);
      ref.invalidate(memberPhotoUrlProvider(member.photoUrl));
      ref.invalidate(memberPhotoUrlProvider(path));
      await service.deleteMemberPhoto(member.photoUrl);
    } catch (error) {
      if (mounted) _showError('Photo non enregistrée', error);
    }
  }

  Future<void> _setActive(Member member, bool isActive) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isActive ? 'Réactiver cet adhérent ?' : 'Archiver cet adhérent ?',
        ),
        content: Text(
          isActive
              ? '${member.fullName} apparaîtra de nouveau parmi les adhérents actifs.'
              : '${member.fullName} sera masqué(e) des adhérents actifs. '
                    'Son historique sera conservé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isActive ? 'Réactiver' : 'Archiver'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(memberServiceProvider)
          .setMemberActive(member.id, isActive);
      ref.invalidate(membersProvider);
    } catch (error) {
      if (mounted) _showError('Archivage impossible', error);
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

  Future<void> _exportTrombinoscope(List<Member> members) async {
    try {
      await ref.read(reportServiceProvider).shareMembersPdf(members);
    } catch (error) {
      if (mounted) _showError('Export PDF impossible', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    final isAdmin = userId != null &&
        ref.watch(userProfileProvider(userId)).valueOrNull?.isAdmin == true;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editMember(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Ajouter'),
      ),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LoadError(
          error: error,
          onRetry: () => ref.invalidate(membersProvider),
        ),
        data: (allMembers) {
          final query = _search.trim().toLowerCase();
          final visible = allMembers.where((member) {
            if (_activeOnly && !member.isActive) return false;
            return query.isEmpty ||
                member.fullName.toLowerCase().contains(query) ||
                (member.email?.toLowerCase().contains(query) ?? false) ||
                (member.phone?.contains(query) ?? false);
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth > 520
                            ? constraints.maxWidth - 170
                            : constraints.maxWidth,
                        child: TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Rechercher par nom, e-mail ou téléphone',
                          ),
                          onChanged: (value) => setState(() => _search = value),
                        ),
                      ),
                      FilterChip(
                        label: const Text('Actifs uniquement'),
                        selected: _activeOnly,
                        onSelected: (value) =>
                            setState(() => _activeOnly = value),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: visible.isEmpty
                            ? null
                            : () => _exportTrombinoscope(visible),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Exporter en PDF'),
                      ),
                    ],
                  ),
                ),
              ),
              const _InstructorStrip(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${visible.length} adhérent(s)'),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: visible.isEmpty
                    ? const _EmptyState(
                        icon: Icons.groups_outlined,
                        title: 'Aucun adhérent trouvé',
                        message: 'Ajoutez une fiche ou modifiez les critères de recherche.',
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth > 1000
                              ? 3
                              : constraints.maxWidth > 650
                              ? 2
                              : 1;
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 92),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  mainAxisExtent: 142,
                                ),
                            itemCount: visible.length,
                            itemBuilder: (context, index) => _MemberCard(
                              member: visible[index],
                              onEdit: () => _editMember(visible[index]),
                              onArchive: visible[index].isActive
                                  ? () => _archive(visible[index])
                                  : null,
                              onReactivate: visible[index].isActive
                                  ? null
                                  : () => _reactivate(visible[index]),
                              onChangePhoto: () => _changePhoto(visible[index]),
                              onAdjustPasses: isAdmin
                                  ? () => _adjustPasses(visible[index])
                                  : null,
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

class _InstructorStrip extends ConsumerWidget {
  const _InstructorStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(staffProfilesProvider);
    return profiles.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Animateurs indisponibles : $error')),
            IconButton(
              tooltip: 'Recharger les animateurs',
              onPressed: () => ref.invalidate(staffProfilesProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      data: (allProfiles) {
        final instructors = allProfiles
            .where((profile) => profile.teachingDances.isNotEmpty)
            .toList(growable: false);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Animateurs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              if (instructors.isEmpty)
                const Text('Aucune discipline animée renseignée.')
              else
                SizedBox(
                  height: 88,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: instructors.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final instructor = instructors[index];
                      final photoUrl = ref
                          .watch(staffPhotoUrlProvider(instructor.photoUrl))
                          .valueOrNull;
                      return SizedBox(
                        width: 240,
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: CircleAvatar(
                              foregroundImage: photoUrl == null
                                  ? null
                                  : NetworkImage(photoUrl),
                              child: Text(
                                instructor.displayName.trim().isEmpty
                                    ? 'A'
                                    : instructor.displayName
                                          .trim()[0]
                                          .toUpperCase(),
                              ),
                            ),
                            title: Text(
                              instructor.displayName.isEmpty
                                  ? 'Animateur·trice'
                                  : instructor.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Animateur·trice · '
                              '${instructor.teachingDances.join(', ')}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MemberCard extends ConsumerWidget {
  const _MemberCard({
    required this.member,
    required this.onEdit,
    required this.onArchive,
    required this.onReactivate,
    required this.onChangePhoto,
    required this.onAdjustPasses,
  });

  final Member member;
  final VoidCallback onEdit;
  final VoidCallback? onArchive;
  final VoidCallback? onReactivate;
  final VoidCallback onChangePhoto;
  final VoidCallback? onAdjustPasses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final current = member.membershipIsCurrent;
    final photoUrl = ref
        .watch(memberPhotoUrlProvider(member.photoUrl))
        .valueOrNull;
    return Card(
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Ajouter ou modifier la photo de ${member.fullName}',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onChangePhoto,
                  child: Tooltip(
                    message: 'Ajouter ou modifier la photo',
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: colors.primary.withValues(
                            alpha: .12,
                          ),
                          foregroundImage: photoUrl == null
                              ? null
                              : NetworkImage(photoUrl),
                          child: Text(
                            member.firstName.trim().isEmpty
                                ? '?'
                                : member.firstName.trim()[0].toUpperCase(),
                            style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: colors.secondary,
                            child: const Icon(Icons.camera_alt, size: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (member.phone?.isNotEmpty ?? false)
                      Text(member.phone!, maxLines: 1),
                    if (member.email?.isNotEmpty ?? false)
                      Text(
                        member.email!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        _StatusChip(
                          label: member.isActive ? 'Actif' : 'Archivé',
                          color: member.isActive
                              ? colors.tertiary
                              : colors.outline,
                        ),
                        _StatusChip(
                          label: member.membershipValidUntil == null
                              ? 'Cotisation à jour ?'
                              : current
                              ? 'Cotisation OK'
                              : 'Cotisation échue',
                          color: current ? colors.tertiary : colors.error,
                        ),
                        _StatusChip(
                          label: '${member.remainingPasses} passage(s)',
                          color: member.remainingPasses <= 1
                              ? colors.secondary
                              : colors.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                  const PopupMenuItem(
                    value: 'photo',
                    child: Text('Modifier la photo'),
                  ),
                  if (onAdjustPasses != null)
                    const PopupMenuItem(
                      value: 'passes',
                      child: Text('Ajuster les passages (admin)'),
                    ),
                  if (onArchive != null)
                    const PopupMenuItem(
                      value: 'archive',
                      child: Text('Archiver'),
                    ),
                  if (onReactivate != null)
                    const PopupMenuItem(
                      value: 'reactivate',
                      child: Text('Réactiver'),
                    ),
                ],
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'photo') onChangePhoto();
                  if (value == 'passes') onAdjustPasses?.call();
                  if (value == 'archive') onArchive?.call();
                  if (value == 'reactivate') onReactivate?.call();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Chip(
    visualDensity: VisualDensity.compact,
    label: Text(label, style: const TextStyle(fontSize: 11)),
    padding: EdgeInsets.zero,
    backgroundColor: color.withValues(alpha: .12),
    side: BorderSide.none,
  );
}

class _PassAdjustment {
  const _PassAdjustment({
    required this.cardId,
    required this.remainingPasses,
    required this.reason,
  });

  final String cardId;
  final int remainingPasses;
  final String reason;
}

class _PassAdjustmentDialog extends StatefulWidget {
  const _PassAdjustmentDialog({
    required this.memberName,
    required this.cards,
  });

  final String memberName;
  final List<Map<String, dynamic>> cards;

  @override
  State<_PassAdjustmentDialog> createState() => _PassAdjustmentDialogState();
}

class _PassAdjustmentDialogState extends State<_PassAdjustmentDialog> {
  late Map<String, dynamic> _card = widget.cards.first;
  late final TextEditingController _remaining = TextEditingController(
    text: '${_card['remaining_passes']}',
  );
  final _reason = TextEditingController();
  String? _remainingError;
  String? _reasonError;

  @override
  void dispose() {
    _remaining.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Ajuster les passages · ${widget.memberName}'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<Map<String, dynamic>>(
            initialValue: _card,
            decoration: const InputDecoration(labelText: 'Carte de cours'),
            items: [
              for (final card in widget.cards)
                DropdownMenuItem(
                  value: card,
                  child: Text(
                    'Carte #${card['purchase_number']} · '
                    '${card['remaining_passes']}/${card['total_passes']} restants',
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _card = value;
                _remaining.text = '${value['remaining_passes']}';
                _remainingError = null;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remaining,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Nouveau solde de passages',
              errorText: _remainingError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Motif obligatoire',
              hintText: 'Ex. correction après erreur de pointage',
              errorText: _reasonError,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Toute hausse au-delà du solde maximal actuel augmente aussi '
            'la capacité de cette carte. La modification est historisée.',
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
          final remaining = int.tryParse(_remaining.text.trim());
          final reason = _reason.text.trim();
          setState(() {
            _remainingError = remaining == null || remaining < 0 || remaining > 1000
                ? 'Saisir un nombre entre 0 et 1000.'
                : null;
            _reasonError = reason.isEmpty
                ? 'Le motif est obligatoire.'
                : reason.length > 500
                ? 'Le motif doit faire 500 caractères maximum.'
                : null;
          });
          if (_remainingError != null || _reasonError != null) return;
          Navigator.pop(
            context,
            _PassAdjustment(
              cardId: _card['id'] as String,
              remainingPasses: remaining!,
              reason: reason,
            ),
          );
        },
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

class _MemberFormDialog extends StatefulWidget {
  const _MemberFormDialog({this.member});

  final Member? member;

  @override
  State<_MemberFormDialog> createState() => _MemberFormDialogState();
}

class _MemberFormDialogState extends State<_MemberFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;
  late final TextEditingController _certificateUrl;
  late final TextEditingController _notes;
  late DateTime? _membershipDate;
  late DateTime? _birthDate;
  late DateTime? _certificateDate;

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    _firstName = TextEditingController(text: member?.firstName ?? '');
    _lastName = TextEditingController(text: member?.lastName ?? '');
    _phone = TextEditingController(text: member?.phone ?? '');
    _email = TextEditingController(text: member?.email ?? '');
    _emergencyName = TextEditingController(
      text: member?.emergencyContactName ?? '',
    );
    _emergencyPhone = TextEditingController(
      text: member?.emergencyContactPhone ?? '',
    );
    _certificateUrl = TextEditingController(
      text: member?.medicalCertificateUrl ?? '',
    );
    _notes = TextEditingController(text: member?.notes ?? '');
    _membershipDate = member?.membershipValidUntil;
    _birthDate = member?.birthDate;
    _certificateDate = member?.medicalCertificateValidUntil;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    _certificateUrl.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required bool membership,
    bool certificate = false,
  }) async {
    final now = DateTime.now();
    final initial = certificate
        ? _certificateDate
        : membership
        ? _membershipDate
        : _birthDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? (membership ? now : DateTime(now.year - 30)),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 20),
    );
    if (date != null) {
      setState(() {
        if (membership) {
          _membershipDate = date;
        } else if (certificate) {
          _certificateDate = date;
        } else {
          _birthDate = date;
        }
      });
    }
  }

  String _formatDate(DateTime? date) => date == null
      ? 'Non renseignée'
      : '${date.day}/${date.month}/${date.year}';

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.member;
    Navigator.pop(
      context,
      Member(
        id: old?.id ?? '',
        firstName: _firstName.text,
        lastName: _lastName.text,
        phone: _phone.text,
        email: _email.text,
        birthDate: _birthDate,
        membershipValidUntil: _membershipDate,
        emergencyContactName: _emergencyName.text,
        emergencyContactPhone: _emergencyPhone.text,
        medicalCertificateUrl: _certificateUrl.text,
        medicalCertificateValidUntil: _certificateDate,
        notes: _notes.text,
        isActive: old?.isActive ?? true,
        photoUrl: old?.photoUrl,
        remainingPasses: old?.remainingPasses ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.member == null ? 'Nouvel adhérent' : 'Modifier la fiche',
    ),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.member case final member?) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.confirmation_number_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cours restants',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                'Solde cumulé des cartes non épuisées',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${member.remainingPasses}',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstName,
                      decoration: const InputDecoration(labelText: 'Prénom *'),
                      validator: _required,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastName,
                      decoration: const InputDecoration(labelText: 'Nom *'),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
                validator: (value) {
                  if (value != null &&
                      value.trim().isNotEmpty &&
                      !value.contains('@')) {
                    return 'Adresse e-mail invalide.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(membership: false),
                    icon: const Icon(Icons.cake_outlined),
                    label: Text('Naissance : ${_formatDate(_birthDate)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(membership: true),
                    icon: const Icon(Icons.verified_outlined),
                    label: Text(
                      'Cotisation jusqu’au ${_formatDate(_membershipDate)}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _certificateUrl,
                decoration: const InputDecoration(
                  labelText: 'Lien / chemin du certificat médical',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      _pickDate(membership: false, certificate: true),
                  icon: const Icon(Icons.medical_information_outlined),
                  label: Text(
                    'Certificat valable jusqu’au ${_formatDate(_certificateDate)}',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emergencyName,
                decoration: const InputDecoration(
                  labelText: 'Contact d’urgence',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emergencyPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone d’urgence',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes',
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

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Champ obligatoire.' : null;
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('Impossible de charger les adhérents'),
          const SizedBox(height: 8),
          SelectableText(error.toString(), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

Member _withPhoto(Member member, String photoUrl) => Member(
  id: member.id,
  firstName: member.firstName,
  lastName: member.lastName,
  phone: member.phone,
  email: member.email,
  birthDate: member.birthDate,
  photoUrl: photoUrl,
  membershipValidUntil: member.membershipValidUntil,
  medicalCertificateUrl: member.medicalCertificateUrl,
  medicalCertificateValidUntil: member.medicalCertificateValidUntil,
  emergencyContactName: member.emergencyContactName,
  emergencyContactPhone: member.emergencyContactPhone,
  notes: member.notes,
  isActive: member.isActive,
  remainingPasses: member.remainingPasses,
);
