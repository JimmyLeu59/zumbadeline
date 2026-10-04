import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/supabase/supabase_providers.dart';
import '../features/auth/presentation/auth_gate.dart';
import 'theme/zumba_theme.dart';

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
          const Image(
            image: AssetImage('assets/images/zumba_background.png'),
            fit: BoxFit.cover,
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
