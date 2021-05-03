#!/bin/bash
set -e

pg_restore -d "$POSTGRES_DB" -U "$POSTGRES_USER" -n public "$(dirname $0)/pgree"
