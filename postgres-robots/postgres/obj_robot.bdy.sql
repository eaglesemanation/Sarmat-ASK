CREATE OR REPLACE FUNCTION obj_robot."ROBOT_STATE_REPAIR"(
    )
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    RETURN 6;
END;
$BODY$;
ALTER FUNCTION obj_robot."ROBOT_STATE_REPAIR"() OWNER TO postgres;

CREATE OR REPLACE FUNCTION obj_robot.get_log_file_name(
    robot_id_ numeric)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    RETURN 'robot_ora_' || robot_id_ || '_'
        || to_char(LOCALTIMESTAMP,'ddmmyy') || '.log';
END;
$BODY$;
ALTER FUNCTION obj_robot.get_log_file_name(numeric) OWNER TO postgres;
COMMENT ON FUNCTION obj_robot.get_log_file_name(numeric) IS 'Generates log name based on robot id and date';


CREATE OR REPLACE PROCEDURE obj_robot.log(
    robot_id_ numeric,
    txt_ text)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    filename TEXT;
BEGIN
    filename := Get_Log_File_Name(robot_id_);
    SELECT pg_catalog.pg_file_write(
        filename,
        to_char(LOCALTIMESTAMP,'HH24:MI:SS.MS') || ' ' || txt_ || E'\n',
        true
    );
END;
$BODY$;
COMMENT ON PROCEDURE obj_robot.log(numeric, text) IS 'Adds timestamped entry into log for specified robot';
