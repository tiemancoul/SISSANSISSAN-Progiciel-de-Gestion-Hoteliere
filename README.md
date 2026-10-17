# SISSAN SISSAN | Gestion hôtelière

Application de gestion d'un hôtel : Flutter (Windows, Android, iOS, Web) et Supabase (PostgreSQL).
Le cahier des charges de référence est la version 1.1 (section 18 : décisions de cadrage).

## Contenu

- `supabase/migrations/` : schéma de la base, droits par rôle (RLS) et journal d'audit.
- `supabase/tests/` : tests de sécurité exécutés sur un PostgreSQL local.
- `supabase/demarrage.sql` : création de l'hôtel et du premier super administrateur.
- `app/` : application Flutter.

## État du lot 1 (socle)

Fait : connexion et mot de passe oublié, 11 rôles, attribution des rôles, identité de l'hôtel,
règles de séjour, devises et taux, taxes, catégories, chambres, salles de conférence, équipements,
journal d'audit automatique, clients, réservations (double réservation impossible côté base),
arrivée et départ avec mise à jour de l'état des chambres.

Pas encore fait : téléversement du logo, tarifs saisonniers, association équipements ↔ catégories,
calendrier de disponibilité, blocages de chambres par période, puis factures, paiements et caisse.

## Mise en place de Supabase

1. Dans le projet Supabase, choisir une région Europe (décision D12).
2. Appliquer les migrations : `supabase link --project-ref <ref>` puis `supabase db push`,
   ou coller les fichiers de `supabase/migrations/` dans l'éditeur SQL, dans l'ordre.
3. Créer votre compte dans Authentication > Users, puis exécuter `supabase/demarrage.sql`.
4. Les autres comptes apparaissent dans l'écran Utilisateurs, où un administrateur leur attribue un rôle.

## Lancer l'application

```sh
cd app
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<clé publique>
```

Utiliser uniquement la clé publique (publishable ou anon). La clé `service_role` ne doit jamais
être placée dans l'application ni dans ce dépôt.

## Tests

```sh
./supabase/tests/run.sh      # nécessite PostgreSQL local (createdb, psql)
cd app && flutter analyze && flutter test
```
