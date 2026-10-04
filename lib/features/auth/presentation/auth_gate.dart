import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../home/presentation/main_menu_page.dart';
import 'sign_in_page.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return authState.when(
      loading: () => const _LoadingPage(),
      error: (error, _) => _ProblemPage(
        title: 'Connexion au service impossible',
        message: error.toString(),
        onRetry: () => ref.invalidate(authStateProvider),
      ),
      data: (state) {
        final user = state.session?.user;
        final offlineStore = ref.read(offlineStoreProvider);
        if (offlineStore.setUser(user?.id) && user != null) {
          unawaited(
            offlineStore.syncPending(ref.read(supabaseClientProvider)),
          );
        }
        if (user == null) return const SignInPage();
        return _ProfileGate(userId: user.id);
      },
    );
  }
}

class _ProfileGate extends ConsumerWidget {
  const _ProfileGate({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(userId));
    return profile.when(
      loading: () => const _LoadingPage(),
      error: (error, _) => _ProblemPage(
        title: 'Impossible de charger le profil',
        message: error.toString(),
        onRetry: () => ref.invalidate(userProfileProvider(userId)),
      ),
      data: (value) {
        if (value == null) {
          return _ProblemPage(
            title: 'Profil non configuré',
            message:
                'Votre compte est authentifié, mais aucun profil ne lui est associé. '
                'Appliquez la migration Supabase puis demandez à une administratrice '
                'de vérifier la table profiles.',
            onRetry: () => ref.invalidate(userProfileProvider(userId)),
          );
        }
        return MainMenuPage(profile: value);
      },
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ProblemPage extends ConsumerWidget {
  const _ProblemPage({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                SelectableText(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Réessayer'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ref.read(supabaseClientProvider).auth.signOut();
                        ref.invalidate(authStateProvider);
                      },
                      child: const Text('Se déconnecter'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
