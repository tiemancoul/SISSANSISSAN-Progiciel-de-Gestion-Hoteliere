# SISSANSISSAN | Progiciel de Gestion Hôtelière

Logiciel SaaS de gestion hôtelière multi-hôtels.

- `backend/` : API REST Laravel 13 (PHP 8.3), authentification par jeton (Sanctum).
- `frontend/` : application Flutter Web installable en PWA.

## Lancer en local

```sh
# API
cd backend
composer install
cp .env.example .env && php artisan key:generate
php artisan migrate --seed   # SQLite par défaut ; PostgreSQL via DB_CONNECTION=pgsql dans .env
php artisan serve            # http://localhost:8000

# Application
cd frontend
flutter run -d chrome --dart-define=API_URL=http://localhost:8000/api
```

Comptes de démonstration (mot de passe `password`, à changer avant toute utilisation réelle) :

| Rôle | E-mail |
|---|---|
| Super administrateur | admin@sissansissan.com |
| Administrateur hôtelier | gerant@demo.ml |
| Réceptionniste | reception@demo.ml |

## Tests

```sh
cd backend && php artisan test
cd frontend && flutter test
```

## Règles de sécurité déjà en place

- Chaque utilisateur appartient à un hôtel ; seul le super administrateur n'en a pas.
- Un administrateur hôtelier ne voit et ne modifie que le personnel de son hôtel (vérifié côté serveur et couvert par des tests).
- La suspension d'un hôtel bloque les connexions sans supprimer aucune donnée.
- Aucun super administrateur ne peut être créé par l'API.
