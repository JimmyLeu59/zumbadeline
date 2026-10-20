# Zumba & Pédagogie

Application Flutter pour l'administration des adhérents, des cours et de la bibliothèque chorégraphique, avec Supabase comme backend.

## Architecture Flutter

Organisation feature-first, avec séparation des responsabilités :

```text
lib/
  app/                       # composition, navigation et thème
  core/                      # erreurs, médias, synchronisation et utilitaires partagés
  features/
    members/                 # domain / data / application / presentation
    choreography/            # modèles et accès à la bibliothèque
    room/                    # préparation et régie en salle
    attendance/              # pointage et file d'opérations
    finances/                # paiements et reçus
    agenda/                  # cours et événements
    statistics/              # agrégats et tableaux de bord
    settings/                # tarifs, association et préférences
supabase/
  migrations/                # SQL versionné
  functions/                 # Edge Functions email/SMS/reçus (à ajouter)
```

Riverpod est le conteneur d'état et d'injection de dépendances. Les services de données reçoivent leur `SupabaseClient` au constructeur; l'écran ne dépend donc pas directement de Supabase. Les modèles métier restent indépendants du widget tree.

### Hors-ligne et médias

Le mode salle utilise un cache Hive chiffré (clé conservée dans le stockage sécurisé iOS/Android) et `connectivity_plus`. Les membres actifs (sans informations médicales/contact), les cartes, séances, présences déjà pointées, fiches musicales et playlists sont mis en cache par compte. Le pointage hors-ligne reçoit un UUID d'opération et est placé dans une file persistante; le solde de carte est décrémenté dans le cache local et chaque opération est rejouée automatiquement lors du retour réseau par `check_in_member_with_payment`. La contrainte unique séance/adhérent et la fonction transactionnelle côté PostgreSQL protègent contre les doublons et décrémentations multiples.

Les mutations hors-ligne disponibles sont les pointages seulement. L'ajout/modification de membres, séances, paiements, tarifs, playlists et répertoires nécessite une connexion. La clôture d'une séance est également en ligne et attend la synchronisation des pointages en file. Le cache doit d'abord être rempli en ligne sur l'appareil. `connectivity_plus` détecte l'interface réseau, pas la disponibilité du serveur; en cas de perte réseau entre le contrôle et le RPC, le pointage est placé en file si le système signale alors l'absence de connexion. Un pointage en échec de validation côté serveur reste visible comme erreur de synchronisation et doit être résolu avant de considérer la caisse rapprochée.

Les médias restent dans les buckets privés Supabase Storage. En local, conserver une copie/cache et le chemin de l'objet (pas une URL signée expirante) dans la base; envoyer la pièce jointe puis mettre à jour son chemin au retour du réseau. Produire des URL signées à durée limitée pour l'affichage. Limiter les types et tailles MIME, et ne pas rendre publics les certificats médicaux ni les photos.

Les reçus et relances email/SMS doivent être déclenchés par Edge Functions, utilisant des secrets côté serveur et des fournisseurs configurés séparément. Ne jamais mettre de clé `service_role` dans l'application Flutter. Les données de paiement ci-dessous enregistrent le moyen et le montant, pas les données de carte bancaire.

## Schéma Supabase

Appliquer toutes les migrations dans l'ordre avec Supabase CLI (`supabase db push`) ou exécuter les scripts dans SQL Editor après avoir vérifié l'historique du projet. `202610040001_initial_schema.sql` est le schéma initial et ne doit pas être rejoué si les tables existent déjà. Les migrations suivantes ajoutent notamment l'authentification et les profils, les RPC de caisse et de pointage, les activités multiples, les forfaits, les notifications et les suppressions protégées. La migration `202610200001_session_workflow_and_singing.sql` ajoute la clôture transactionnelle des séances (absences confirmées, morceaux réellement joués et notes de suivi), le répertoire de chant distinct des chorégraphies et le bucket privé des documents de répétition. Si le schéma a été initialisé manuellement, comparez les migrations appliquées avant d'utiliser `supabase db push`.

L'application propose la connexion par e-mail/mot de passe et la réinitialisation du mot de passe; la création de comptes se fait par invitation depuis Supabase Auth, pas depuis l'application. Supabase conserve la session sur l'appareil jusqu'à la déconnexion. L'écran de connexion peut mémoriser l'adresse e-mail dans le stockage sécurisé; les mots de passe ne sont jamais enregistrés par l'application et peuvent être proposés par le gestionnaire sécurisé du système via l'autoremplissage. Désactivez les inscriptions publiques dans les réglages Auth du projet. Le trigger `on_auth_user_created` crée alors un profil `assistant` pour les comptes Auth provisionnés par l'administratrice. Créez ou invitez le premier compte depuis Supabase Auth, puis attribuez-lui le rôle administrateur depuis le SQL Editor avec un compte de confiance :

```sql
insert into public.profiles (id, display_name, role)
select id, coalesce(raw_user_meta_data->>'name', email), 'admin'
from auth.users
where email = 'adresse-admin@example.com'
on conflict (id) do update set role = 'admin';
```

Les rôles sont attribués côté base, jamais depuis les métadonnées fournies par le client. Seules les administratrices peuvent modifier les rôles. Les comptes assistants doivent être invités par une administratrice.

Tarifs initiaux insérés : adhésion 20 €, cours à l'unité 5 €, première carte 50 €, renouvellement 45 €, 10 passages (sans date limite). Les valeurs sont modifiables dans `pricing_settings`.

Forfaits (migration `202610040017_subscription_plans.sql`, table `subscription_plans`, prix modifiables dans Réglages) : mensuel valable 30 jours — 1 cours/semaine 20 €, 2 : 35 €, 3 : 48 €, 4 : 57 € ; trimestriel valable 3 mois — 1 cours/semaine 53 €, 2 : 95 €, 3 : 128 €, 4 : 154 €. Le pointage refuse un forfait expiré (selon la date de la séance) ou dont la limite hebdomadaire (semaine civile, fuseau Europe/Paris) est atteinte. Hors-ligne, seule l'expiration est contrôlée localement ; la limite hebdomadaire est vérifiée à la synchronisation.

## Thème

`ZumbaTheme.light` et `ZumbaTheme.dark` déclarent les thèmes Material 3, assortis au fond fourni (magenta, violet, lime et orange). L'image `assets/images/zumba_background.png` est posée sous l'application avec un voile adapté au thème pour préserver la lisibilité. Le choix système/clair/sombre est proposé dans les paramètres et stocké dans le cache local chiffré, par compte.

## Fonctionnalités implémentées

- Connexion et réinitialisation de mot de passe Supabase; accès au menu conditionné au profil et au rôle. Le logo fourni apparaît sur l'écran de connexion, dans l'en-tête et comme icône de l'application.
- Adhérents : recherche, création, modification, archivage/réactivation, cotisation, contact d'urgence, certificat, notes et photo caméra/galerie privée. L'avatar du trombinoscope permet d'ajouter/modifier la photo; la fiche affiche également le cumul des cours restants sur les cartes non épuisées et les jours restants avant l'échéance de la cotisation annuelle et des forfaits datés.
- Équipe pédagogique : l'administratrice renseigne le nom affiché, plusieurs disciplines et une photo caméra/galerie pour chaque compte; les portraits et disciplines apparaissent au-dessus du trombinoscope adhérents.
- Bibliothèque : chorégraphies de danse avec filtres style/intensité/titres oubliés, notes et documents privés; pour le chant, répertoire séparé avec tonalité, tessiture/niveau, pupitre, accompagnement, durée, notes de répétition et document privé. Ne joindre que des paroles/partitions que l'association est autorisée à stocker et partager. L'ouverture de Spotify ne pilote pas la lecture depuis l'application.
- Agenda : séances triées de la plus récente à la plus éloignée, onglet des dates passées pour les séances clôturées ou avec des présences, et pointage rapide qui crée un cours à l'activité et à l'heure courantes puis ouvre directement l'émargement. L'agenda permet aussi la création de cours/stages, la modification des événements programmés, l'affectation de plusieurs instructeurs avec un rôle propre à chacun, les inscriptions extérieures et la check-list matériel. Ouvrir une séance donne accès à un parcours unique de préparation, pointage et clôture; à la clôture, l'équipe confirme les absences, les morceaux réellement joués et les notes de suivi.
- Régie : préparation de playlist, glisser-déposer, durée totale et interface plein écran « morceau suivant ».
- Finances : paiements, reçus numérotés en base, cartes vendues transactionnellement, facture PDF acquittée d'un adhérent sur une période choisie et bilans exportables en PDF et Excel (.xlsx). L'export de facture récapitule les paiements déjà enregistrés; il ne calcule pas les cours non réglés.
- Passages : une administratrice peut ajuster manuellement le solde d'une carte depuis le menu de la fiche adhérent; le motif, l'ancien et le nouveau solde sont historisés en base.
- Suppressions : les administratrices peuvent supprimer définitivement un événement (avec ses inscriptions et présences associées) et des lignes de paiement. Une carte achetée n'est supprimée avec son paiement que si aucun passage n'a été utilisé; sinon l'opération est refusée. Les assistants ne peuvent effectuer aucune de ces suppressions.
- Exports : trombinoscope des adhérents en PDF, feuille d'émargement PDF (liste complète des adhérents actifs avec présence, absence confirmée ou statut à confirmer), bilans de tous les paiements enregistrés en PDF/Excel. Les fichiers peuvent être imprimés, enregistrés ou partagés depuis le dialogue du système.
- Statistiques initiales : compteurs de suivi et morceaux les plus joués sur 30 jours. La date de dernière lecture est mise à jour à la clôture d'une séance.

Les reçus PDF/email/SMS automatiques, recherche d'absences prolongées, jalons de fréquentation, répétition automatique des cours et visualisations avancées ne sont pas encore implémentés. Les tables/buckets existent lorsque prévus par le schéma, mais les fonctions Edge/provider externes ne sont pas configurés.

## Modèles et services fournis

- `Track` décrit une musique, son style, durée, intensité et document pédagogique.
- `SessionPlan` calcule la durée totale et la courbe d'intensité d'une séance.
- `ChoreographyService` lit, filtre, enregistre et supprime les morceaux via Supabase.
- Chaque morceau peut conserver son lien Spotify; la régie ouvre ce morceau (ou le recherche par titre et artiste) dans l'application Spotify/le navigateur.
- `RoomModeService` gère le morceau courant/suivant, l'avance de la régie et le réordonnancement de la playlist.
- `StatisticsService` calcule les morceaux les plus joués pendant les séances terminées sur une période.

La connexion du client Supabase et l'ouverture du cache chiffré sont initialisées au démarrage dans `lib/main.dart`. L'URL du projet et sa clé `publishable` publique sont centralisées dans `lib/core/supabase/supabase_config.dart`. Une clé `publishable` est destinée au client mobile; elle n'est pas une clé secrète et ne remplace pas les politiques RLS. N'utilisez jamais de clé `secret`/`service_role` dans l'application.

Le client et les services sont accessibles via `supabaseClientProvider`, `choreographyServiceProvider` et `statisticsServiceProvider` dans `lib/core/supabase/supabase_providers.dart`. Appliquez d'abord la migration SQL de ce dépôt au projet Supabase. Les accès aux tables nécessitent une session authentifiée et un profil ayant le rôle approprié.

## Démarrage

```sh
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter test
```

Sur Windows, Flutter peut demander d'activer le **Mode développeur Windows** pour créer les liens symboliques requis par les plugins. `flutter run` requiert en outre un appareil ou un émulateur connecté. Pour les téléphones, ouvrez le projet sur iOS/Android après `flutter pub get`; les descriptions d'accès à la caméra/photothèque iOS sont dans `ios/Runner/Info.plist`.

## Notifications de cartes

La migration `202610040018_card_notifications.sql` crée chaque jour dans Supabase des notifications pour les cartes expirant sous 7 jours ou avec un seul cours restant. L'application les reçoit en temps réel via Supabase Realtime lorsque le personnel est connecté et affiche un compteur, un rappel et une liste consultable. Un clic sur le message ouvre la fiche de l'adhérent et marque la notification comme lue; l'icône e-mail prépare un message prérempli vers l'adresse de l'adhérent. Elle dépend du schéma des migrations `202610040014` à `202610040017`; exécutez les migrations manquantes dans l'ordre, puis la migration `202610040018` dans le SQL Editor Supabase. Si le schéma a été initialisé manuellement, vérifiez l'historique avant d'utiliser `supabase db push`, qui pourrait tenter de rejouer les anciennes migrations. Ce sont des notifications dans l'application : aucun service externe n'est utilisé et aucune notification système n'est envoyée quand l'application est fermée.
