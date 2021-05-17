CREATE OR REPLACE FUNCTION container_collection_bi_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
BEGIN
    SELECT nextval('SEQ_cont_coll') INTO NEW.id;
    NEW.date_time_begin := LOCALTIMESTAMP;
    INSERT INTO tmp_cc (id, action)
        VALUES (NEW.id, 1);
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION container_collection_bi_e()
    OWNER TO postgres;

COMMENT ON FUNCTION container_collection_bi_e()
    IS 'Generates ID for new container_collection sequentially and sets current time';

DROP TRIGGER IF EXISTS container_collection_bi_e ON container_collection;

CREATE TRIGGER container_collection_bi_e
    BEFORE INSERT
    ON container_collection
    FOR EACH ROW
    EXECUTE FUNCTION container_collection_bi_e();