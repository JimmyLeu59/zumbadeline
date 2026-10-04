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

Choix recommandé : **PowerSync + SQLite local**, avec une configuration de synchronisation limitée aux données nécessaires à la salle (membres actifs, fiches de morceaux, séances et morceaux ordonnés). Les paiements et opérations de pointage sont conservés dans la file locale, avec un UUID d'opération généré sur l'appareil; la reprise réseau rejoue les pointages par `check_in_member`. Cette fonction est idempotente et décrémente atomiquement la carte choisie. Les conflits administratifs (tarifs, rôles, suppressions) restent serveur-maître et ne sont pas éditables hors connexion. La configuration PowerSync et ses règles de synchronisation sont à déployer séparément; le mode hors-ligne n'est pas encore activé dans ce squelette.

Les médias restent dans les buckets privés Supabase Storage. En local, conserver une copie/cache et le chemin de l'objet (pas une URL signée expirante) dans la base; envoyer la pièce jointe puis mettre à jour son chemin au retour du réseau. Produire des URL signées à durée limitée pour l'affichage. Limiter les types et tailles MIME, et ne pas rendre publics les certificats médicaux ni les photos.

Les reçus et relances email/SMS doivent être déclenchés par Edge Functions, utilisant des secrets côté serveur et des fournisseurs configurés séparément. Ne jamais mettre de clé `service_role` dans l'application Flutter. Les données de paiement ci-dessous enregistrent le moyen et le montant, pas les données de carte bancaire.

## Schéma Supabase

Appliquer `supabase/migrations/202610040001_initial_schema.sql` avec Supabase CLI ou SQL Editor. Le script crée les tables, index, fonctions de rôle, fonction transactionnelle de pointage, deux buckets privés et les politiques RLS/Storage.

Après création du premier compte Auth, promouvoir son profil admin depuis le SQL Editor avec un compte de confiance :

```sql
insert into public.profiles (id, display_name, role)
select id, coalesce(raw_user_meta_data->>'name', email), 'admin'
from auth.users
where email = 'adresse-admin@example.com'
on conflict (id) do update set role = 'admin';
```

Les futurs comptes doivent avoir une ligne `profiles`, rôle `assistant` par défaut; seules les administratrices peuvent modifier les rôles. Cette promotion initiale est volontairement une opération privilégiée, pas une inscription ouverte dans l'application.

Tarifs initiaux insérés : adhésion 20 €, cours à l'unité 5 €, première carte 50 €, renouvellement 45 €, 10 passages. Les valeurs sont modifiables dans `pricing_settings`.

## Thème

`ZumbaTheme.light` et `ZumbaTheme.dark` déclarent les thèmes Material 3, basés sur magenta, orange, violet et lime. `ZumbaApp` suit actuellement le thème système (`ThemeMode.system`); le réglage utilisateur pourra être connecté aux paramètres.

## Modèles et services fournis

- `Track` décrit une musique, son style, durée, intensité et document pédagogique.
- `SessionPlan` calcule la durée totale et la courbe d'intensité d'une séance.
- `ChoreographyService` lit, filtre, enregistre et supprime les morceaux via Supabase.
- `RoomModeService` gère le morceau courant/suivant, l'avance de la régie et le réordonnancement de la playlist.
- `StatisticsService` calcule les morceaux les plus joués pendant les séances terminées sur une période.

Configuration Supabase (à effectuer avant de créer le client dans l'application) :

```sh
flutter run --dart-define=SUPABASE_URL=https://<project>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

## Démarrage

```sh
flutter pub get
flutter analyze
flutter test
```
