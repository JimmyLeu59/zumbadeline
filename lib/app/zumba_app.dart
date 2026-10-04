import 'package:flutter/material.dart';

import 'theme/zumba_theme.dart';

class ZumbaApp extends StatelessWidget {
  const ZumbaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zumba & Pédagogie',
      debugShowCheckedModeBanner: false,
      theme: ZumbaTheme.light,
      darkTheme: ZumbaTheme.dark,
      themeMode: ThemeMode.system,
      home: const _HomePage(),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zumba & Pédagogie')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note_rounded,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Prête à danser ?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'La base de votre espace de gestion est installée.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
