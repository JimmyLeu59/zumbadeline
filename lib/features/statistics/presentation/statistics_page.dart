import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({this.activityId, super.key});

  final String? activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersForActivityProvider(activityId));
    final sessions = ref.watch(sessionsProvider(activityId));
    final tracks = ref.watch(tracksForActivityProvider(activityId));
    final plays = ref.watch(mostPlayedTracksProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Vue d’ensemble',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 900
                ? 4
                : constraints.maxWidth > 560
                ? 2
                : 1;
            final values = [
              _SummaryValue(
                title: 'Adhérents actifs',
                icon: Icons.groups_outlined,
                future: members.when(
                  data: (value) =>
                      '${value.where((member) => member.isActive).length}',
                  loading: () => '…',
                  error: (_, stackTrace) => 'Erreur',
                ),
              ),
              _SummaryValue(
                title: 'Séances planifiées',
                icon: Icons.calendar_month_outlined,
                future: sessions.when(
                  data: (value) =>
                      '${value.where((session) => session.status == 'scheduled').length}',
                  loading: () => '…',
                  error: (_, stackTrace) => 'Erreur',
                ),
              ),
              _SummaryValue(
                title: 'Morceaux',
                icon: Icons.library_music_outlined,
                future: tracks.when(
                  data: (value) => '${value.length}',
                  loading: () => '…',
                  error: (_, stackTrace) => 'Erreur',
                ),
              ),
              _SummaryValue(
                title: 'Cartes à relancer',
                icon: Icons.notification_important_outlined,
                future: members.when(
                  data: (value) =>
                      '${value.where((member) => member.isActive && member.subscriptionUntil == null && member.remainingPasses <= 1).length}',
                  loading: () => '…',
                  error: (_, stackTrace) => 'Erreur',
                ),
              ),
            ];
            final width =
                (constraints.maxWidth - ((columns - 1) * 12)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final item in values)
                  SizedBox(
                    width: width,
                    child: _SummaryCard(value: item),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        Text(
          'Morceaux les plus joués · 30 derniers jours',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        plays.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Statistiques indisponibles'),
              subtitle: Text(error.toString()),
              trailing: IconButton(
                onPressed: () => ref.invalidate(mostPlayedTracksProvider),
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
          data: (items) => items.isEmpty
              ? const Card(
                  child: ListTile(
                    leading: Icon(Icons.music_note_outlined),
                    title: Text('Pas encore de morceaux joués'),
                    subtitle: Text(
                      'Les morceaux des séances terminées apparaîtront ici.',
                    ),
                  ),
                )
              : Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        ListTile(
                          leading: CircleAvatar(child: Text('${i + 1}')),
                          title: Text(items[i].title),
                          subtitle: Text(items[i].artist),
                          trailing: Text('${items[i].playCount} fois'),
                        ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () {
              ref.invalidate(membersForActivityProvider(activityId));
              ref.invalidate(sessionsProvider(activityId));
              ref.invalidate(tracksForActivityProvider(activityId));
              ref.invalidate(mostPlayedTracksProvider);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Actualiser'),
          ),
        ),
      ],
    );
  }
}

class _SummaryValue {
  const _SummaryValue({
    required this.title,
    required this.icon,
    required this.future,
  });
  final String title;
  final IconData icon;
  final String future;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.value});
  final _SummaryValue value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          CircleAvatar(child: Icon(value.icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value.title),
                Text(
                  value.future,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
