CREATE OR REPLACE PROCEDURE trigger.finish_command(
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
            -- если команда не промежуточная, то выдаем на гора
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
COMMENT ON PROCEDURE trigger.finish_command(record)
    IS 'Migrated inline procedure for command_bu_cis_e trigger
';

-- vim: ft=pgsql
