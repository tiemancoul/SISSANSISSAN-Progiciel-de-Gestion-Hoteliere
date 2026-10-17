#!/bin/sh
# Applique les migrations sur une base PostgreSQL locale jetable puis lance les tests RLS.
# Usage : ./supabase/tests/run.sh  (nécessite psql et un serveur PostgreSQL local)
set -e
cd "$(dirname "$0")/.."
DB=sissan_test
dropdb --if-exists "$DB"; createdb "$DB"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/supabase_stub.sql
for f in migrations/*.sql; do psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f"; done
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/rls_test.sql
dropdb "$DB"
