import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../staff/domain/app_user_profile.dart';

class ActivityContextSwitcher extends ConsumerWidget {
  const ActivityContextSwitcher({required this.profile, super.key});

  final AppUserProfile profile;

  static const _association = '__association__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activitiesProvider);
    return activities.when(
      loading: () => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (error, _) => IconButton(
        tooltip: 'Activités indisponibles. Réessayer.',
        onPressed: () => ref.invalidate(activitiesProvider),
        icon: const Icon(Icons.error_outline),
      ),
      data: (allActivities) {
        final isInstructor = profile.role == 'instructor';
        final available = isInstructor
            ? allActivities
                  .where((activity) => activity.id == profile.activityIdAccess)
                  .toList(growable: false)
            : allActivities;
        if (available.isEmpty) {
          return const Tooltip(
            message: 'Aucune activité accessible.',
            child: Icon(Icons.error_outline),
          );
        }
        final selectedId = ref.watch(activitySelectionProvider);
        final selected = available
            .where((activity) => activity.id == selectedId)
            .firstOrNull;
        final accent =
            selected?.accentColor ?? Theme.of(context).colorScheme.primary;
        final value =
            selected?.id ??
            (isInstructor && available.isNotEmpty
                ? available.first.id
                : _association);
        if (isInstructor &&
            available.isNotEmpty &&
            selectedId != available.first.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(activitySelectionProvider.notifier).state =
                available.first.id;
          });
        }

        return Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: .45)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: Icon(Icons.expand_more_rounded, color: accent),
              selectedItemBuilder: (context) => [
                if (!isInstructor)
                  _selectedLabel(
                    icon: Icons.account_balance_rounded,
                    label: 'Vue globale Association',
                    color: accent,
                  ),
                for (final activity in available)
                  _selectedLabel(
                    icon: activity.iconData,
                    label: activity.name,
                    color: activity.accentColor,
                  ),
              ],
              items: [
                if (!isInstructor)
                  const DropdownMenuItem(
                    value: _association,
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_rounded),
                        SizedBox(width: 10),
                        Text('Vue globale Association'),
                      ],
                    ),
                  ),
                for (final activity in available)
                  DropdownMenuItem(
                    value: activity.id,
                    child: Row(
                      children: [
                        Icon(activity.iconData, color: activity.accentColor),
                        const SizedBox(width: 10),
                        Text(activity.name),
                      ],
                    ),
                  ),
              ],
              onChanged: (id) {
                if (id == null) return;
                ref.read(activitySelectionProvider.notifier).state =
                    id == _association ? null : id;
              },
            ),
          ),
        );
      },
    );
  }

  Widget _selectedLabel({
    required IconData icon,
    required String label,
    required Color color,
  }) => Row(
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 8),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}
