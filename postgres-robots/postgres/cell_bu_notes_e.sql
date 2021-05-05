CREATE OR REPLACE FUNCTION cell_bu_notes_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    cnt INT;
BEGIN
    IF coalesce(NEW.notes, '-') <> coalesce(OLD.notes,'-') THEN

        SELECT count(*) INTO cnt FROM command_inner
            WHERE NEW.id IN (cell_src_id, cell_dest_id) AND state NOT IN (2,5);
        IF (cnt > 0) THEN
            RAISE EXCEPTION 'Нельзя менять компьютер ячейки - есть еще неотработанные команды (command_inner)!'
                USING errcode = -20012;
        END IF;

        SELECT count(*) INTO cnt FROM command_rp
            WHERE NEW.id IN (cell_src_id, cell_dest_id) AND state NOT IN (2,5);
        IF (cnt > 0) THEN
            RAISE EXCEPTION 'Нельзя менять компьютер ячейки - есть еще неотработанные команды (command_rp)!'
                USING errcode = -20012;
        END IF;

        SELECT count(*) INTO cnt FROM command
            WHERE NEW.id IN (cell_src_id, cell_dest_id) AND state NOT IN (2,5);
        IF (cnt > 0) THEN
            RAISE EXCEPTION 'Нельзя менять компьютер ячейки - есть еще неотработанные команды (command)!'
                USING errcode = -20012;
        END IF;

        SELECT count(*) INTO cnt FROM command_gas
            WHERE NEW.sname = cell_name AND NEW.repository_part_id = rp_id AND state NOT IN (2,5);
        IF (cnt > 0) THEN
            RAISE EXCEPTION 'Нельзя менять компьютер ячейки - есть еще неотработанные команды (command_gas)!'
                USING errcode = -20012;
        END IF;

        SELECT count(*) INTO cnt FROM command_order
            WHERE NEW.sname = cell_name AND NEW.repository_part_id = rp_id AND state NOT IN (2,5);
        IF (cnt > 0) THEN
            RAISE EXCEPTION 'Нельзя менять компьютер ячейки - есть еще неотработанные команды (command_order)!'
                USING errcode = -20012;
        END IF;

    END IF;
END;
$BODY$;

ALTER FUNCTION cell_bu_notes_e() OWNER TO postgres;

COMMENT ON FUNCTION cell_bu_notes_e() IS 'Throws exception before updating if commands are still executing';

DROP TRIGGER IF EXISTS cell_bu_notes_e ON cell;

CREATE TRIGGER cell_bu_notes_e
    BEFORE UPDATE OF notes
    ON cell
    FOR EACH ROW
    EXECUTE FUNCTION cell_bu_notes_e();
