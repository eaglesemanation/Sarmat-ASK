CREATE OR REPLACE FUNCTION obj_robot."CMD_LOAD_TYPE_ID"(
    )
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    RETURN 4;
END;
$BODY$;
ALTER FUNCTION obj_robot."CMD_LOAD_TYPE_ID"() OWNER TO postgres;
COMMENT ON FUNCTION obj_robot."CMD_LOAD_TYPE_ID"() IS 'Числовой код команды: LOAD';

CREATE OR REPLACE FUNCTION obj_robot."CMD_UNLOAD_TYPE_ID"(
    )
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    RETURN 5;
END;
$BODY$;
ALTER FUNCTION obj_robot."CMD_UNLOAD_TYPE_ID"() OWNER TO postgres;
COMMENT ON FUNCTION obj_robot."CMD_UNLOAD_TYPE_ID"() IS 'Числовой код команды: UNLOAD';

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
COMMENT ON FUNCTION obj_robot."ROBOT_STATE_REPAIR"() IS 'Состояние робота: В починке';

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
COMMENT ON FUNCTION obj_robot.get_log_file_name(numeric)
    IS 'Generates log name based on robot id and date.
получить имя файла лога';


CREATE OR REPLACE PROCEDURE obj_robot.log(
    robot_id_ numeric,
    txt_ text)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    filename TEXT;
BEGIN
    filename := get_log_file_name(robot_id_);
    PERFORM pg_catalog.pg_file_write(
        filename,
        to_char(LOCALTIMESTAMP,'HH24:MI:SS.MS') || ' ' || txt_ || E'\n',
        true
    );
END;
$BODY$;
COMMENT ON PROCEDURE obj_robot.log(numeric, text)
    IS 'Adds timestamped entry into log for specified robot
процедура ведения журнала';

CREATE OR REPLACE PROCEDURE obj_robot.set_command_inner(
    robot_id_ bigint,
    crp_id_ bigint,
    new_cmd_state_ bigint,
    cmd_inner_type_ bigint,
    dir_ bigint,
    cell_src_sname_ text,
    cell_dest_sname_ text,
    cmd_text_ text,
    container_id_ bigint DEFAULT 0,
    check_point_ bigint DEFAULT NULL::bigint)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    rob_rec__ RECORD;
    ci_rec__ RECORD;
    cc RECORD;
    ciid__ BIGINT;
    cnt__ BIGINT;
    errmm__ TEXT;
    lpfix__ TEXT;
    rp_id__ BIGINT;
    nomr__ BIGINT;
    npp_rd__ BIGINT;
BEGIN
    SELECT * INTO rob_rec__ FROM robot WHERE id = robot_id_;
    rp_id__ := rob_rec__.repository_part_id;
    SELECT num_of_robots INTO nomr__ FROM repository_part WHERE id = rp_id__;
    CALL log(robot_id_, 'set_command_inner: robot_id_=' || robot_id_ ||
                        '; crp_id_=' || crp_id_ ||
                        '; new_cmd_state=' || new_cmd_state_ ||
                        '; cmd_inner_type=' || cmd_inner_type_ ||
                        '; dir=' || dir_ ||
                        '; cell_src_sname_=' || cell_src_sname_ ||
                        '; cell_dest_sname_=' || cell_dest_sname_ ||
                        '; cmd_text=' || cmd_text_);
    SELECT count(*) INTO cnt__ FROM command_inner WHERE robot_id = robot_id_ AND state = 3;
    IF (cnt__ <> 0) THEN
        errmm__ := 'ERROR постановки команды - назначается новая, а есть еще старая ';
        CALL log(robot_id_, errmm__);
        RAISE EXCEPTION '%', errmm__ USING errcode = -20003;
    END IF;
    IF (rob_rec__.state <> 0) THEN
        errmm__ := 'ERROR постановки команды для робота ' || robot_id_ || ' - робот занят!';
        CALL log(robot_id_, errmm__);
        RAISE EXCEPTION '%', errmm__ USING errcode = -20012;
    END IF;
    IF (coalesce(rob_rec__.command_inner_assigned_id, 0) <> 0) THEN
        errmm__ := 'ERROR постановки команды для робота ' || robot_id_ ||
            ' - уже закреплена но не запущена команда ' || rob_rec__.command_inner_assigned_id;
        CALL log(robot_id_, errmm__);
        RAISE EXCEPTION '%', errmm__ USING errcode = -20012;
    END IF;
    IF (cell_src_sname_ IS NULL) AND (cell_dest_sname_ IS NULL) THEN
        errmm__ := 'ERROR постановки команды для робота ' || robot_id_ || ' - пустые и источник и приемник!';
        CALL log(robot_id_, errmm__);
        RAISE EXCEPTION '%', errmm__ USING errcode = -20012;
    END IF;
    rob_rec__.state := 1;
    ci_rec__.command_type_id := cmd_inner_type_;
    ci_rec__.direction := dir_;
    IF (cell_src_sname_ IS NOT NULL) THEN
        SELECT c.id, t.npp, t.id
            INTO ci_rec__.cell_src_id, ci_rec__.npp_src, ci_rec__.track_src_id
            FROM cell c
            INNER JOIN shelving s
                ON c.shelving_id = s.id
            INNER JOIN track t
                ON s.track_id = t.id
            WHERE c.sname = cell_src_sname_
                AND t.repository_part_id = rob_rec__.repository_part_id;
    ELSE
        ci_rec__.cell_src_id := 0;
        ci_rec__.npp_src := 0;
        ci_rec__.track_src_id := 0;
    END IF;
    IF (cell_dest_sname_ IS NOT NULL) THEN
        SELECT c.id, t.npp, t.id
        INTO ci_rec__.cell_dest_id, ci_rec__.npp_dest, ci_rec__.track_dest_id
        FROM cell c
        INNER JOIN shelving s
            ON c.shelving_id = s.id
        INNER JOIN track t
            ON s.track_id = t.id
        WHERE c.sname = cell_dest_sname_
            AND t.repository_part_id = rob_rec__.repository_part_id;
    ELSE
        ci_rec__.cell_dest_id := 0;
        ci_rec__.npp_dest := 0;
        ci_rec__.track_dest_id := 0;
    END IF;
    -- проверка на занятость плафтормы
    IF (cmd_inner_type_ IN (5)) THEN -- unload
        IF (rob_rec__.platform_busy = 0) THEN
            UPDATE robot SET wait_for_problem_resolve = 1 WHERE id = robot_id_;
            errmm__ := '  ERROR for robot=' || robot_id_ || ' rob_rec.platform_busy=0';
            CALL obj_ask.global_error_log(obj_ask.ERROR_TYPE_ROBOT(), rp_id__, robot_id_, errmm__);
            CALL log(robot_id_, errmm__);
            RETURN;
            --raise_application_error (-20012, 'Неовзможно дать команду unload при пустой плафторме');
        END IF;
    ELSIF (cmd_inner_type_ IN (4)) THEN -- load
        IF (rob_rec__.platform_busy = 1) THEN
            UPDATE robot SET wait_for_problem_resolve = 1 WHERE id = robot_id_;
            errmm__ := '  ERROR for robot=' || robot_id_ || ' rob_rec.platform_busy=1';
            CALL obj_ask.global_error_log(obj_ask.ERROR_TYPE_ROBOT(), rp_id__, robot_id_, errmm__);
            CALL log(robot_id_, errmm__);
            RETURN;
        END IF;
    END IF;
    IF (nomr__ > 1) THEN -- проверяем, а заблокирован ли трек до цели в случае > 1-го робота
        IF (cmd_inner_type_ IN (5,6)) THEN
            npp_rd__ := ci_rec__.npp_dest;
        ELSE
            npp_rd__ := ci_rec__.npp_src;
        END IF;
        IF check_point_ IS NOT NULL THEN
            npp_rd__ := check_point_;
        END IF;
        IF (obj_rpart.is_track_locked(robot_id_, npp_rd__, dir_) = 0) THEN
            errmm__ := 'ERROR - Ошибка постановки команды для робота ' || robot_id_
                        || ' - команды ' || cmd_text_
                        || ' - незаблокирован трек до секции ' || npp_rd__ || '!';
            CALL obj_ask.global_error_log(obj_ask.ERROR_TYPE_ROBOT_RP(), rp_id__, robot_id_, errmm__);
            CALL log(robot_id_, errmm__);
            RAISE EXCEPTION '%', errmm__ USING errcode = -20012;
        END IF;
    END IF;
    -- проверка для LOAD/UNLOAD
    IF (service.is_cell_full_check() = 1) THEN
        IF (cmd_inner_type_ = CMD_LOAD_TYPE_ID()) THEN
            FOR cc IN (
                SELECT * FROM cell
                WHERE id = ci_rec__.cell_src_id AND is_full = 0
            ) LOOP
                errmm__ := 'ERROR - Ошибка постановки команды для робота ' || robot_id_
                            || ' - команды ' || cmd_text_
                            || ' - ячейка - источник для LOAD пуста!';
                CALL obj_ask.global_error_log(obj_ask.ERROR_TYPE_ROBOT(), rp_id__, robot_id_, errmm__);
                CALL log(robot_id_, errmm__);
                RAISE EXCEPTION '%', errmm__ USING errcode = -20012;
            END LOOP;
        ELSIF (cmd_inner_type_ = CMD_UNLOAD_TYPE_ID()) THEN
            FOR cc IN (
                SELECT * FROM cell
                WHERE id = ci_rec__.cell_dest_id AND is_full >= max_full_size
            ) LOOP
                errmm__ := 'ERROR - Ошибка постановки команды для робота ' || robot_id_
                            || ' - команды ' || cmd_text_
                            || ' - ячейка - приемник для UNLOAD переполнена!';
                CALL obj_ask.global_error_log(obj_ask.ERROR_TYPE_ROBOT(), rp_id__, robot_id_, errmm__);
                CALL log(robot_id_, errmm__);
                RAISE EXCEPTION '%', errmm__ USING errcode = -20012;
            END LOOP;
        END IF;
    END IF;
    INSERT INTO command_inner (command_type_id, rp_id,
        cell_src_sname, cell_src_id, track_src_id, npp_src,
        cell_dest_sname, cell_dest_id, track_dest_id, npp_dest,
        track_npp_begin,
        state, command_rp_id, robot_id, command_to_run, direction, container_id, check_point)
    VALUES (cmd_inner_type_,rob_rec__.repository_part_id,
        cell_src_sname_, ci_rec__.cell_src_id, ci_rec__.track_src_id, ci_rec__.npp_src,
        cell_dest_sname_, ci_rec__.cell_dest_id, ci_rec__.track_dest_id, ci_rec__.npp_dest,
        rob_rec__.current_track_npp,
        1, crp_id_, robot_id_, cmd_text_, dir_, container_id_, check_point_)
    RETURNING id INTO ciid__;
    UPDATE robot SET command_inner_assigned_id = ciid__ WHERE id = robot_id_;
    CALL log(robot_id_, 'Успешно назначили cmd_inner id=' || ciid__);
END;
$BODY$;
COMMENT ON PROCEDURE obj_robot.set_command_inner(bigint, bigint, bigint, bigint, bigint, text, text, text, bigint, bigint)
IS 'выдаем роботу простую команду типа load/Unload/Move';


-- vim: ft=pgsql
