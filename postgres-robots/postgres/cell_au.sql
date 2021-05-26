CREATE OR REPLACE FUNCTION cell_au()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    cnt INT;
    tmp RECORD;
BEGIN
    FOR tmp IN (SELECT * FROM tmp_check_cell WHERE action=1) LOOP
        DELETE FROM tmp_check_cell WHERE cell_id = tmp.cell_id;
        SELECT count(distinct(repository_part_id)) INTO cnt
            FROM cell WHERE emp_id=tmp.par;
        IF cnt > 1 THEN
            RAISE EXCEPTION 'Для одного сотрудника возможны ячейки лишь на одном складе!'
                USING errcode = -20123;
        END IF;
    END LOOP;
END;
$BODY$;

ALTER FUNCTION cell_au() OWNER TO postgres;

COMMENT ON FUNCTION cell_au() IS 'Throws exception if more than one cell for one employee';

DROP TRIGGER IF EXISTS cell_au ON cell;

CREATE TRIGGER cell_au
    AFTER UPDATE
    ON cell
    FOR EACH ROW
    EXECUTE FUNCTION cell_au();

-- vim: ft=pgsql
