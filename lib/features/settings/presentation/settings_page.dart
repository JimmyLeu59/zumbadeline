import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../finances/domain/payment.dart';
import '../../staff/domain/app_user_profile.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pricing = ref.watch(pricingProvider);
    return pricing.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Impossible de charger les tarifs'),
              SelectableText(error.toString()),
              OutlinedButton(
                onPressed: () => ref.invalidate(pricingProvider),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
      data: (settings) => _PricingForm(settings: settings),
    );
  }
}

class _PricingForm extends ConsumerStatefulWidget {
  const _PricingForm({required this.settings});
  final PricingSettings settings;

  @override
  ConsumerState<_PricingForm> createState() => _PricingFormState();
}

class _PricingFormState extends ConsumerState<_PricingForm> {
  late final TextEditingController _membership = _controller(
    widget.settings.annualMembershipFee,
  );
  late final TextEditingController _single = _controller(
    widget.settings.singleClassPrice,
  );
  late final TextEditingController _firstCard = _controller(
    widget.settings.firstCardPrice,
  );
  late final TextEditingController _renewal = _controller(
    widget.settings.renewalCardPrice,
  );
  late final TextEditingController _passCount = TextEditingController(
    text: widget.settings.cardPassCount.toString(),
  );
  bool _saving = false;

  TextEditingController _controller(double value) =>
      TextEditingController(text: value.toStringAsFixed(2));

  @override
  void dispose() {
    _membership.dispose();
    _single.dispose();
    _firstCard.dispose();
    _renewal.dispose();
    _passCount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final annual = _parse(_membership.text);
    final single = _parse(_single.text);
    final firstCard = _parse(_firstCard.text);
    final renewal = _parse(_renewal.text);
    final passCount = int.tryParse(_passCount.text);
    if ([annual, single, firstCard, renewal].contains(null) ||
        passCount == null ||
        passCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vérifiez les montants et le nombre de passages.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(financeServiceProvider)
          .savePricing(
            PricingSettings(
              annualMembershipFee: annual!,
              singleClassPrice: single!,
              firstCardPrice: firstCard!,
              renewalCardPrice: renewal!,
              cardPassCount: passCount,
              currency: widget.settings.currency,
            ),
          );
      ref.invalidate(pricingProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Tarifs mis à jour.')));
      }
    } catch (error) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Enregistrement impossible'),
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  double? _parse(String value) =>
      double.tryParse(value.replaceAll(',', '.').trim());

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Tarifs', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text(
        'Ces prix sont utilisés automatiquement pour les cartes et le pointage à l’unité.',
      ),
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth > 760
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: width,
                child: _priceField(
                  _membership,
                  'Cotisation annuelle (€)',
                  Icons.verified_outlined,
                ),
              ),
              SizedBox(
                width: width,
                child: _priceField(
                  _single,
                  'Cours à l’unité (€)',
                  Icons.confirmation_number_outlined,
                ),
              ),
              SizedBox(
                width: width,
                child: _priceField(
                  _firstCard,
                  'Première carte (€)',
                  Icons.card_membership_outlined,
                ),
              ),
              SizedBox(
                width: width,
                child: _priceField(
                  _renewal,
                  'Renouvellement de carte (€)',
                  Icons.refresh_rounded,
                ),
              ),
              SizedBox(
                width: width,
                child: TextField(
                  controller: _passCount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Passages par carte',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Enregistrer les tarifs'),
        ),
      ),
      const SizedBox(height: 24),
      Text('Apparence', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      DropdownButtonFormField<ThemeMode>(
        initialValue: ref.watch(themeModeProvider),
        decoration: const InputDecoration(
          labelText: 'Thème de l’application',
          prefixIcon: Icon(Icons.palette_outlined),
        ),
        items: const [
          DropdownMenuItem(
            value: ThemeMode.system,
            child: Text('Suivre le système'),
          ),
          DropdownMenuItem(value: ThemeMode.light, child: Text('Clair')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('Sombre')),
        ],
        onChanged: (mode) async {
          if (mode == null) return;
          ref.read(themeModeProvider.notifier).state = mode;
          try {
            await ref
                .read(offlineStoreProvider)
                .saveString('theme_mode', mode.name);
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Préférence non enregistrée : $error')),
              );
            }
          }
        },
      ),
      const SizedBox(height: 24),
      Text('Équipe pédagogique', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        'Renseignez le nom affiché et les disciplines de chaque compte. '
        'Ces informations apparaîtront au-dessus du trombinoscope.',
      ),
      const SizedBox(height: 8),
      const _StaffProfilesSection(),
      const SizedBox(height: 24),
      const Card(
        child: ListTile(
          leading: Icon(Icons.security_outlined),
          title: Text('Accès administrateur'),
          subtitle: Text(
            'Les rôles utilisateurs et les politiques de sécurité se gèrent '
            'dans Supabase, jamais depuis un formulaire public.',
          ),
        ),
      ),
    ],
  );

  Widget _priceField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
  );
}

class _StaffProfilesSection extends ConsumerWidget {
  const _StaffProfilesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(staffProfilesProvider);
    return profiles.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Impossible de charger les comptes'),
          subtitle: Text(error.toString()),
          trailing: IconButton(
            tooltip: 'Réessayer',
            onPressed: () => ref.invalidate(staffProfilesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ),
      ),
      data: (items) => Card(
        child: Column(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0) const Divider(height: 1),
              ListTile(
                leading: _InstructorAvatar(
                  profile: items[index],
                  radius: 22,
                ),
                title: Text(
                  items[index].displayName.isEmpty
                      ? 'Nom à renseigner'
                      : items[index].displayName,
                ),
                subtitle: Text(
                  items[index].teachingDances.isEmpty
                      ? 'Aucune discipline renseignée'
                      : 'Animateur·trice : '
                            '${items[index].teachingDances.join(', ')}',
                ),
                trailing: Wrap(
                  spacing: 0,
                  children: [
                    IconButton(
                      tooltip: 'Ajouter ou modifier la photo',
                      onPressed: () =>
                          _changePhoto(context, ref, items[index]),
                      icon: const Icon(Icons.add_a_photo_outlined),
                    ),
                    IconButton(
                      tooltip: 'Modifier le profil animateur',
                      onPressed: () => _edit(context, ref, items[index]),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                onTap: () => _edit(context, ref, items[index]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AppUserProfile profile,
  ) async {
    final updated = await showDialog<_InstructorDetails>(
      context: context,
      builder: (_) => _InstructorDetailsDialog(profile: profile),
    );
    if (updated == null || !context.mounted) return;
    try {
      await ref
          .read(staffProfileServiceProvider)
          .saveInstructorProfile(
            id: profile.id,
            displayName: updated.displayName,
            teachingDances: updated.teachingDances,
          );
      ref.invalidate(staffProfilesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil animateur mis à jour.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Enregistrement impossible'),
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
    }
  }

  Future<void> _changePhoto(
    BuildContext context,
    WidgetRef ref,
    AppUserProfile profile,
  ) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows &&
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
    if (source == null || !context.mounted) return;
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (image == null) return;
      final service = ref.read(staffProfileServiceProvider);
      final path = await service.uploadProfilePhoto(
        profileId: profile.id,
        bytes: await image.readAsBytes(),
        extension: image.name.split('.').last,
      );
      ref.invalidate(staffPhotoUrlProvider(profile.photoUrl));
      ref.invalidate(staffPhotoUrlProvider(path));
      ref.invalidate(staffProfilesProvider);
      ref.invalidate(userProfileProvider(profile.id));
      await service.deleteProfilePhoto(profile.photoUrl);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo de l’animateur mise à jour.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Photo non enregistrée'),
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
    }
  }
}

class _InstructorAvatar extends ConsumerWidget {
  const _InstructorAvatar({required this.profile, required this.radius});

  final AppUserProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoUrl =
        ref.watch(staffPhotoUrlProvider(profile.photoUrl)).valueOrNull;
    return CircleAvatar(
      radius: radius,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
      child: Text(
        profile.displayName.trim().isEmpty
            ? 'A'
            : profile.displayName.trim()[0].toUpperCase(),
      ),
    );
  }
}

class _InstructorDetails {
  const _InstructorDetails({
    required this.displayName,
    required this.teachingDances,
  });

  final String displayName;
  final List<String> teachingDances;
}

class _InstructorDetailsDialog extends StatefulWidget {
  const _InstructorDetailsDialog({required this.profile});

  final AppUserProfile profile;

  @override
  State<_InstructorDetailsDialog> createState() =>
      _InstructorDetailsDialogState();
}

class _InstructorDetailsDialogState extends State<_InstructorDetailsDialog> {
  late final TextEditingController _name;
  late final TextEditingController _dances;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.displayName);
    _dances = TextEditingController(
      text: widget.profile.teachingDances.join(', '),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _dances.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Saisissez le nom à afficher.');
      return;
    }
    Navigator.pop(
      context,
      _InstructorDetails(
        displayName: name,
        teachingDances: _dances.text
            .split(',')
            .map((dance) => dance.trim())
            .where((dance) => dance.isNotEmpty)
            .toSet()
            .toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Profil animateur'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nom affiché',
              hintText: 'Ex. Camille Dupont',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dances,
            decoration: const InputDecoration(
              labelText: 'Disciplines animées',
              hintText: 'Line Dance, danse celtique',
              helperText: 'Séparez les disciplines par des virgules.',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
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
