#!/bin/bash
set -e

for script in /docker-entrypoint-initdb.d/scripts/*.plpgsql; do
    psql -v ON_ERROR_STOP=1 -d "$POSTGRES_DB" -U "$POSTGRES_USER" -f "$script"
done
