import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  static const _rememberedEmailKey = 'zumba_remembered_email';
  static const _secureStorage = FlutterSecureStorage();

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberEmail = false;
  bool _isLoadingRememberedEmail = true;
  String? _notice;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreRememberedEmail());
  }

  Future<void> _restoreRememberedEmail() async {
    try {
      final email = await _secureStorage.read(key: _rememberedEmailKey);
      if (!mounted) return;
      if (email != null && email.isNotEmpty) {
        _emailController.text = email;
        setState(() => _rememberEmail = true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _notice = 'Impossible de récupérer l’adresse mémorisée : $error';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingRememberedEmail = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _notice = null;
      _error = null;
    });
    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .signInWithPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      TextInput.finishAutofillContext(shouldSave: true);
      try {
        if (_rememberEmail) {
          await _secureStorage.write(
            key: _rememberedEmailKey,
            value: _emailController.text.trim(),
          );
        } else {
          await _secureStorage.delete(key: _rememberedEmailKey);
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _notice =
                'Connexion réussie, mais la préférence d’adresse e-mail '
                'n’a pas pu être enregistrée : $error';
          });
        }
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _authErrorMessage(error));
    } catch (error) {
      if (mounted) setState(() => _error = 'Une erreur est survenue : $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = 'Saisissez une adresse e-mail valide pour recevoir le lien.';
        _notice = null;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(supabaseClientProvider).auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() {
          _notice =
              'Si un compte correspond à cette adresse, un e-mail '
              'de réinitialisation va être envoyé.';
        });
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _authErrorMessage(error));
    } catch (error) {
      if (mounted) setState(() => _error = 'Une erreur est survenue : $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      return 'Saisissez une adresse e-mail valide.';
    }
    return null;
  }

  String _authErrorMessage(AuthException error) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'Adresse e-mail ou mot de passe incorrect.';
      case 'email_not_confirmed':
        return 'Confirmez votre adresse e-mail avant de vous connecter.';
      case 'user_already_exists':
        return 'Un compte existe déjà avec cette adresse e-mail.';
      case 'weak_password':
        return 'Choisissez un mot de passe plus robuste.';
      default:
        return error.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'assets/images/app_logo.jpg',
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Icon(
                                  Icons.music_note_rounded,
                                  color: colors.primary,
                                  size: 56,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Zumba & Pédagogie',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Connectez-vous à votre espace',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Adresse e-mail',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) {
                              if (!_isLoading) unawaited(_submit());
                            },
                            decoration: InputDecoration(
                              labelText: 'Mot de passe',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Afficher le mot de passe'
                                    : 'Masquer le mot de passe',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Saisissez votre mot de passe.'
                                : null,
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _rememberEmail,
                            onChanged: _isLoading || _isLoadingRememberedEmail
                                ? null
                                : (value) => setState(
                                    () => _rememberEmail = value ?? false,
                                  ),
                            title: const Text(
                              'Se souvenir de mon adresse e-mail',
                            ),
                            subtitle: const Text(
                              'La session reste ouverte jusqu’à déconnexion. '
                              'Pour le mot de passe, utilisez le gestionnaire '
                              'sécurisé de votre appareil.',
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading ? null : _resetPassword,
                              child: const Text('Mot de passe oublié ?'),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            _MessageBanner(
                              message: _error!,
                              color: colors.error,
                              icon: Icons.error_outline,
                            ),
                          ],
                          if (_notice != null) ...[
                            const SizedBox(height: 8),
                            _MessageBanner(
                              message: _notice!,
                              color: colors.tertiary,
                              icon: Icons.mark_email_read_outlined,
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _isLoading ? null : _submit,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Se connecter'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Les comptes sont créés par une administratrice.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
