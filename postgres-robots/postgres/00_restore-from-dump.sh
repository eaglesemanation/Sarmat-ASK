#!/bin/bash
set -e

#pg_restore -d "$POSTGRES_DB" -U "$POSTGRES_USER" -n public "$(dirname $0)/pgree"
psql -v ON_ERROR_STOP=1 -d "$POSTGRES_DB" -U "$POSTGRES_USER" -f "$(dirname $0)/pgree"
