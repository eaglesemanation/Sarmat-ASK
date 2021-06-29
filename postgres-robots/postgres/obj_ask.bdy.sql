CREATE OR REPLACE FUNCTION obj_ask."ERROR_TYPE_ROBOT_RP"(
	)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    RETURN 1;
END;
$BODY$;
ALTER FUNCTION obj_ask."ERROR_TYPE_ROBOT_RP"() OWNER TO postgres;
COMMENT ON FUNCTION obj_ask."ERROR_TYPE_ROBOT_RP"()
    IS 'Emulating package variable. Code for all robot-rp related errors.
Тип ошибки: ошибка робот-подсклад';

CREATE OR REPLACE FUNCTION obj_ask."ERROR_TYPE_ROBOT"(
	)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    RETURN 3;
END;
$BODY$;
ALTER FUNCTION obj_ask."ERROR_TYPE_ROBOT"() OWNER TO postgres;
COMMENT ON FUNCTION obj_ask."ERROR_TYPE_ROBOT"()
    IS 'Emulating package variable. Code for all robot related errors.
Тип ошибки: ошибка робота';

CREATE OR REPLACE FUNCTION obj_ask."CELL_TYPE_TRANSIT_1RP"(
	)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    RETURN 18;
END;
$BODY$;
ALTER FUNCTION obj_ask."CELL_TYPE_TRANSIT_1RP"() OWNER TO postgres;
COMMENT ON FUNCTION obj_ask."CELL_TYPE_TRANSIT_1RP"()
    IS 'Emulating package variable. Virtual cell for inner warehouse transfers.
Тип ячейки: транзитные виртуальные для перемещений внутри одного подсклада';

CREATE OR REPLACE FUNCTION obj_ask.get_log_file_name(
    )
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    RETURN 'ask_ora_' || to_char(LOCALTIMESTAMP,'ddmmyy') || '.log';
END;
$BODY$;
ALTER FUNCTION obj_ask.get_log_file_name() OWNER TO postgres;
COMMENT ON FUNCTION obj_ask.get_log_file_name()
    IS 'Generates log name based on date.
получить имя файла текущего лога';


CREATE OR REPLACE PROCEDURE obj_ask.log(
    txt_ text)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    filename TEXT;
BEGIN
    filename := get_log_file_name();
    PERFORM pg_catalog.pg_file_write(
        filename,
        to_char(LOCALTIMESTAMP,'HH24:MI:SS.MS') || ' ' || txt_ || E'\n',
        true
    );
END;
$BODY$;
COMMENT ON PROCEDURE obj_ask.log(text)
    IS 'Adds timestamped entry into log
запись строки в журнал';

CREATE OR REPLACE PROCEDURE obj_ask.global_error_log(
    error_type_ bigint,
    repository_part_id_ bigint,
    robot_id_ bigint,
    errm_ text)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    rp_id__ BIGINT;
    cnt_ BIGINT;
    exception_msg_ TEXT;
BEGIN
    IF (repository_part_id_ IS NULL) AND (robot_id_ IS NOT NULL) THEN
        SELECT repository_part_id INTO rp_id__ FROM robot WHERE id = robot_id_;
    ELSE
        rp_id__ := repository_part_id_;
    END IF;
    SELECT count(*) INTO cnt_ FROM error
    WHERE date_time > CURRENT_DATE - 1 / (24*60)
        AND error_type_id = error_type_
        AND notes = errm_
        AND coalesce(rp_id, 0) = coalesce(rp_id__, 0)
        AND coalesce(robot_id, 0) = coalesce(robot_id_, 0);
    IF cnt_=0 THEN
        INSERT INTO error (date_time,error_type_id,rp_id,robot_id,notes)
            VALUES (sysdate,error_type_,rp_id__,robot_id_,errm_);
    END IF;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS exception_msg_ = MESSAGE_TEXT;
    CALL log('Ошибка формирования записи global_error_log:' || exception_msg_);
END;
$BODY$;
COMMENT ON PROCEDURE obj_ask.global_error_log(bigint, bigint, bigint, text)
    IS 'добавить лог о глобальной ошибке';

-- vim: ft=pgsql
