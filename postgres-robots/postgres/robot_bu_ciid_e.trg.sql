CREATE OR REPLACE FUNCTION robot_bu_ciid_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    cnt NUMERIC;
    rti RECORD;
BEGIN
    FOR rti IN (SELECT * FROM robot_trigger_ignore WHERE robot_id = NEW.id) LOOP
        RETURN NEW;
    END LOOP;

    IF (coalesce(OLD.command_inner_id, 0) <> coalesce(NEW.command_inner_id, 0))
        AND (coalesce(NEW.command_inner_id, 0) <> 0)
    THEN
        SELECT obj_robot.log(NEW.id, '  триггер robot_bu_ciid_e - назначилась новая команда inner=' || coalesce(NEW.command_inner_id, 0));
        IF (NEW.state <> 1) THEN
            NEW.state:=1;
            SELECT obj_robot.log(NEW.id, '  триггер robot_bu_ciid_e - сменили состояние робота на 1');
        END IF;
        UPDATE command_inner
            SET
                date_time_begin = LOCALTIMESTAMP,
                TRACK_ID_BEGIN = NEW.current_track_id,
                TRACK_NPP_BEGIN = (SELECT npp FROM track WHERE id = NEW.current_track_id),
                CELL_SNAME_BEGIN = (SELECT cell_sname FROM track WHERE id = NEW.current_track_id)
        WHERE id = NEW.command_inner_id;
    END IF;

    IF (coalesce(OLD.command_inner_id, 0) <> coalesce(NEW.command_inner_id, 0))
        AND (coalesce(NEW.command_inner_id, 0) = 0)
    THEN
        SELECT obj_robot.log(NEW.id, '  триггер robot_bu_ciid_e - убрали команду inner=' || coalesce(OLD.command_inner_id, 0));
        NEW.command_inner_assigned_id := 0;
    END IF;
END;
$BODY$;

ALTER FUNCTION robot_bu_ciid_e() OWNER TO postgres;

COMMENT ON FUNCTION robot_bu_ciid_e() IS 'Log changes in robot commands';

DROP TRIGGER IF EXISTS robot_bu_ciid_e ON robot;

CREATE TRIGGER robot_bu_ciid_e
    BEFORE UPDATE OF command_inner_id
    ON robot
    FOR EACH ROW
    EXECUTE FUNCTION robot_bu_ciid_e();
