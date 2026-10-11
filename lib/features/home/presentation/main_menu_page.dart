import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/offline/offline_store.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/updates/update_service.dart';
import '../../activities/presentation/activity_context_switcher.dart';
import '../../agenda/domain/class_session.dart';
import '../../agenda/presentation/agenda_page.dart';
import '../../attendance/presentation/attendance_page.dart';
import '../../choreography/presentation/choreography_page.dart';
import '../../finances/presentation/finances_page.dart';
import '../../members/presentation/members_page.dart';
import '../../members/domain/card_notification.dart';
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
  String? _memberIdToOpen;
  bool _isSigningOut = false;

  bool get _isAdmin => widget.profile.isAdmin;

  @override
  void initState() {
    super.initState();
    ref.read(activitySelectionProvider.notifier).state =
        widget.profile.activityIdAccess;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) promptForUpdate(context);
    });
  }

  @override
  void didUpdateWidget(covariant MainMenuPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      ref.read(activitySelectionProvider.notifier).state =
          widget.profile.activityIdAccess;
    }
  }

  List<_Destination> get _availableDestinations => [
    _Destination.home,
    _Destination.members,
    _Destination.agenda,
    _Destination.choreography,
    _Destination.attendance,
    _Destination.room,
    if (widget.profile.canViewGlobalFinances) ...[
      _Destination.statistics,
      _Destination.finances,
    ],
    if (_isAdmin) ...[_Destination.settings],
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
    final notificationsState = ref.watch(
      cardNotificationsProvider(widget.profile.id),
    );
    final notifications = notificationsState.valueOrNull ?? const [];
    ref.listen(cardNotificationsProvider(widget.profile.id), (previous, next) {
      final previousIds = {
        for (final item in previous?.valueOrNull ?? const <CardNotification>[])
          if (!item.isRead) item.id,
      };
      final newCount = (next.valueOrNull ?? const <CardNotification>[])
          .where((item) => !item.isRead && !previousIds.contains(item.id))
          .length;
      if (newCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newCount == 1
                  ? 'Un nouveau rappel de carte.'
                  : '$newCount nouveaux rappels de carte.',
            ),
            action: SnackBarAction(
              label: 'Voir',
              onPressed: () => _showCardNotifications(),
            ),
          ),
        );
      }
    });
    final visibleDestinations = _availableDestinations.take(5).toList();
    final isSmall = MediaQuery.sizeOf(context).width < 700;
    final syncStatus = ref.watch(offlineStatusProvider).valueOrNull;
    final activityId = ref.watch(activitySelectionProvider);
    final selectedActivity = ref
        .watch(activitiesProvider)
        .valueOrNull
        ?.where((activity) => activity.id == activityId)
        .firstOrNull;
    final baseTheme = Theme.of(context);
    final colorScheme = selectedActivity == null
        ? baseTheme.colorScheme
        : baseTheme.colorScheme.copyWith(
            primary: selectedActivity.accentColor,
            secondary: selectedActivity.accentColor,
          );
    return Theme(
      data: baseTheme.copyWith(colorScheme: colorScheme),
      child: Scaffold(
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
              Flexible(child: ActivityContextSwitcher(profile: widget.profile)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: _showCardNotifications,
              icon: Badge(
                isLabelVisible: notifications.any((item) => !item.isRead),
                label: Text(
                  '${notifications.where((item) => !item.isRead).length}',
                ),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
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
            Expanded(child: _buildSelectedPage(activityId)),
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
      ),
    );
  }

  void _showCardNotifications() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CardNotificationsSheet(
        staffId: widget.profile.id,
        onOpenMember: _openMemberFromNotification,
        onEmailMember: _emailMemberFromNotification,
      ),
    );
  }

  Future<void> _emailMemberFromNotification(
    CardNotification notification,
  ) async {
    try {
      final contact = await ref
          .read(cardNotificationServiceProvider)
          .memberContactForCard(notification.cardId);
      final email = contact.email?.trim();
      if (email == null || email.isEmpty) {
        throw StateError('Aucune adresse e-mail n’est renseignée.');
      }
      final detail = switch (notification.kind) {
        'expiry' =>
          'Votre carte pour ${notification.activityName} arrive à échéance'
              '${notification.expiresAt == null ? ' prochainement' : ' le ${_dateLabel(notification.expiresAt!)}'}.',
        'last_class' =>
          'Il ne vous reste qu’un cours sur votre carte '
              'pour ${notification.activityName}.',
        _ => notification.message,
      };
      final uri = Uri(
        scheme: 'mailto',
        path: email,
        queryParameters: {
          'subject': 'Votre carte de cours',
          'body':
              'Bonjour ${contact.firstName},\n\n$detail\n\n'
              'N’hésitez pas à nous contacter pour la renouveler.\n\n'
              'À bientôt !',
        },
      );
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Aucune application de messagerie disponible.');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ouverture du courriel impossible : $error')),
        );
      }
    }
  }

  Future<void> _openMemberFromNotification(
    CardNotification notification,
  ) async {
    try {
      final route = await ref
          .read(cardNotificationServiceProvider)
          .memberRouteForCard(notification.cardId);
      final allowedActivityId = widget.profile.activityIdAccess;
      if (allowedActivityId != null && allowedActivityId != route.activityId) {
        throw StateError('Vous n’avez pas accès à cette fiche adhérent.');
      }
      if (!mounted) return;
      setState(() {
        _memberIdToOpen = route.memberId;
        _selected = _Destination.members;
        _initialAttendanceSession = null;
      });
      ref.read(activitySelectionProvider.notifier).state = route.activityId;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ouverture de la fiche impossible : $error')),
        );
      }
    }
  }

  void _showSyncStatus(OfflineStatus status) {
    final message =
        status.lastError ??
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

  Widget _buildSelectedPage(String? activityId) {
    return switch (_selected) {
      _Destination.home => _DashboardPage(
        name: widget.profile.displayName,
        role: widget.profile.role,
        teachingDances: widget.profile.teachingDances,
        destinations: _availableDestinations,
        onSelect: _select,
      ),
      _Destination.members => MembersPage(
        activityId: activityId,
        initialMemberId: _memberIdToOpen,
        onInitialMemberOpened: () {
          if (mounted && _memberIdToOpen != null) {
            setState(() => _memberIdToOpen = null);
          }
        },
      ),
      _Destination.agenda => AgendaPage(
        activityId: activityId,
        onOpenAttendance: _openAttendance,
      ),
      _Destination.choreography => ChoreographyPage(activityId: activityId),
      _Destination.attendance => AttendancePage(
        activityId: activityId,
        initialSession: _initialAttendanceSession,
      ),
      _Destination.room => RoomPage(activityId: activityId),
      _Destination.statistics => StatisticsPage(activityId: activityId),
      _Destination.finances => FinancesPage(activityId: activityId),
      _Destination.settings => const SettingsPage(),
    };
  }
}

class _CardNotificationsSheet extends ConsumerWidget {
  const _CardNotificationsSheet({
    required this.staffId,
    required this.onOpenMember,
    required this.onEmailMember,
  });

  final String staffId;
  final ValueChanged<CardNotification> onOpenMember;
  final ValueChanged<CardNotification> onEmailMember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(cardNotificationsProvider(staffId));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            Expanded(
              child: notifications.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Notifications indisponibles.'),
                        const SizedBox(height: 8),
                        SelectableText(error.toString()),
                        TextButton(
                          onPressed: () => ref.invalidate(
                            cardNotificationsProvider(staffId),
                          ),
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (items) => items.isEmpty
                    ? const Center(
                        child: Text('Aucune notification pour le moment.'),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            leading: Icon(
                              item.kind == 'expiry'
                                  ? Icons.event_busy_outlined
                                  : Icons.confirmation_number_outlined,
                            ),
                            title: Text(item.title),
                            subtitle: Text(item.message),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Préparer un e-mail à l’adhérent',
                                  onPressed: () => onEmailMember(item),
                                  icon: const Icon(Icons.email_outlined),
                                ),
                                if (!item.isRead)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Icon(Icons.circle, size: 10),
                                  ),
                              ],
                            ),
                            onTap: () async {
                              if (!item.isRead) {
                                try {
                                  await ref
                                      .read(cardNotificationServiceProvider)
                                      .markAsRead(
                                        notificationId: item.id,
                                        staffId: staffId,
                                      );
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Impossible de marquer comme lu : $error',
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                              }
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              onOpenMember(item);
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
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

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';
