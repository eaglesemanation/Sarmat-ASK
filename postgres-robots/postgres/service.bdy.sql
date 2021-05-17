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


CREATE OR REPLACE PROCEDURE service."command_bu_cis_e.finish_command"(
	INOUT new record)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    cg RECORD;
    cnt BIGINT;
BEGIN
    PERFORM service.log2file('  триггер command_bu_cis_e - procedure finish_command');
    NEW.date_time_end := LOCALTIMESTAMP;
    NEW.state := 5;
    IF (coalesce(NEW.command_gas_id, 0) <> 0) THEN
        -- container.accept
        FOR cg IN (
            SELECT * FROM command_gas
                WHERE id = NEW.command_gas_id
                AND command_type_id IN (11, 18, 14)
        ) LOOP
            UPDATE command_gas
                SET state = 5, container_cell_name = NEW.cell_dest_sname, container_rp_id = NEW.rp_dest_id
                WHERE id = NEW.command_gas_id;
        END LOOP;
        -- good.out
        FOR cg IN (
            SELECT * FROM command_gas
                WHERE id = NEW.command_gas_id
                AND command_type_id = 12
        ) LOOP
            PERFORM service.log2file('  триггер command_bu_cis_e - cg_type=12 :new.command_gas_id=' || NEW.command_gas_id || ' :new.container_id=' || NEW.container_id || ' :new.cell_dest_sname' || NEW.cell_dest_sname);
            UPDATE command_gas
                SET state = 1
                WHERE id = NEW.command_gas_id AND state < 1;
            IF (NEW.is_intermediate = 0) THEN
                PERFORM service.log2file('  триггер command_bu_cis_e - перед доб command_gas_out_container ');
                INSERT INTO command_gas_out_container(
                    cmd_gas_id, container_id, container_barcode, good_desc_id, quantity, cell_name, gd_party_id
                ) SELECT
                    NEW.command_gas_id, NEW.container_id, barcode, good_desc_id, quantity, NEW.cell_dest_sname, ccn.gdp_id
                    FROM container cn
                    INNER JOIN container_content ccn
                        ON ccn.container_id = cn.id
                    WHERE cn.id = NEW.container_id
                    AND cg.good_desc_id = ccn.good_desc_id
                    AND coalesce(cg.gd_party_id, 0) = coalesce(ccn.gdp_id, 0);
                GET DIAGNOSTICS cnt = ROW_COUNT;
                PERFORM service.log2file('  триггер command_bu_cis_e - после доб command_gas_out_container = ' || cnt);
                INSERT INTO tmp_cmd(id, action) VALUES (NEW.id, 3);
            END IF;
        END LOOP;
    END IF;
END;
$BODY$;
COMMENT ON PROCEDURE service."command_bu_cis_e.finish_command"(record) IS 'Migrated inline procedure for command_bu_cis_e trigger';
