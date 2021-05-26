CREATE OR REPLACE FUNCTION cell_bi_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
BEGIN
    IF (NEW.id IS null) THEN
        SELECT nextval('SEQ_cell') INTO NEW.id;
    END IF;
END;
$BODY$;

ALTER FUNCTION cell_bi_e() OWNER TO postgres;

COMMENT ON FUNCTION cell_bi_e() IS 'Generate ID for newly added cell sequentially';

DROP TRIGGER IF EXISTS cell_bi_e ON cell;

CREATE TRIGGER cell_bi_e
    BEFORE INSERT
    ON cell
    FOR EACH ROW
    EXECUTE FUNCTION cell_bi_e();

-- vim: ft=pgsql
