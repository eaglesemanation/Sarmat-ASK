CREATE OR REPLACE FUNCTION container_ad_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    cnt NUMERIC;
BEGIN
    SELECT count(*) INTO cnt FROM container_content
        WHERE container_id = OLD.id AND coalesce(quantity, 0) <> 0;
    IF (OLD.location <> 0) THEN
        RAISE EXCEPTION 'It''s not allowed to delete container in ASK!'
            USING errcode = -20003;
    END IF;
    IF (cnt <> 0) THEN
        RAISE EXCEPTION 'It''s not allowed to delete container with not epmty content!'
            USING errcode = -20003;
    ELSE
        DELETE FROM container_content WHERE container_id = OLD.id;
    END IF;
    RETURN null;
END;
$BODY$;

ALTER FUNCTION container_ad_e() OWNER TO postgres;

COMMENT ON FUNCTION container_ad_e() IS 'Checks if container is allowed to be deleted';

DROP TRIGGER IF EXISTS container_ad_e ON container;

CREATE TRIGGER container_ad_e
    AFTER DELETE
    ON container
    FOR EACH ROW
    EXECUTE FUNCTION container_ad_e();
