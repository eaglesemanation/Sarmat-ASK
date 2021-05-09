CREATE OR REPLACE FUNCTION service.bkp_to_file_active(
    )
    RETURNS boolean
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    RETURN 1;
END;
$BODY$;

ALTER FUNCTION service.bkp_to_file_active() OWNER TO postgres;
COMMENT ON FUNCTION service.bkp_to_file_active()
    IS 'Imitation of variable from Oracle that disables/enables behaviour of bkp_to_file';

CREATE OR REPLACE PROCEDURE service.log2filen(
    filename text,
    txt text)
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
    PERFORM pg_catalog.pg_file_write(
        filename,
        to_char(LOCALTIMESTAMP, 'HH24:MI:SS.MS') || ' ' || txt || E'\n',
        true
    );
END;
$BODY$;

COMMENT ON PROCEDURE service.log2filen(text, text)
    IS 'Add timestamped entry into file';

CREATE OR REPLACE PROCEDURE service.log2file(
    txt text,
    prefix text DEFAULT 'log_'::text)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    filename TEXT;
    append BOOLEAN;
    entry TEXT;
    entryPart Text;
BEGIN
    filename := prefix || to_char(LOCALTIMESTAMP, 'DDMMYY');
    append := true;
    entry := to_char(LOCALTIMESTAMP, 'HH24:MI:SS.MS') || ' ' || txt;
    LOOP
        IF (char_length(entry) > 250) THEN
            entryPart := substring(entry from 1 for 250);
            entry := substring(entry from 251);
        ELSE
            entryPart := entry;
            entry := null;
        END IF;
        PERFORM pg_catalog.pg_file_write(filename, entryPart || E'\n', append);
        EXIT WHEN entry IS null;
    END LOOP;
END;
$BODY$;

COMMENT ON PROCEDURE service.log2file(text, text)
    IS 'Adds timestamped entry into log file separating it into 250 characters lines';

CREATE OR REPLACE PROCEDURE service.bkp_to_file(
    filename text,
    txt text)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    append BOOLEAN;
    entry TEXT;
    entryPart TEXT;
    ns BIGINT;
BEGIN
    IF bkp_to_file_acitve() THEN
        RETURN;
    END IF;
    SELECT coalesce(no_shift, 0) INTO ns FROM repository;
    filename := 'BKP_DIR/' || to_char(LOCALTIMESTAMP, 'DDMMYY') || '_'
        || trim(to_char(ns, '0000')) || '_' || filename;
    append := true;
    entry := to_char(LOCALTIMESTAMP, 'HH24:MI:SS.MS') || ';' || txt;
    LOOP
        IF (char_length(entry) > 250) THEN
            entryPart := substring(entry from 1 for 250);
            entry := substring(entry from 251);
        ELSE
            entryPart := entry;
            entry := null;
        END IF;
        PERFORM pg_catalog.pg_file_write(filename, entryPart || E'\n', append);
        EXIT WHEN entry IS null;
    END LOOP;
END;
$BODY$;

COMMENT ON PROCEDURE service.bkp_to_file(text, text)
    IS 'Adds timestamped entry into backup file separated into 250 char lines';

