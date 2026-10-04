import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/zumba_app.dart';
import 'core/offline/offline_store.dart';
import 'core/supabase/supabase_providers.dart';
import 'core/supabase/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  final offlineStore = await OfflineStore.open();
  offlineStore.setUser(Supabase.instance.client.auth.currentUser?.id);
  await offlineStore.startSync(Supabase.instance.client);
  runApp(
    ProviderScope(
      overrides: [offlineStoreProvider.overrideWithValue(offlineStore)],
      child: const ZumbaApp(),
    ),
  );
}
