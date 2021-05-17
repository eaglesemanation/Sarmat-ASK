CREATE OR REPLACE FUNCTION robot_bu_wait_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    rit RECORD;
BEGIN
    FOR rit IN (
        SELECT * FROM robot_trigger_ignore
        WHERE robot_id = NEW.id
    ) LOOP
        RETURN NEW;
    END LOOP;
    IF (coalesce(NEW.wait_for_problem_resolve, 0) <> coalesce(OLD.wait_for_problem_resolve, 0)) THEN
        IF (coalesce(NEW.wait_for_problem_resolve, 0) = 1) THEN
            CALL obj_robot.log(NEW.id, 'Установили режим решения проблемы');
            NEW.platform_busy_on_problem_set := NEW.platform_busy;
        ELSE
            CALL obj_robot.log(NEW.id, 'Сняли режим решения проблемы');
            NEW.platform_busy_on_problem_set := null;
        END IF;
    END IF;
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION robot_bu_wait_e() OWNER TO postgres;

COMMENT ON FUNCTION robot_bu_wait_e() IS 'Logs if robot entered/exited state of waiting for error to be resolved ';

DROP TRIGGER IF EXISTS robot_bu_wait_e ON public.robot;

CREATE TRIGGER robot_bu_wait_e
    BEFORE UPDATE OF wait_for_problem_resolve
    ON public.robot
    FOR EACH ROW
    EXECUTE FUNCTION public.robot_bu_wait_e();