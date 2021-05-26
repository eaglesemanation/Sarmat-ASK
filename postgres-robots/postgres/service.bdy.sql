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


CREATE OR REPLACE FUNCTION service.ml_get_rus_eng_val(
    in_rus text,
    in_eng text)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    rr RECORD;
BEGIN
    FOR rr IN (SELECT language FROM repository) LOOP
        IF (coalesce(rr.language, 0) = 0) THEN
            RETURN in_rus;
        ELSE
            RETURN in_eng;
        END IF;
    END LOOP;
END;
$BODY$;
ALTER FUNCTION service.ml_get_rus_eng_val(text, text) OWNER TO postgres;
COMMENT ON FUNCTION service.ml_get_rus_eng_val(text, text)
    IS 'Multilanguage (internationalization) - returns string depending on language set in repository';


CREATE OR REPLACE FUNCTION service.is_cell_full_check(
    )
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    rr RECORD;
BEGIN
    FOR rr IN (SELECT ignore_full_cell_check FROM repository) LOOP
        IF (coalesce(rr.ignore_full_cell_check, 0) = 1) THEN
            RETURN 0;
        ELSE
            RETURN 1;
        END IF;
    END LOOP;
END;
$BODY$;
ALTER FUNCTION service.is_cell_full_check() OWNER TO postgres;


CREATE OR REPLACE FUNCTION service.is_cell_near_edge(
    cid_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    cc RECORD;
    rp RECORD;
BEGIN
    FOR cc IN (SELECT * FROM cell WHERE id = cid_) LOOP
        FOR rp IN (
            SELECT repository_type, num_of_robots, max_npp, spacing_of_robots
            FROM repository_part WHERE id = cc.repository_part_id
        ) LOOP
            IF (rp.num_of_robots <> 2) OR (rp.repository_type <> 0) THEN
                RETURN 0;
            ELSE
                IF (cc.track_npp <= 2 * rp.spacing_of_robots) THEN
                    RETURN 1;
                ELSEIF (cc.track_npp >= rp.max_npp - 2 * rp.spacing_of_robots) THEN
                    RETURN 2;
                END IF;
            END IF;
        END LOOP;
    END LOOP;
    RETURN 0;
END;
$BODY$;
ALTER FUNCTION service.is_cell_near_edge(bigint) OWNER TO postgres;
COMMENT ON FUNCTION service.is_cell_near_edge(bigint)
    IS 'If cell near beginning of line - returns 1, near end - returns 2, otherwise returns 0';


CREATE OR REPLACE FUNCTION service.cell_acc_only_1_robot(
    src_ bigint,
    dst_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    cs RECORD;
    cd RECORD;
    tua RECORD;
    rr RECORD;
BEGIN
    FOR cs IN (SELECT * FROM cell WHERE id = src_) LOOP
        FOR cd IN (SELECT * FROM cell WHERE id = dst_) LOOP
            FOR tua IN (
                SELECT r.* FROM robot r
                    WHERE r.repository_part_id = cs.repository_part_id
                    AND coalesce(work_npp_from, -1) >= 0
                    AND coalesce(work_npp_to, -1) >= 0
                    AND cs.track_npp NOT BETWEEN coalesce(work_npp_from, -1)
                    AND coalesce(work_npp_to, -1)
            ) LOOP
                FOR rr IN (
                    SELECT * FROM robot r
                        WHERE r.repository_part_id = cd.repository_part_id
                        AND r.id <> tua.id
                        AND coalesce(work_npp_from, -1) >= 0
                        AND coalesce(work_npp_to, -1) >= 0
                        AND cd.track_npp NOT BETWEEN coalesce(work_npp_from, -1) AND coalesce(work_npp_to, -1)
                ) LOOP
                    RETURN 1;
                END LOOP;
            END LOOP;
        END LOOP;
    END LOOP;
    RETURN 0;
END;
$BODY$;
ALTER FUNCTION service.cell_acc_only_1_robot(bigint, bigint) OWNER TO postgres;


CREATE OR REPLACE FUNCTION service.is_cell_over_locked(
    cid bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    cnt BIGINT;
    crec RECORD;
BEGIN
    SELECT count(*) INTO cnt FROM cell_cmd_lock WHERE cell_id = cid;
    IF (cnt = 0) THEN
        RETURN 0;
    ELSE
        SELECT * INTO crec FROM cell WHERE id = cid;
        IF (cnt >= crec.max_full_size) THEN
            RETURN 1;
        ELSE
            RETURN 0;
        END IF;
    END IF;
END;
$BODY$;
ALTER FUNCTION service.is_cell_over_locked(bigint)
    OWNER TO postgres;
COMMENT ON FUNCTION service.is_cell_over_locked(bigint) IS 'Check if amount of locks on cell is over max';


CREATE OR REPLACE PROCEDURE service.cell_lock_by_cmd(
    cid bigint,
    cmd_id_ bigint)
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
    INSERT INTO cell_cmd_lock(cell_id, cmd_id) VALUES (cid, cmd_id_);
END;
$BODY$;
