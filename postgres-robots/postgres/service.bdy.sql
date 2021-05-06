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
