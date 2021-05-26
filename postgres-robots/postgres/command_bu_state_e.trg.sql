CREATE OR REPLACE FUNCTION command_bu_state_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    cmdrp RECORD;
    cmdi RECORD;
    rr RECORD;
    is_ci BOOLEAN;
BEGIN
    IF (coalesce(OLD.state, 0) <> coalesce(NEW.state, 0)) THEN
        IF (NEW.state >= 3) THEN
            UPDATE command_gas
                SET state = 1 -- Start execution / начала выполняться
                WHERE id = NEW.command_gas_id and state<1;
        END IF;
        IF (NEW.state = 2) AND (OLD.state <> 2) OR
            (NEW.state = 6) AND (OLD.state <> 6)
        THEN
            FOR cmdrp IN (
                SELECT * FROM command_rp
                    WHERE command_id = NEW.id
            ) LOOP
                FOR cmdi IN (
                    SELECT * FROM command_inner
                        WHERE command_rp_id = cmdrp.id
                        AND state NOT IN (5, 2)
                ) LOOP
                    IF (cmdi.command_type_id <> 4) THEN
                        RAISE EXCEPTION 'It''s possible to cancel only active <Load> command!'
                            USING errcode = -20123;
                    END IF;
                    FOR rr IN (
                        SELECT * FROM robot
                            WHERE coalesce(command_inner_id, 0) = cmdi.id
                    ) LOOP
                        IF (coalesce(rr.wait_for_problem_resolve, 0) = 0) THEN
                            RAISE EXCEPTION 'It''s possible to cancel command only in <wait_for_problem_resolve_state>!'
                                USING errcode = -20123;
                        END IF;
                    END LOOP;
                    UPDATE command_inner SET state = 2
                        WHERE command_rp_id = cmdrp.id
                        AND state NOT IN (5, 2);
                    UPDATE robot SET command_inner_id = null, wait_for_problem_resolve = 0
                        WHERE coalesce(command_inner_id, 0) = cmdi.id;
                    UPDATE robot SET command_inner_assigned_id = 0
                        WHERE coalesce(command_inner_assigned_id, 0) = cmdi.id;
                END LOOP;
                DELETE FROM cell_cmd_lock
                    WHERE cell_id IN (cmdrp.cell_src_id, cmdrp.cell_dest_id);
                UPDATE command_rp SET state = 2 WHERE command_id = NEW.id;
                UPDATE robot SET command_rp_id = null, wait_for_problem_resolve = 0
                    WHERE coalesce(command_rp_id, 0) = cmdrp.id;
            END LOOP;
        END IF;
    END IF;
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION command_bu_state_e() OWNER TO postgres;

DROP TRIGGER IF EXISTS command_bu_state_e ON command;

CREATE TRIGGER command_bu_state_e
    BEFORE UPDATE OF state
    ON command
    FOR EACH ROW
    EXECUTE FUNCTION command_bu_state_e();

-- vim: ft=pgsql
