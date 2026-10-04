import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/offline_store.dart';
import '../reports/report_service.dart';
import '../../features/agenda/data/session_service.dart';
import '../../features/agenda/domain/class_session.dart';
import '../../features/choreography/data/choreography_service.dart';
import '../../features/choreography/domain/track.dart';
import '../../features/finances/data/finance_service.dart';
import '../../features/finances/domain/payment.dart';
import '../../features/members/data/member_service.dart';
import '../../features/members/domain/member.dart';
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
      .select('id, display_name, role, teaching_dances, photo_url')
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

final staffPhotoUrlProvider = FutureProvider.family<String?, String?>((ref, path) {
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

final memberPhotoUrlProvider =
    FutureProvider.family<String?, String?>((ref, path) {
  return ref.watch(memberServiceProvider).signedPhotoUrl(path);
});

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService(
    ref.watch(supabaseClientProvider),
    ref.watch(offlineStoreProvider),
  );
});

final financeServiceProvider = Provider<FinanceService>((ref) {
  return FinanceService(ref.watch(supabaseClientProvider));
});

final membersProvider = FutureProvider<List<Member>>((ref) {
  ref.watch(offlineStatusProvider);
  return ref.watch(memberServiceProvider).listMembers();
});

final tracksProvider = FutureProvider<List<Track>>((ref) {
  ref.watch(offlineStatusProvider);
  return ref.watch(choreographyServiceProvider).listTracks();
});

final sessionsProvider = FutureProvider<List<ClassSession>>((ref) {
  ref.watch(offlineStatusProvider);
  return ref.watch(sessionServiceProvider).listSessions();
});

final paymentsProvider = FutureProvider<List<Payment>>((ref) {
  return ref.watch(financeServiceProvider).listPayments();
});

final pricingProvider = FutureProvider<PricingSettings>((ref) {
  return ref.watch(financeServiceProvider).getPricing();
});

final mostPlayedTracksProvider = FutureProvider((ref) {
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 30));
  return ref
      .watch(statisticsServiceProvider)
      .mostPlayedTracks(from: from, to: now, limit: 10);
});
