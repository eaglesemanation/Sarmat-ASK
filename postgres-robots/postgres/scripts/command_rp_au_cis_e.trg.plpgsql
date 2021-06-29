CREATE OR REPLACE FUNCTION command_rp_au_cis_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    tc RECORD;
    crec command_rp%ROWTYPE;
BEGIN
    FOR tc IN (SELECT * FROM tmp_cmd_rp ORDER BY id) LOOP
        SELECT * INTO crec FROM command_rp WHERE id = tc.id;
        IF (crec.is_to_free = 0) THEN
            PERFORM service.log2file('  триггер command_rp_au_cis_e - продолжаем завершение command_rp command_rp_executed=' || crec.id);
            UPDATE command SET command_rp_executed = crec.id,
                crp_cell = crec.cell_dest_sname,
                error_code_id = crec.error_code_id
                WHERE id=crec.command_id;
        END IF;
        UPDATE robot SET command_rp_id = 0 WHERE id = crec.robot_id;
        DELETE FROM tmp_cmd_rp WHERE id = tc.id;
    END LOOP;
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION command_rp_au_cis_e() OWNER TO postgres;

DROP TRIGGER IF EXISTS command_rp_au_cis_e ON command_rp;

CREATE TRIGGER command_rp_au_cis_e
    AFTER UPDATE OF command_inner_executed
    ON command_rp
    FOR EACH ROW
    EXECUTE FUNCTION command_rp_au_cis_e();

-- vim: ft=pgsql
