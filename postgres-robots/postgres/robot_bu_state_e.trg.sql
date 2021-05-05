CREATE FUNCTION robot_bu_state_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    cnt NUMERIC;
BEGIN
    IF (coalesce(NEW.state, 0) <> coalesce(OLD.state, 0)) THEN
        SELECT obj_robot.log(NEW.id, '  триггер robot_bu_state_e - сменился state с '
                             || OLD.state || ' на ' || NEW.state || ' у робота ' || NEW.id);
    INSERT INTO log (repository_part_id, action, comments, robot_id, old_value, new_value)
        VALUES(NEW.repository_part_id, 19, '  триггер robot_bu_state_e - сменился state с '
               || OLD.state || ' на ' || NEW.state || ' у робота ' || NEW.id,
               NEW.id, coalesce(OLD.state, 0), coalesce(NEW.state, 0));
    END IF;
END;
$BODY$;

ALTER FUNCTION robot_bu_state_e() OWNER TO postgres;

COMMENT ON FUNCTION robot_bu_state_e() IS 'Logs updates of robot state';

DROP TRIGGER IF EXISTS robot_bu_state_e ON robot;

CREATE TRIGGER robot_bu_state_e
    BEFORE UPDATE OF state
    ON robot
    FOR EACH ROW
    EXECUTE FUNCTION robot_bu_state_e();
