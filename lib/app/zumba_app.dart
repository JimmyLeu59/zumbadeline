import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/supabase/supabase_providers.dart';
import '../features/auth/presentation/auth_gate.dart';
import 'theme/zumba_theme.dart';

const _backgroundAssets = {
  '00000000-0000-0000-0000-000000000002':
      'assets/images/chant_background.jpg',
  '00000000-0000-0000-0000-000000000003':
      'assets/images/line_dance_background.jpg',
};

class ZumbaApp extends ConsumerStatefulWidget {
  const ZumbaApp({super.key});

  @override
  ConsumerState<ZumbaApp> createState() => _ZumbaAppState();
}

class _ZumbaAppState extends ConsumerState<ZumbaApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreTheme());
  }

  Future<void> _restoreTheme() async {
    final saved = ref.read(offlineStoreProvider).readString('theme_mode');
    final modes = ThemeMode.values.where((mode) => mode.name == saved);
    if (modes.isNotEmpty) {
      ref.read(themeModeProvider.notifier).state = modes.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zumba & Pédagogie',
      debugShowCheckedModeBanner: false,
      theme: ZumbaTheme.light,
      darkTheme: ZumbaTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: AssetImage(
              _backgroundAssets[ref.watch(activitySelectionProvider)] ??
                  'assets/images/zumba_background.png',
            ),
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
          ColoredBox(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xB8000614)
                : const Color(0xB8FFFFFF),
          ),
          ?child,
        ],
      ),
      home: const AuthGate(),
    );
  }
}
