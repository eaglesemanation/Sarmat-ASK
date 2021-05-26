CREATE OR REPLACE FUNCTION obj_rpart.get_log_file_name(
    rp_id_ numeric)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    RETURN 'rp_ora_' || rp_id_ || '_' || to_char(LOCALTIMESTAMP, 'DDMMYY') || '.log';
END;
$BODY$;
ALTER FUNCTION obj_rpart.get_log_file_name(numeric) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.get_log_file_name(numeric) IS 'Generates log filename based on sub warehouse id';


CREATE OR REPLACE PROCEDURE obj_rpart.log(
    rp_id_ numeric,
    txt_ text)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    filename TEXT;
BEGIN
    filename := Get_Log_File_Name(rp_id_);
    PERFORM pg_catalog.pg_file_write(
        filename,
        to_char(LOCALTIMESTAMP, 'HH24:MI:SS.MS') || ' ' || txt_ || E'\n',
        true
    );
END;
$BODY$;
COMMENT ON PROCEDURE obj_rpart.log(numeric, text) IS 'Logs timestamped entry into file specific to current sub warehouse';


CREATE OR REPLACE PROCEDURE obj_rpart.get_next_npp(
    rp_type numeric,
    max_npp numeric,
    cur_npp numeric,
    npp_to numeric,
    dir numeric,
    INOUT next_npp numeric,
    INOUT is_loop_end numeric)
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
    is_loop_end := 0;
    IF (cur_npp = npp_to) THEN
        is_loop_end := 1;
    END IF;
    IF (dir = 1) THEN -- CLOCKWISE
        IF (cur_npp < max_npp) THEN
            next_npp:= cur_npp+1;
        ELSEIF (cur_npp = max_npp) THEN -- Reached edge
            IF (rp_type = 0) THEN -- Line
                next_npp := cur_npp;
                is_loop_end := 1;
            ELSE -- Loop
                next_npp := 0;
            END IF;
        --ELSE
            --if emu_log_level>=1 then emu_log('  gnp: Error cur_npp='||cur_npp); end if;
        END IF;
    ELSE -- COUNTERCLOCKWISE
        IF (cur_npp > 0) THEN
            next_npp := cur_npp - 1;
        ELSEIF (cur_npp = 0) THEN -- Reached edge
            IF (rp_type = 0) THEN -- Line
                next_npp := cur_npp;
                is_loop_end := 1;
            ELSE
                next_npp:=max_npp;
            END IF;
        --ELSE
            --if emu_log_level>=1 then emu_log('  gnp: Error cur_npp='||cur_npp); end if;
        END IF;
    END IF;
END;
$BODY$;
COMMENT ON PROCEDURE obj_rpart.get_next_npp(numeric, numeric, numeric, numeric, numeric, numeric, numeric) IS 'Get next track number in set direction';


CREATE OR REPLACE FUNCTION obj_rpart.add_track_npp(
    rp_id_ numeric,
    npp_from_ numeric,
    npp_num_ numeric,
    dir_ numeric)
    RETURNS numeric
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    k_ NUMERIC;
    inc_ NUMERIC;
    rp RECORD;
BEGIN
    FOR rp IN (
        SELECT num_of_robots, spacing_of_robots, repository_type, max_npp
             FROM repository_part WHERE id = rp_id_
    ) LOOP
        k_ := npp_from_;
        inc_ := npp_num_;
        -- TODO: Isn't that trivially solvable with modulus?
        LOOP
            IF (dir_ = 1) THEN -- CLOCKWISE
                IF (k_ = rp.max_npp) THEN
                    IF (rp.repository_type = 0) THEN -- Line, edge reached
                        RETURN rp.max_npp;
                    ELSE -- Closed loop, looping over
                        k_:=0;
                        inc_:=inc_-1;
                    END IF;
                ELSE
                    k_:=k_+1;
                    inc_:=inc_-1;
                END IF;
            ELSE -- COUNTERCLOCKWISE
                IF (k_ = 0) THEN
                    IF (rp.repository_type = 0) THEN -- Line, edge reached
                        RETURN 0;
                    ELSE -- Closed loop, looping over
                        k_ := rp.max_npp;
                        inc_ := inc_-1;
                    END IF;
                ELSE
                    k_ := k_-1;
                    inc_ := inc_-1;
                END IF;
            END IF;
            EXIT WHEN inc_ = 0;
        END LOOP;
    END LOOP;
    RETURN k_;
END;
$BODY$;
ALTER FUNCTION obj_rpart.add_track_npp(numeric, numeric, numeric, numeric) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.add_track_npp(numeric, numeric, numeric, numeric) IS 'Adds section to track';


CREATE OR REPLACE PROCEDURE obj_rpart.add_check_point(
    rp_id_ numeric,
    sorb_ numeric,
    robot_id_ numeric,
    dir_ numeric,
    track_npp_ numeric)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    tr_ NUMERIC;
    ci RECORD;
BEGIN
    FOR ci IN (
        SELECT * FROM command_inner
        WHERE robot_id=robot_id_
        AND STATE IN (0,1,3,4)
        AND coalesce(check_point, -1) >= 0
    ) LOOP
        SELECT add_track_npp(rp_id_, tr_npp_ ,sorb_, get_another_direction(dir_))
            INTO tr_;
        INSERT INTO command_inner_checkpoint(command_inner_id,npp)
            VALUES(ci.id, tr_);
    END LOOP;
END;
$BODY$;
COMMENT ON PROCEDURE obj_rpart.add_check_point(numeric, numeric, numeric, numeric, numeric) IS 'Adds checkpoint for robot if it''s supported';


CREATE OR REPLACE FUNCTION obj_rpart.get_track_npp_by_id(
    id_ numeric)
    RETURNS numeric
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    npp_ numeric;
BEGIN
    SELECT npp INTO npp_ FROM track WHERE id = id_;
    RETURN npp_;
END;
$BODY$;
ALTER FUNCTION obj_rpart.get_track_npp_by_id(numeric) OWNER TO postgres;


CREATE OR REPLACE PROCEDURE obj_rpart.unlock_track(
    robot_id_ numeric,
    rp_id_ numeric,
    npp_from_ numeric,
    npp_to_ numeric,
    dir_ numeric)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    rrp RECORD;
    ord RECORD;
    errmm TEXT;
    npp1_ NUMERIC;
    npp2_ NUMERIC;
    npp2 NUMERIC;
    tr_npp NUMERIC;
    tr_id NUMERIC;
    tr_locked_by_robot_id NUMERIC;
BEGIN
    FOR rrp IN (
        SELECT rp.id rpid_, spacing_of_robots sorb, max_npp, repository_type rpt, num_of_robots
            FROM repository_part rp
            WHERE rp.id = rp_id_
    ) LOOP
        CALL log(rrp.rpid_, 'unlock_track: пришла npp_from_=' || npp_from_ || '; npp_to_=' || npp_to_ || '; direction=' || dir_ || '; robot.id=' || robot_id_);
        IF (npp_from_ = npp_to_) THEN
            CALL log(rrp.rpid_, '  нет смысла сразу npp_from_=' || npp_from_ || '; npp_to_=' || npp_to_ || '; direction=' || dir_ || '; robot.id=' || robot_id_);
            RETURN;
        END IF;
        -- FIXME: confusing naming
        npp2 := add_track_npp(rrp.rpid_, npp_to_, 1, get_another_direction(dir_));
        npp1_ := add_track_npp(rrp.rpid_, npp_from_, rrp.sorb, get_another_direction(dir_));
        npp2_ := add_track_npp(rrp.rpid_, npp2, rrp.sorb, get_another_direction(dir_));
        IF (rrp.rpt = 0) AND (npp_to_ <= rrp.sorb) AND (dir_ = 1) THEN
            null;
        ELSEIF (rrp.rpt = 0) AND (npp_to_ >= rrp.max_npp - rrp.sorb) AND (dir_ = 0) THEN
            null;
        ELSE
            tr_npp := npp1_;
            LOOP
                SELECT id, locked_by_robot_id
                    INTO tr_id, tr_locked_by_robot_id
                    FROM track
                    WHERE npp = tr_npp AND repository_part_id = rrp.rpid_;
                IF coalesce(tr_locked_by_robot_id, 0) NOT IN (robot_id_, 0) THEN
                    errmm := 'ERROR - Ошибка ошибка разблокировки трека ' || tr_npp || '! locked by ' || coalesce(tr_locked_by_robot_id,0);
                    CALL log(rrp.rpid_, errmm);
                    RAISE EXCEPTION '%', errmm USING errcode = -20012;
                END IF;
                UPDATE track SET locked_by_robot_id = 0 WHERE id = tr_id;
                -- Fulfil orders and delete them
                FOR ord IN (
                    SELECT * FROM track_order
                        WHERE tr_npp = npp_from
                        AND robot_id <> robot_id_
                        AND repository_part_id = rrp.rpid_
                        ORDER BY id
                ) LOOP
                    CALL log(rrp.rpid_,'  есть заявка =' || ord.id || ' - освобождаем');
                    UPDATE track SET locked_by_robot_id = ord.robot_id WHERE id = tr_id;
                    CALL add_check_point(ord.repository_part_id, rrp.sorb, ord.robot_id, ord.direction, tr_npp);
                    IF ord.npp_from = ord.npp_to THEN -- Order is fulfilled
                        DELETE FROM track_order WHERE id = ord.id;
                        CALL log(rrp.rpid_,'  уже все выбрано по заявке - удаляем');
                    ELSE -- Still fulfilling
                        IF ord.npp_from = tr_npp THEN
                            CALL log(rrp.rpid_,'  уменьшаем заявку трек ' || tr_npp);
                            npp1_ := add_track_npp(rrp.rpid_, tr_npp, 1, ord.direction);
                            UPDATE track_order SET npp_from=npp1_ WHERE id = ord.id;
                        END IF;
                    END IF;
                END LOOP;
                CALL get_next_npp(rrp.rpt, rrp.max_npp, tr_npp, npp2_, dir_, tr_npp, is_loop_exit);
                EXIT WHEN is_loop_exit = 1;
            END LOOP;
        END IF;
    END LOOP;
END;
$BODY$;
COMMENT ON PROCEDURE obj_rpart.unlock_track(numeric, numeric, numeric, numeric, numeric) IS 'Unlocks track by fulfilling track orders';


CREATE OR REPLACE FUNCTION obj_rpart.is_track_between(
    goal_npp numeric,
    npp_from numeric,
    npp_to numeric,
    dir numeric,
    rp_id_ numeric)
    RETURNS numeric
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    rp_rec_max_npp NUMERIC;
    rp_rec_min_npp NUMERIC;
BEGIN
    SELECT min(npp), max(npp) INTO rp_rec_min_npp, rp_rec_max_npp
        FROM track WHERE repository_part_id = rp_id_;
    IF (dir = 1) THEN -- CLOCKWISE
        FOR i IN npp_from..rp_rec_max_npp LOOP
            IF (i = goal_npp) THEN
                RETURN 1;
            END IF;
            IF (i = npp_to) THEN
                RETURN 0;
            END IF;
        END LOOP;
        -- Looping over
        FOR i IN rp_rec_min_npp..npp_to LOOP
            IF (i = goal_npp) THEN
                RETURN 1;
            END IF;
            IF (i = npp_to) THEN
                RETURN 0;
            END IF;
        END LOOP;
    ELSE -- COUNTERCLOCKWISE
        FOR i IN REVERSE rp_rec_min_npp..npp_from LOOP
            IF (i = goal_npp) THEN
                RETURN 1;
            END IF;
            IF (i = npp_to) THEN
                RETURN 0;
            END IF;
        END LOOP;
        -- Looping over
        FOR i IN REVERSE npp_to..rp_rec_max_npp LOOP
            IF (i = goal_npp) THEN
                RETURN 1;
            END IF;
            IF (i = npp_to) THEN
                RETURN 0;
            END IF;
        END LOOP;
    END IF;
    RETURN 0;
END;
$BODY$;
ALTER FUNCTION obj_rpart.is_track_between(numeric, numeric, numeric, numeric, numeric) OWNER TO postgres;


CREATE OR REPLACE FUNCTION obj_rpart.get_cell_id_by_name(
    rp_id_ bigint,
    sname_ text)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    res BIGINT;
BEGIN
    SELECT id INTO res
    FROM cell
    WHERE sname = sname_ AND shelving_id IN (
        SELECT id FROM shelving WHERE track_id IN (
            SELECT id FROM track WHERE repository_part_id = rp_id_
        )
    );
    RETURN res;
END;
$BODY$;
ALTER FUNCTION obj_rpart.get_cell_id_by_name(bigint, text) OWNER TO postgres;


CREATE OR REPLACE FUNCTION obj_rpart.get_track_id_by_cell_and_rp(
    rp_id_ bigint,
    sname_ text)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    res BIGINT;
BEGIN
    SELECT t.id INTO res
    FROM cell c
    INNER JOIN shelving s
        ON c.shelving_id = s.id
    INNER JOIN track t
        ON s.track_id = t.id
    WHERE c.sname = sname_ AND t.repository_part_id = rp_id_;
    RETURN res;
END;
$BODY$;
ALTER FUNCTION obj_rpart.get_track_id_by_cell_and_rp(bigint, text) OWNER TO postgres;


CREATE OR REPLACE FUNCTION obj_rpart.get_track_npp_by_cell_and_rp(
    rp_id_ bigint,
    sname_ text)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    res BIGINT;
BEGIN
    SELECT t.npp INTO res
    FROM cell c
    INNER JOIN shelving s
        ON c.shelving_id = s.id
    INNER JOIN track t
        ON s.track_id = t.id
    WHERE c.sname = sname_ AND t.repository_part_id = rp_id_;
    RETURN res;
END;
$BODY$;
ALTER FUNCTION obj_rpart.get_track_npp_by_cell_and_rp(bigint, text) OWNER TO postgres;


CREATE OR REPLACE FUNCTION obj_rpart.calc_repair_robots(
    rpid_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    cnt_ BIGINT;
BEGIN
    SELECT count(*) INTO cnt_ FROM robot
        WHERE repository_part_id = rpid_
        AND state = obj_robot.ROBOT_STATE_REPAIR();
    RETURN cnt_;
END;
$BODY$;
ALTER FUNCTION obj_rpart.calc_repair_robots(bigint) OWNER TO postgres;


CREATE OR REPLACE FUNCTION obj_rpart.calc_distance_by_dir(
    rpid_ bigint,
    n1 bigint,
    n2 bigint,
    dir_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    rp RECORD;
    res BIGINT;
    nn BIGINT;
BEGIN
    IF (n1 = n2) THEN
        RETURN 0;
    END IF;
    FOR rp IN (
        SELECT repository_type, max_npp
        FROM repository_part
        WHERE id = rpid_
    ) LOOP
        -- Linear track
        IF (rp.repository_type = 0) THEN
            IF (n2 < n1) AND (dir_ = 1)
                OR (n2 > n1) AND (dir_ = 0)
            THEN
                res := rp.max_npp * 100;
            ELSE
                res := abs(n2 - n1);
            END IF;
        -- Cyclic track
        ELSE
            nn := n1;
            res := 0;
            LOOP
                res := res + 1;
                -- Clockwise
                IF (dir_ = 1) THEN
                    IF (nn = rp.max_npp) THEN
                        nn := 0;
                    ELSE
                        nn := nn+1;
                    END IF;
                -- Counterclockwise
                ELSE
                    IF (nn = 0) THEN
                        nn := rp.max_npp;
                    ELSE
                        nn := nn - 1;
                    END IF;
                END IF;
                EXIT WHEN nn = n2;
            END LOOP;
        END IF;
    END LOOP;
    RETURN res;
end;
$BODY$;
ALTER FUNCTION obj_rpart.calc_distance_by_dir(bigint, bigint, bigint, bigint) OWNER TO postgres;


CREATE OR REPLACE FUNCTION obj_rpart.get_rp_spacing_of_robots(
    rpid_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    rp RECORD;
BEGIN
    FOR rp IN (
        SELECT spacing_of_robots FROM repository_part WHERE id = rpid_
    ) LOOP
        RETURN rp.spacing_of_robots;
    END LOOP;
    RETURN 0;
END;
$BODY$;
ALTER FUNCTION obj_rpart.get_rp_spacing_of_robots(bigint) OWNER TO postgres;


CREATE OR REPLACE FUNCTION obj_rpart.get_rp_num_of_robots(
    rpid_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    rp RECORD;
BEGIN
    FOR rp IN (
        SELECT num_of_robots FROM repository_part WHERE id = rpid_
    ) LOOP
        RETURN rp.num_of_robots;
    END LOOP;
    RETURN 0;
END;
$BODY$;
ALTER FUNCTION obj_rpart.get_rp_num_of_robots(bigint) OWNER TO postgres;


CREATE OR REPLACE FUNCTION obj_rpart.is_track_near_repair_robot(
    rp_id_ bigint,
    npp_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    rr RECORD;
    d1 BIGINT;
    d2 BIGINT;
    md BIGINT;
BEGIN
    FOR rr IN (
        SELECT * FROM robot
        WHERE state = obj_robot.ROBOT_STATE_REPAIR()
        AND repository_part_id = rp_id_
    ) LOOP
        d1 := calc_distance_by_dir(rp_id_, npp_, rr.current_track_npp, 0);
        d2 := calc_distance_by_dir(rp_id_ , npp_, rr.current_track_npp, 1);
        md := get_rp_spacing_of_robots(rp_id_) * (get_rp_num_of_robots(rp_id_) - 1) * 2 +(get_rp_num_of_robots(rp_id_) - 1);
        IF (d1 <= md) OR (d2 <= md) THEN
            RETURN 1;
        END IF;
    END LOOP;
    RETURN 0;
END;
$BODY$;
ALTER FUNCTION obj_rpart.is_track_near_repair_robot(bigint, bigint) OWNER TO postgres;


CREATE OR REPLACE FUNCTION obj_rpart.is_exists_cell_type(
    rp_id_ bigint,
    ct_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    cc RECORD;
BEGIN
    FOR cc IN (
        SELECT * FROM cell
        WHERE repository_part_id = rp_id_
        AND hi_level_type = ct_
        AND is_error = 0
    ) LOOP
        RETURN 1;
    END LOOP;
    RETURN 0;
END;
$BODY$;
ALTER FUNCTION obj_rpart.is_exists_cell_type(bigint, bigint) OWNER TO postgres;


CREATE OR REPLACE FUNCTION obj_rpart.get_transit_1rp_cell(
    rpid_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    ncl RECORD;
BEGIN
    FOR ncl IN (
        SELECT * FROM cell
            WHERE repository_part_id = rpid_
            AND is_full = 0
            AND coalesce(blocked_by_ci_id, 0) = 0
            AND service.is_cell_over_locked(id) = 0
            AND coalesce(is_error, 0) = 0
            AND hi_level_type = obj_ask.CELL_TYPE_TRANSIT_1RP
    ) LOOP
        RETURN ncl.id;
    END LOOP;
    RETURN 0;
END;
$BODY$;
ALTER FUNCTION obj_rpart.get_transit_1rp_cell(bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.get_transit_1rp_cell(bigint)
    IS 'Returns available transit cell inside specified track
получить id свободной транзитной ячейки для передач внутри одного огурца';

-- vim: ft=pgsql
