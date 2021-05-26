CREATE OR REPLACE FUNCTION robot_au_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
BEGIN
    IF (coalesce(NEW.wait_for_problem_resolve, 0) <> coalesce(OLD.wait_for_problem_resolve, 0)) THEN
        CALL service.log2file('  робот [' || NEW.id || '] - триггер robot_au_e - смена wait_for_problem_resolve с '
                                || OLD.wait_for_problem_resolve || ' на ' || NEW.wait_for_problem_resolve);
    END IF;
    IF (coalesce(NEW.platform_busy, 0) <> coalesce(OLD.platform_busy, 0)) THEN
        CALL service.log2file('  робот [' || NEW.id || '] - триггер robot_au_e - смена platform_busy  с '
                                || OLD.platform_busy || ' на ' || NEW.platform_busy);
    END IF;
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION robot_au_e() OWNER TO postgres;

COMMENT ON FUNCTION robot_au_e() IS 'Log robot changing wait_for_problem_resolve or platform_busy columns';

DROP TRIGGER IF EXISTS robot_au_e ON robot;

CREATE TRIGGER robot_au_e
    AFTER UPDATE
    ON robot
    FOR EACH ROW
    EXECUTE FUNCTION robot_au_e();

-- vim: ft=pgsql
