import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _latestReleaseUrl =
    'https://api.github.com/repos/JimmyLeu59/zumbadeline/releases/latest';

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.notes,
    required this.downloadUrl,
  });

  final String version;
  final String notes;
  final Uri downloadUrl;
}

/// Compare deux versions « 1.2.3 » (suffixes +build / -pre ignorés).
int compareVersions(String a, String b) {
  List<int> parse(String v) => v
      .replaceFirst(RegExp(r'^v'), '')
      .split(RegExp(r'[+-]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final pa = parse(a);
  final pb = parse(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Retourne la mise à jour disponible, ou null si l'app est à jour
/// ou si la plateforme n'est pas gérée.
Future<AppUpdate?> checkForUpdate() async {
  if (kIsWeb) return null;
  final suffix = switch (defaultTargetPlatform) {
    TargetPlatform.windows => '.exe',
    TargetPlatform.android => '.apk',
    _ => null,
  };
  if (suffix == null) return null;

  final response = await http
      .get(
        Uri.parse(_latestReleaseUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      )
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    throw Exception('GitHub a répondu ${response.statusCode}');
  }
  final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
  final tag = (json['tag_name'] as String?) ?? '';
  final current = (await PackageInfo.fromPlatform()).version;
  if (compareVersions(tag, current) <= 0) return null;

  final assets = (json['assets'] as List? ?? const []).cast<Map>();
  final asset = assets.firstWhere(
    (a) => (a['name'] as String).toLowerCase().endsWith(suffix),
    orElse: () => const {},
  );
  final url = asset['browser_download_url'] as String?;
  if (url == null) return null;
  return AppUpdate(
    version: tag.replaceFirst(RegExp(r'^v'), ''),
    notes: (json['body'] as String?) ?? '',
    downloadUrl: Uri.parse(url),
  );
}

/// Vérifie et propose la mise à jour. [silent] masque « à jour » et les erreurs.
Future<void> promptForUpdate(
  BuildContext context, {
  bool silent = true,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  AppUpdate? update;
  try {
    update = await checkForUpdate();
  } catch (error) {
    if (!silent) {
      messenger.showSnackBar(
        SnackBar(content: Text('Vérification impossible : $error')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  if (update == null) {
    if (!silent) {
      messenger.showSnackBar(
        const SnackBar(content: Text('L’application est à jour.')),
      );
    }
    return;
  }
  final found = update;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Version ${found.version} disponible'),
      content: SingleChildScrollView(
        child: Text(
          found.notes.isEmpty
              ? 'Une nouvelle version est disponible.'
              : found.notes,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Télécharger'),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await launchUrl(found.downloadUrl, mode: LaunchMode.externalApplication);
  }
}
