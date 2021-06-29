CREATE OR REPLACE FUNCTION command_rp_ad_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
BEGIN
	DELETE FROM command_inner WHERE command_rp_id = OLD.id;
	UPDATE robot SET command_rp_id=null WHERE command_rp_id = OLD.id;
end;
$BODY$;

ALTER FUNCTION command_rp_ad_e() OWNER TO postgres;

COMMENT ON FUNCTION command_rp_ad_e()
    IS 'Removes command_rp references on deletion';

DROP TRIGGER IF EXISTS command_rp_ad_e ON command_rp;

CREATE TRIGGER command_rp_ad_e
    AFTER DELETE
    ON command_rp
    FOR EACH ROW
    EXECUTE FUNCTION command_rp_ad_e();

-- vim: ft=pgsql
