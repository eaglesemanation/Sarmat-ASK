-- Taken from https://github.com/okbob/plpgsql_check README

SET client_encoding = 'UTF8';

-- check all plpgsql functions (functions or trigger functions with defined triggers)
SELECT
    (pcf).functionid::regprocedure, (pcf).lineno, (pcf).statement,
    (pcf).sqlstate, (pcf).message, (pcf).detail, (pcf).hint
FROM
(
    SELECT
        plpgsql_check_function_tb(pg_proc.oid, COALESCE(pg_trigger.tgrelid, 0)) AS pcf
    FROM pg_proc
    LEFT JOIN pg_trigger
        ON (pg_trigger.tgfoid = pg_proc.oid)
    WHERE
        prolang = (SELECT lang.oid FROM pg_language lang WHERE lang.lanname = 'plpgsql') AND
        pronamespace <> (SELECT nsp.oid FROM pg_namespace nsp WHERE nsp.nspname = 'pg_catalog') AND
        -- ignore unused triggers
        (pg_proc.prorettype <> (SELECT typ.oid FROM pg_type typ WHERE typ.typname = 'trigger') OR
         pg_trigger.tgfoid IS NOT NULL)
    OFFSET 0
) ss
WHERE (pcf).sqlstate <> '00000' -- Ignore warnings
ORDER BY (pcf).functionid::regprocedure::text, (pcf).lineno
