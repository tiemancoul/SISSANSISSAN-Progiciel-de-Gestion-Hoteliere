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
arrivée et départ avec mise à jour de l'état des chambres, calendrier d'occupation sur deux semaines,
blocages de chambres par période (incompatibles avec une réservation confirmée).

## État du lot 2 (finances)

Fait : factures (depuis une réservation ou client de passage), taxes calculées et figées à la validation,
numérotation annuelle sans trou (F2026-00001), paiements multi-devises au taux figé, monnaie rendue,
protection contre les doubles paiements, remboursements réservés à la direction, annulation motivée,
sessions de caisse avec écart à la clôture.

Arrondi : chaque montant est arrondi au nombre de décimales de la devise de la facture (0 pour le XOF),
au demi supérieur.

Pas encore fait : impressions A4 / A5 et reçus, avoirs, téléversement du logo, tarifs saisonniers.

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
