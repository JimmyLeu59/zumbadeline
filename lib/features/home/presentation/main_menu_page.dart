import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/offline_store.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../agenda/domain/class_session.dart';
import '../../agenda/presentation/agenda_page.dart';
import '../../attendance/presentation/attendance_page.dart';
import '../../choreography/presentation/choreography_page.dart';
import '../../finances/presentation/finances_page.dart';
import '../../members/presentation/members_page.dart';
import '../../room/presentation/room_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../statistics/presentation/statistics_page.dart';
import '../../staff/domain/app_user_profile.dart';

enum _Destination {
  home,
  members,
  agenda,
  choreography,
  attendance,
  room,
  statistics,
  finances,
  settings,
}

class MainMenuPage extends ConsumerStatefulWidget {
  const MainMenuPage({required this.profile, super.key});

  final AppUserProfile profile;

  @override
  ConsumerState<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends ConsumerState<MainMenuPage> {
  _Destination _selected = _Destination.home;
  ClassSession? _initialAttendanceSession;
  bool _isSigningOut = false;

  bool get _isAdmin => widget.profile.isAdmin;

  List<_Destination> get _availableDestinations => [
    _Destination.home,
    _Destination.members,
    _Destination.agenda,
    _Destination.choreography,
    _Destination.attendance,
    _Destination.room,
    if (_isAdmin) ...[
      _Destination.statistics,
      _Destination.finances,
      _Destination.settings,
    ],
  ];

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    try {
      await ref.read(supabaseClientProvider).auth.signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de la déconnexion : $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  void _select(_Destination destination) {
    if (!_availableDestinations.contains(destination)) return;
    setState(() {
      _selected = destination;
      if (destination != _Destination.attendance) {
        _initialAttendanceSession = null;
      }
    });
  }

  void _openAttendance(ClassSession session) {
    setState(() {
      _selected = _Destination.attendance;
      _initialAttendanceSession = session;
    });
  }

  void _showMoreMenu() {
    final extra = _availableDestinations
        .where(
          (destination) =>
              destination != _Destination.home &&
              destination != _Destination.members &&
              destination != _Destination.agenda &&
              destination != _Destination.choreography,
        )
        .toList(growable: false);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(
                'Autres espaces',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final destination in extra)
              ListTile(
                leading: Icon(_iconFor(destination)),
                title: Text(_labelFor(destination)),
                selected: destination == _selected,
                onTap: () {
                  Navigator.pop(context);
                  _select(destination);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleDestinations = _availableDestinations.take(5).toList();
    final isSmall = MediaQuery.sizeOf(context).width < 700;
    final syncStatus = ref.watch(offlineStatusProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset(
                'assets/images/app_logo.jpg',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(child: Text(_labelFor(_selected))),
          ],
        ),
        actions: [
          if (syncStatus != null)
            IconButton(
              tooltip: 'État de synchronisation',
              onPressed: () => _showSyncStatus(syncStatus),
              icon: Badge(
                isLabelVisible: syncStatus.pendingCheckIns > 0,
                label: Text('${syncStatus.pendingCheckIns}'),
                child: Icon(
                  syncStatus.isOnline
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                ),
              ),
            ),
          if (!_isSmall(context))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  widget.profile.displayName.isEmpty
                      ? widget.profile.role
                      : widget.profile.displayName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Se déconnecter',
            onPressed: _isSigningOut ? null : _signOut,
            icon: _isSigningOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (!isSmall)
            NavigationRail(
              selectedIndex: _railIndex(visibleDestinations),
              onDestinationSelected: (index) {
                if (index == visibleDestinations.length) {
                  _showMoreMenu();
                } else {
                  _select(visibleDestinations[index]);
                }
              },
              labelType: NavigationRailLabelType.selected,
              destinations: [
                for (final destination in visibleDestinations)
                  NavigationRailDestination(
                    icon: Icon(_iconFor(destination)),
                    selectedIcon: Icon(_iconFor(destination)),
                    label: Text(_labelFor(destination)),
                  ),
                const NavigationRailDestination(
                  icon: Icon(Icons.more_horiz_rounded),
                  label: Text('Plus'),
                ),
              ],
            ),
          if (!isSmall) const VerticalDivider(width: 1),
          Expanded(child: _buildSelectedPage()),
        ],
      ),
      bottomNavigationBar: isSmall
          ? NavigationBar(
              selectedIndex: _bottomIndex(),
              onDestinationSelected: (index) {
                if (index == 4) {
                  _showMoreMenu();
                  return;
                }
                _select(_Destination.values[index]);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Accueil',
                ),
                NavigationDestination(
                  icon: Icon(Icons.groups_outlined),
                  selectedIcon: Icon(Icons.groups_rounded),
                  label: 'Adhérents',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: 'Agenda',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music_rounded),
                  label: 'Chorés',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz_rounded),
                  label: 'Plus',
                ),
              ],
            )
          : null,
    );
  }

  void _showSyncStatus(OfflineStatus status) {
    final message = status.lastError ??
        (status.pendingCheckIns > 0
            ? '${status.pendingCheckIns} pointage(s) en attente.'
            : status.isOnline
                ? 'Données synchronisées.'
                : 'Hors-ligne. Les pointages seront synchronisés au retour du réseau.');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Synchronisation'),
        content: Text(message),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await ref
                  .read(offlineStoreProvider)
                  .syncPending(ref.read(supabaseClientProvider));
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.sync),
            label: const Text('Synchroniser'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  bool _isSmall(BuildContext context) => MediaQuery.sizeOf(context).width < 700;

  int _bottomIndex() {
    final index = _Destination.values.indexOf(_selected);
    return index >= 0 && index < 4 ? index : 4;
  }

  int _railIndex(List<_Destination> destinations) {
    final index = destinations.indexOf(_selected);
    return index < 0 ? destinations.length : index;
  }

  Widget _buildSelectedPage() {
    return switch (_selected) {
      _Destination.home => _DashboardPage(
        name: widget.profile.displayName,
        role: widget.profile.role,
        teachingDances: widget.profile.teachingDances,
        destinations: _availableDestinations,
        onSelect: _select,
      ),
      _Destination.members => const MembersPage(),
      _Destination.agenda => AgendaPage(onOpenAttendance: _openAttendance),
      _Destination.choreography => const ChoreographyPage(),
      _Destination.attendance =>
        AttendancePage(initialSession: _initialAttendanceSession),
      _Destination.room => const RoomPage(),
      _Destination.statistics => const StatisticsPage(),
      _Destination.finances => const FinancesPage(),
      _Destination.settings => const SettingsPage(),
    };
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({
    required this.name,
    required this.role,
    required this.teachingDances,
    required this.destinations,
    required this.onSelect,
  });

  final String name;
  final String role;
  final List<String> teachingDances;
  final List<_Destination> destinations;
  final ValueChanged<_Destination> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final shortcuts = destinations
        .where((destination) => destination != _Destination.home)
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.primary, const Color(0xFF7A2CA0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 540;
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(name),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Votre espace de gestion des cours et de la pédagogie.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white.withValues(alpha: .9),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Chip(
                          avatar: Icon(
                            role == 'admin'
                                ? Icons.stars_rounded
                                : Icons.music_note_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: Text(
                            role == 'admin'
                                ? 'Administratrice'
                                : teachingDances.isEmpty
                                    ? 'Animateur·trice'
                                    : 'Animateur·trice · '
                                        '${teachingDances.join(', ')}',
                          ),
                          backgroundColor: Colors.white.withValues(alpha: .18),
                          labelStyle: const TextStyle(color: Colors.white),
                          side: BorderSide.none,
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 20),
                    const Icon(
                      Icons.celebration_rounded,
                      size: 88,
                      color: Color(0xFFFFD166),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 28),
        Text('Accès rapides', style: theme.textTheme.titleLarge),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 4
                : constraints.maxWidth >= 600
                ? 3
                : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shortcuts.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 128,
              ),
              itemBuilder: (context, index) {
                final destination = shortcuts[index];
                return _ShortcutCard(
                  destination: destination,
                  onTap: () => onSelect(destination),
                );
              },
            );
          },
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: colors.secondary.withValues(alpha: .15),
              child: Icon(Icons.info_outline, color: colors.secondary),
            ),
            title: const Text('Bienvenue dans votre espace'),
            subtitle: const Text(
              'Choisissez un raccourci pour accéder aux outils de gestion.',
            ),
          ),
        ),
      ],
    );
  }

  String _greeting(String name) {
    final firstName = name.trim().split(RegExp(r'\s+')).first;
    return firstName.isEmpty ? 'Prête à danser ?' : 'Bonjour, $firstName !';
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.destination, required this.onTap});

  final _Destination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(_iconFor(destination), color: colors.primary, size: 28),
              Text(
                _labelFor(destination),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _labelFor(_Destination destination) => switch (destination) {
  _Destination.home => 'Accueil',
  _Destination.members => 'Adhérents',
  _Destination.agenda => 'Agenda',
  _Destination.choreography => 'Chorégraphies',
  _Destination.attendance => 'Pointage rapide',
  _Destination.room => 'Mode en salle',
  _Destination.statistics => 'Statistiques',
  _Destination.finances => 'Finances',
  _Destination.settings => 'Paramètres',
};

IconData _iconFor(_Destination destination) => switch (destination) {
  _Destination.home => Icons.home_rounded,
  _Destination.members => Icons.groups_rounded,
  _Destination.agenda => Icons.calendar_month_rounded,
  _Destination.choreography => Icons.library_music_rounded,
  _Destination.attendance => Icons.how_to_reg_rounded,
  _Destination.room => Icons.play_circle_outline_rounded,
  _Destination.statistics => Icons.insights_rounded,
  _Destination.finances => Icons.payments_outlined,
  _Destination.settings => Icons.settings_outlined,
};
