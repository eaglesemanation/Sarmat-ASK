CREATE OR REPLACE FUNCTION command_bu_cis_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    cnt BIGINT;
    cell_comm TEXT;
    cl RECORD;
    cd RECORD;
BEGIN
    PERFORM service.log2file('  триггер command_bu_cis_e - зашли ctype=' || NEW.command_type_id);
    -- Successful execution
    IF (coalesce(OLD.command_rp_executed, 0) = 0) AND (coalesce(NEW.command_rp_executed, 0) <> 0) THEN
        -- Movement command
        IF (NEW.command_type_id = 1) THEN
            IF (NEW.rp_src_id = NEW.rp_dest_id) THEN
                SELECT hi_level_type INTO cnt FROM cell
                    WHERE sname = NEW.crp_cell
                    AND repository_part_id = NEW.rp_src_id;
                IF (cnt = obj_ask.CELL_TYPE_TRANSIT_1RP()) THEN
                    -- Inner warehouse transfer
                    INSERT INTO tmp_cmd(id, action) VALUES (NEW.id, 5);
                ELSE
                    PERFORM trigger.finish_command(NEW);
                END IF;
            ELSE -- rp_src_id <> rp_dest_id
                IF (NEW.container_rp_id = NEW.rp_src_id) THEN
                    NEW.container_rp_id := NEW.rp_dest_id;
                    INSERT INTO tmp_cmd(id, action) VALUES (NEW.id, 1);
                ELSE
                    PERFORM trigger.finish_command(NEW);
                END IF;
            END IF;
        ELSIF (NEW.command_type_id = 19) THEN
            IF (NEW.state <> 2) THEN
                PERFORM service.log2file('  триггер command_bu_cis_e - выполнилась команда верификации по складу');
                cnt := 0;
                FOR cl IN (
                    SELECT c.*, sh.track_id
                        FROM robot_cell_verify rcv
                        INNER JOIN cell c
                            ON rcv.cell_id = c.id
                        INNER JOIN shelving sh
                            ON c.shelving_id=sh.id
                        WHERE cmd_id = NEW.id
                        AND rcv.vstate = 1
                        ORDER BY rcv.id
                ) LOOP
                    cnt := 1;
                    INSERT INTO command_rp(
                        command_id, command_type_id, robot_id,
                        rp_id, cell_src_sname, track_src_id, cell_src_id,
                        npp_src, state, priority, direction_1, substate
                    ) VALUES (
                        NEW.id, 20, NEW.robot_id, NEW.rp_src_id, cl.sname,
                        cl.track_id, cl.id, cl.track_npp, 1, -99999999,
                        service.get_ust_cell_dir(NEW.robot_id, cl.track_id), 0
                    );
                    EXIT;
                END LOOP;
                IF (cnt = 0) THEN
                    NEW.state := 5;
                END IF;
            END IF;
        ELSIF (NEW.command_type_id = 23) THEN
            IF (NEW.state <> 2) THEN
                PERFORM service.log2file('  триггер command_bu_cis_e - выполнилась команда тест мех по складу');
                NEW.priority := NEW.priority - 1;
                IF (NEW.priority > 0) THEN
                    FOR cl IN (
                        SELECT c.*, sh.track_id
                            FROM robot_cell_verify rcv
                            INNER JOIN cell c
                                ON rcv.cell_id = c.id
                            INNER JOIN shelving sh
                                ON c.shelving_id = sh.id
                            WHERE cmd_id = NEW.id
                            AND is_full = 1
                            ORDER BY random()
                    ) LOOP
                        FOR cd IN (
                            SELECT c.*, sh.track_id
                            FROM robot_cell_verify rcv
                            INNER JOIN cell c
                                ON rcv.cell_id = c.id
                            INNER JOIN shelving sh
                                ON c.shelving_id = sh.id
                            WHERE cmd_id = NEW.id
                            AND is_full = 0
                            AND cell.id <> cl.id
                            ORDER BY random()
                        ) LOOP
                            INSERT INTO command_rp (
                                command_type_id, rp_id, cell_src_sname, cell_dest_sname,
                                priority, state, command_id, track_src_id , track_dest_id,
                                cell_src_id, cell_dest_id, npp_src, npp_dest, container_id
                            ) VALUES (
                                3, NEW.rp_src_id, cl.sname, cd.sname, 0, 1, NEW.id,
                                (SELECT track_id FROM shelving WHERE id = cl.shelving_id),
                                (SELECT track_id FROM shelving WHERE id = cd.shelving_id),
                                cl.id, cd.id, cl.track_npp,cd.track_npp, cl.container_id
                            );
                            PERFORM service.cell_lock_by_cmd(cl.id, NEW.id);
                            PERFORM service.cell_lock_by_cmd(cd.id, NEW.id);
                            EXIT;
                        END LOOP;
                        EXIT;
                    END LOOP;
                ELSE
                    NEW.state := 5;
                END IF;
            END IF;
        END IF;
    END IF;
    IF (NEW.state <> 5) THEN
        UPDATE command_gas
            SET state = 3
            WHERE id = NEW.command_gas_id
            AND state < 3;
    END IF;
    NEW.command_rp_executed := 0;
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION command_bu_cis_e() OWNER TO postgres;

DROP TRIGGER IF EXISTS command_bu_cis_e ON command;

CREATE TRIGGER command_bu_cis_e
    BEFORE UPDATE OF command_rp_executed
    ON command
    FOR EACH ROW
    EXECUTE FUNCTION command_bu_cis_e();
