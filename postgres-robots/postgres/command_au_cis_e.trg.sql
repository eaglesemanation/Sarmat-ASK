CREATE OR REPLACE FUNCTION command_au_cis_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    tc RECORD;
    crec RECORD;
    crp RECORD;
    cl RECORD;
    ct RECORD;
    cnt BIGINT;
    crp_id BIGINT;
    cdn TEXT;
    cgid BIGINT;
    sumq BIGINT;
    sumqr BIGINT;
BEGIN
    -- interwarehouse transfers
    FOR tc IN (SELECT * FROM tmp_cmd WHERE action = 1 ORDER BY id) LOOP
        PERFORM service.log2file(' trigger command_au_cis: Between repository_part transfer begin tmp.id=' || tc.id);
        SELECT * INTO crec FROM command WHERE id = tc.id;
        PERFORM service.log2file(' trigger command_au_cis: crec.id=' || crec.id);
        SELECT count(*) INTO cnt FROM command_rp WHERE command_id = crec.id AND state = 5;
        PERFORM service.log2file(' trigger command_au_cis: cnt='||cnt);
        IF (cnt > 1) THEN
            FOR crp IN (SELECT * FROM command_rp WHERE command_id = crec.id AND state = 5) LOOP
                PERFORM service.log2file('     command_au_cis: crp.id=' || crp.id);
            END LOOP;
        END IF;
        SELECT max(id) INTO crp_id FROM command_rp WHERE command_id = crec.id AND state=5;
        PERFORM service.log2file('     command_au_cis: max crp.id=' || crp_id);
        SELECT cell_dest_sname INTO cdn FROM command_rp WHERE command_id = crec.id AND state = 5 AND id = crp_id;
        INSERT INTO command_rp (
            command_type_id, rp_id, cell_src_sname, cell_dest_sname, priority, state, command_id,
            track_src_id, track_dest_id, npp_src, npp_dest,
            cell_dest_id, cell_src_id, container_id
        ) VALUES (
            3, crec.rp_dest_id, crec.crp_cell, crec.cell_dest_sname, crec.priority, 1, crec.id,
            obj_rpart.get_track_id_by_cell_and_rp(crec.rp_dest_id, crec.crp_cell),
            obj_rpart.get_track_id_by_cell_and_rp(crec.rp_dest_id, crec.cell_dest_sname),
            obj_rpart.get_track_npp_by_cell_and_rp(crec.rp_dest_id, crec.crp_cell),
            obj_rpart.get_track_npp_by_cell_and_rp(crec.rp_dest_id, crec.cell_dest_sname),
            obj_rpart.get_cell_id_by_name(crec.rp_dest_id, crec.cell_dest_sname),
            obj_rpart.get_cell_id_by_name(crec.rp_dest_id, cdn),
            crec.container_id
        );
        DELETE FROM tmp_cmd WHERE id = tc.id AND action = 1;
    END LOOP;

    -- Check if command_gas is fullfiled
    FOR tc IN (SELECT * FROM tmp_cmd WHERE action = 3 ORDER BY id) LOOP
        BEGIN
            SELECT command_gas_id INTO cgid FROM command WHERE id = tc.id;
            SELECT sum(quantity_to_pick) INTO sumq
                FROM command_gas_out_container_plan cp
                INNER JOIN command_gas_out_container c
                    ON cp.cmd_gas_id = c.cmd_gas_id AND cp.container_id=c.container_id
                WHERE c.cmd_gas_id = cgid;
            SELECT quantity INTO sumqr FROM command_gas WHERE id = cgid;
            PERFORM service.log2file(' trigger command_au_cis: правим quantity_out=' || sumq || ' у cg_cmd=' || cgid);
            UPDATE command_gas SET quantity_out = sumq WHERE id = cgid;
            IF (sumq >= sumqr) THEN
                PERFORM service.log2file(' trigger command_au_cis: правим state=5 у cg_cmd=' || cgid);
                UPDATE command_gas SET state = 5 WHERE id = cgid;
            END IF;
        EXCEPTION WHEN others THEN
        END;
        DELETE FROM tmp_cmd WHERE id = tc.id AND action = 3;
    END LOOP;

    -- innerwarehouse transfers
    FOR tc IN (SELECT * FROM tmp_cmd WHERE action = 5 ORDER BY id) LOOP
        PERFORM service.log2file(' trigger command_au_cis: inner repository_part transfer begin tmp.id=' || tc.id);
        SELECT * INTO crec FROM command WHERE id = tc.id;
        PERFORM service.log2file(' trigger command_au_cis: crec.id='||crec.id);
        FOR cl IN (
            SELECT c.*, sh.track_id
            FROM cell c
            INNER JOIN shelving sh
                ON c.shelving_id = sh.id
            WHERE c.id = crec.cell_dest_id
        ) LOOP
            FOR ct IN (
                SELECT c.*, sh.track_id
                FROM cell c
                INNER JOIN shelving sh
                    ON c.shelving_id = sh.id
                WHERE c.sname = crec.crp_cell
                    AND c.repository_part_id = cl.repository_part_id
            ) LOOP
                INSERT INTO command_rp (
                    command_type_id, rp_id, cell_src_sname, cell_dest_sname,
                    priority, state, command_id,
                    track_src_id, track_dest_id, npp_src, npp_dest,
                    cell_src_id, cell_dest_id, container_id
                ) VALUES (
                    3, crec.rp_dest_id, crec.crp_cell, crec.cell_dest_sname,
                    crec.priority, 1, crec.id,
                    ct.track_id, cl.track_id, ct.track_npp, cl.track_npp,
                    ct.id, cl.id, crec.container_id
                );
            END LOOP;
        END LOOP;
        DELETE FROM tmp_cmd WHERE id = tc.id AND action=5;
    END LOOP;
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION command_au_cis_e() OWNER TO postgres;

DROP TRIGGER IF EXISTS command_au_cis_e ON command;

CREATE TRIGGER command_au_cis_e
    AFTER UPDATE OF command_rp_executed
    ON command
    FOR EACH ROW
    EXECUTE FUNCTION command_au_cis_e();
