#!/bin/sh
# Applique les migrations sur une base PostgreSQL locale jetable puis lance les tests (tests/NN_*_test.sql, dans l'ordre).
# Usage : ./supabase/tests/run.sh  (nécessite psql et un serveur PostgreSQL local)
set -e
cd "$(dirname "$0")/.."
DB=sissan_test
dropdb --if-exists "$DB"; createdb "$DB"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/supabase_stub.sql
for f in migrations/*.sql; do psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f"; done
for f in tests/[0-9]*_test.sql; do psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f"; done
dropdb "$DB"
