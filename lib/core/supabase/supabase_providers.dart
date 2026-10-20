import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/offline_store.dart';
import '../reports/report_service.dart';
import '../../features/agenda/data/session_service.dart';
import '../../features/agenda/domain/class_session.dart';
import '../../features/activities/domain/activity.dart';
import '../../features/choreography/data/choreography_service.dart';
import '../../features/choreography/domain/track.dart';
import '../../features/finances/data/finance_service.dart';
import '../../features/finances/domain/payment.dart';
import '../../features/members/data/member_service.dart';
import '../../features/members/data/card_notification_service.dart';
import '../../features/members/domain/card_notification.dart';
import '../../features/members/domain/member.dart';
import '../../features/repertoire/data/repertoire_service.dart';
import '../../features/repertoire/domain/repertoire_song.dart';
import '../../features/staff/data/staff_profile_service.dart';
import '../../features/staff/domain/app_user_profile.dart';
import '../../features/statistics/data/statistics_service.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final offlineStoreProvider = Provider<OfflineStore>((ref) {
  throw StateError('OfflineStore must be initialized before the app starts.');
});

final offlineStatusProvider = StreamProvider<OfflineStatus>((ref) {
  return ref.watch(offlineStoreProvider).watchStatus;
});

final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService(ref.watch(supabaseClientProvider));
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

final activitySelectionProvider = StateProvider<String?>((ref) => null);

final activitiesProvider = FutureProvider<List<Activity>>((ref) async {
  final offlineStore = ref.watch(offlineStoreProvider);
  final client = ref.watch(supabaseClientProvider);
  if (await offlineStore.isOnline()) {
    final rows = await client
        .from('activities')
        .select('id, name, color_code, icon')
        .eq('is_active', true)
        .order('name');
    await offlineStore.cacheJson('activities_cache', rows);
    return rows.map(Activity.fromMap).toList(growable: false);
  }
  final cached = offlineStore.readJsonList('activities_cache');
  if (cached == null) {
    throw StateError('Aucune liste d’activités n’est disponible hors-ligne.');
  }
  return cached.map(Activity.fromMap).toList(growable: false);
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

final userProfileProvider = FutureProvider.family<AppUserProfile?, String>((
  ref,
  userId,
) async {
  final row = await ref
      .watch(supabaseClientProvider)
      .from('profiles')
      .select(
        'id, display_name, role, activity_id_access, teaching_dances, photo_url',
      )
      .eq('id', userId)
      .maybeSingle();
  if (row == null) return null;
  return AppUserProfile.fromMap(row);
});

final staffProfilesProvider = FutureProvider<List<AppUserProfile>>((ref) {
  return ref.watch(staffProfileServiceProvider).listProfiles();
});

final staffProfileServiceProvider = Provider<StaffProfileService>((ref) {
  return StaffProfileService(ref.watch(supabaseClientProvider));
});

final staffPhotoUrlProvider = FutureProvider.family<String?, String?>((
  ref,
  path,
) {
  return ref.watch(staffProfileServiceProvider).signedPhotoUrl(path);
});

final choreographyServiceProvider = Provider<ChoreographyService>((ref) {
  return ChoreographyService(
    ref.watch(supabaseClientProvider),
    ref.watch(offlineStoreProvider),
  );
});

final statisticsServiceProvider = Provider<StatisticsService>((ref) {
  return StatisticsService(ref.watch(supabaseClientProvider));
});

final memberServiceProvider = Provider<MemberService>((ref) {
  return MemberService(
    ref.watch(supabaseClientProvider),
    ref.watch(offlineStoreProvider),
  );
});

final cardNotificationServiceProvider = Provider<CardNotificationService>((
  ref,
) {
  return CardNotificationService(ref.watch(supabaseClientProvider));
});

final cardNotificationsProvider =
    StreamProvider.family<List<CardNotification>, String>((ref, staffId) {
      return ref.watch(cardNotificationServiceProvider).watchForStaff(staffId);
    });

final memberPhotoUrlProvider = FutureProvider.family<String?, String?>((
  ref,
  path,
) {
  return ref.watch(memberServiceProvider).signedPhotoUrl(path);
});

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService(
    ref.watch(supabaseClientProvider),
    ref.watch(offlineStoreProvider),
  );
});

final repertoireServiceProvider = Provider<RepertoireService>((ref) {
  return RepertoireService(
    ref.watch(supabaseClientProvider),
    ref.watch(offlineStoreProvider),
  );
});

final repertoireSongsProvider =
    FutureProvider.family<List<RepertoireSong>, String>((ref, activityId) {
      ref.watch(offlineStatusProvider);
      return ref.watch(repertoireServiceProvider).listSongs(activityId);
    });

final financeServiceProvider = Provider<FinanceService>((ref) {
  return FinanceService(ref.watch(supabaseClientProvider));
});

final membersProvider = FutureProvider<List<Member>>((ref) {
  ref.watch(offlineStatusProvider);
  return ref.watch(memberServiceProvider).listMembers();
});

final membersForActivityProvider = FutureProvider.family<List<Member>, String?>(
  (ref, activityId) {
    ref.watch(offlineStatusProvider);
    return ref.watch(memberServiceProvider).listMembers(activityId: activityId);
  },
);

final tracksProvider = FutureProvider<List<Track>>((ref) {
  ref.watch(offlineStatusProvider);
  return ref.watch(choreographyServiceProvider).listTracks();
});

final tracksForActivityProvider = FutureProvider.family<List<Track>, String?>((
  ref,
  activityId,
) {
  ref.watch(offlineStatusProvider);
  return ref
      .watch(choreographyServiceProvider)
      .listTracks(activityId: activityId);
});

final sessionsProvider = FutureProvider.family<List<ClassSession>, String?>((
  ref,
  activityId,
) {
  ref.watch(offlineStatusProvider);
  return ref.watch(sessionServiceProvider).listSessions(activityId: activityId);
});

final paymentsProvider = FutureProvider.family<List<Payment>, String?>(
  (ref, activityId) =>
      ref.watch(financeServiceProvider).listPayments(activityId: activityId),
);

final pricingProvider = FutureProvider<PricingSettings>((ref) {
  return ref.watch(financeServiceProvider).getPricing();
});

final subscriptionPlansProvider = FutureProvider<List<SubscriptionPlan>>((ref) {
  return ref.watch(financeServiceProvider).listPlans();
});

final mostPlayedTracksProvider = FutureProvider((ref) {
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 30));
  return ref
      .watch(statisticsServiceProvider)
      .mostPlayedTracks(from: from, to: now, limit: 10);
});
