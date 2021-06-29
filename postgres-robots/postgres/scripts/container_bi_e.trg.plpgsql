CREATE OR REPLACE FUNCTION container_bi_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
BEGIN
    IF (NEW.id IS null) THEN
        SELECT nextval('SEQ_cnt') INTO NEW.id;
    END IF;
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION container_bi_e()
    OWNER TO postgres;

COMMENT ON FUNCTION container_bi_e()
    IS 'Generate ID for newly added container sequentially';

DROP TRIGGER IF EXISTS container_bi_e ON container;

CREATE TRIGGER container_bi_e
    BEFORE INSERT
    ON container
    FOR EACH ROW
    EXECUTE FUNCTION container_bi_e();

-- vim: ft=pgsql
