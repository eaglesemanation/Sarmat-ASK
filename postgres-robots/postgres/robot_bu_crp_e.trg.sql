CREATE OR REPLACE FUNCTION robot_bu_crp_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
BEGIN
    IF (coalesce(OLD.command_rp_id, 0) <> coalesce(NEW.command_rp_id, 0)) THEN
        SELECT service.log2file(
            '  триггер robot_bu_ciaid_e - сменили команду rp='
            || coalesce(OLD.command_rp_id, 0)
            || ' на ' || coalesce(NEW.command_rp_id, 0)
            || ' на робота ' || NEW.id);
    END IF;
END;
$BODY$;

ALTER FUNCTION robot_bu_crp_e() OWNER TO postgres;

COMMENT ON FUNCTION robot_bu_crp_e() IS 'Log changes for robots command_rp_id';

DROP TRIGGER IF EXISTS robot_bu_crp_e ON robot;

CREATE TRIGGER robot_bu_crp_e
    BEFORE UPDATE OF command_rp_id
    ON robot
    FOR EACH ROW
    EXECUTE FUNCTION robot_bu_crp_e();
