CREATE OR REPLACE FUNCTION command_ad_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
BEGIN
    DELETE FROM command_rp WHERE command_id = OLD.id;
    DELETE FROM cell_cmd_lock WHERE cmd_id = OLD.id;
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION command_ad_e() OWNER TO postgres;

COMMENT ON FUNCTION command_ad_e()
    IS 'Deletes cell lock and movement commands on command deletion';

DROP TRIGGER IF EXISTS command_ad_e ON command;

CREATE TRIGGER command_ad_e
    AFTER DELETE
    ON command
    FOR EACH ROW
    EXECUTE FUNCTION command_ad_e();