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
COMMENT ON FUNCTION obj_rpart.get_log_file_name(numeric)
    IS 'Generates log filename based on sub warehouse id.
получить имя файла лога';


CREATE OR REPLACE PROCEDURE obj_rpart.log(
    rp_id_ numeric,
    txt_ text)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    filename TEXT;
BEGIN
    filename := get_log_file_name(rp_id_);
    PERFORM pg_catalog.pg_file_write(
        filename,
        to_char(LOCALTIMESTAMP, 'HH24:MI:SS.MS') || ' ' || txt_ || E'\n',
        true
    );
END;
$BODY$;
COMMENT ON PROCEDURE obj_rpart.log(numeric, text)
    IS 'Logs timestamped entry into file specific to current sub warehouse.
процедура ведения журнала';


CREATE OR REPLACE FUNCTION obj_rpart.get_cmd_dir_text(
    dir_ bigint)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    IF (dir_ = 1) THEN
        RETURN '';
    ELSE
        RETURN 'CCW';
    END IF;
END;
$BODY$;
ALTER FUNCTION obj_rpart.get_cmd_dir_text(bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.get_cmd_dir_text(bigint)
    IS 'получить по ID направления кусок команды в текстовом виде для отдачи роботу';


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
    -- Clockwise
    IF (dir = 1) THEN -- по часовой
        IF (cur_npp < max_npp) THEN
            next_npp:= cur_npp+1;
        ELSIF (cur_npp = max_npp) THEN -- Reached edge
            -- Line
            IF (rp_type = 0) THEN -- линейный
                next_npp := cur_npp;
                is_loop_end := 1;
            -- Cyclic
            ELSE
                next_npp := 0;
            END IF;
        --ELSE
            --if emu_log_level>=1 then emu_log('  gnp: Error cur_npp='||cur_npp); end if;
        END IF;
    -- Counterclockwise
    ELSE
        IF (cur_npp > 0) THEN
            next_npp := cur_npp - 1;
        ELSIF (cur_npp = 0) THEN -- Reached edge
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
COMMENT ON PROCEDURE obj_rpart.get_next_npp(numeric, numeric, numeric, numeric, numeric, numeric, numeric)
    IS 'Get next track number in set direction.
взять следующий № трека по направлению (и высчитать, не пришди ли уже куда надо)';


CREATE OR REPLACE FUNCTION obj_rpart.add_track_npp(
    rp_id_ bigint,
    npp_from_ bigint,
    npp_num_ bigint,
    dir_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    k_ BIGINT;
    inc_ BIGINT;
    rp RECORD;
BEGIN
    FOR rp IN (
        SELECT num_of_robots, spacing_of_robots, repository_type, max_npp
             FROM repository_part WHERE id = rp_id_
    ) LOOP
        k_ := npp_from_;
        inc_ := npp_num_;
        -- FIXME: Isn't that trivially solvable with modulus?
        LOOP
            -- Clockwise
            IF (dir_ = 1) THEN -- по часовой стрелке
                IF (k_ = rp.max_npp) THEN -- достигли максимума
                    -- Line, edge reached
                    IF (rp.repository_type = 0) THEN -- склад линейный
                        RETURN rp.max_npp;
                    -- Cyclic, looping over
                    ELSE -- склад кольцевой, начинаем сначала
                        k_:=0;
                        inc_:=inc_-1;
                    END IF;
                ELSE
                    k_:=k_+1;
                    inc_:=inc_-1;
                END IF;
            -- Counterclockwise
            ELSE -- против часовой стрелке
                IF (k_ = 0) THEN -- достигли минимума
                    -- Line, edge reached
                    IF (rp.repository_type = 0) THEN -- склад линейный
                        RETURN 0;
                    -- Cyclic, looping over
                    ELSE -- склад кольцевой, начинаем с конца
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
ALTER FUNCTION obj_rpart.add_track_npp(bigint, bigint, bigint, bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.add_track_npp(bigint, bigint, bigint, bigint)
    IS 'Adds section to track.
примитив для добавления к номеру трека столько-то секций';


CREATE OR REPLACE FUNCTION obj_rpart.correct_npp_to_track_order(
    rid_ bigint,
    to_rid_ bigint,
    dir_ bigint,
    npp_to_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    npp_to_ar BIGINT;
    ro_ RECORD;
BEGIN
    FOR ro_ IN (
        SELECT rp.num_of_robots, spacing_of_robots, rp.id rpid
        FROM robot_order ro
        INNER JOIN robot r
            ON ro.robot_id = r.id
        INNER JOIN repository_part rp
            ON r.repository_part_id = rp.id
        WHERE corr_robot_id = to_rid_
        AND dir = dir_
        AND r.id = rid_
    ) LOOP
        IF (ro_.num_of_robots > 0) THEN
            npp_to_ar := add_track_npp(ro_.rpid, npp_to_, ro_.num_of_robots * (ro_.spacing_of_robots * 2 + 1), dir_);
        ELSE
            npp_to_ar := npp_to_;
        END IF;
        RETURN npp_to_ar;
    END LOOP;
    RETURN npp_to_;
END;
$BODY$;
ALTER FUNCTION obj_rpart.correct_npp_to_track_order(bigint, bigint, bigint, bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.correct_npp_to_track_order(bigint, bigint, bigint, bigint)
    IS 'корректируем заявку на блокировку трека по вновь открывшимся обстоятельствам';


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
COMMENT ON PROCEDURE obj_rpart.add_check_point(numeric, numeric, numeric, numeric, numeric)
    IS 'Adds checkpoint for robot if it''s supported
добавить промежуточную точку для робота, если он поддерживает';


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
COMMENT ON FUNCTION obj_rpart.get_track_npp_by_id(numeric)
    IS 'взять ID трека по его номеру на конкретном огурце';


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
                -- освобождаем заявки их удовлетворяя
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
                    -- Order is fulfilled
                    IF ord.npp_from = ord.npp_to THEN -- нет нужды в этой заявке - удаляем ее
                        DELETE FROM track_order WHERE id = ord.id;
                        CALL log(rrp.rpid_,'  уже все выбрано по заявке - удаляем');
                    -- Still fulfilling
                    ELSE -- еще есть нужда в заявке - уменьшаем ее размер
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
COMMENT ON PROCEDURE obj_rpart.unlock_track(numeric, numeric, numeric, numeric, numeric)
    IS 'Unlocks track by fulfilling track orders.
вызывается из триггера при смене текущего трека; нужно передавать rp_id_, чтобы не было мутации';


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
    -- Clockwise
    -- по часовой стрелке
    IF (dir = 1) THEN
        FOR i IN npp_from..rp_rec_max_npp LOOP
            IF (i = goal_npp) THEN
                RETURN 1;
            END IF;
            IF (i = npp_to) THEN
                RETURN 0;
            END IF;
        END LOOP;
        -- Looping over
        -- за конец
        FOR i IN rp_rec_min_npp..npp_to LOOP
            IF (i = goal_npp) THEN
                RETURN 1;
            END IF;
            IF (i = npp_to) THEN
                RETURN 0;
            END IF;
        END LOOP;
    -- Counterclockwise
    -- против часовой стрелке
    ELSE
        FOR i IN REVERSE rp_rec_min_npp..npp_from LOOP
            IF (i = goal_npp) THEN
                RETURN 1;
            END IF;
            IF (i = npp_to) THEN
                RETURN 0;
            END IF;
        END LOOP;
        -- Looping over
        -- за конец
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
COMMENT ON FUNCTION obj_rpart.is_track_between(numeric, numeric, numeric, numeric, numeric)
    IS 'указанный трек между двумя треками по направлению?';


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
COMMENT ON FUNCTION obj_rpart.get_cell_id_by_name(bigint, text)
    IS 'взять ID ячейки по ее имени на конкретном огурце';


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
COMMENT ON FUNCTION obj_rpart.get_track_id_by_cell_and_rp(bigint, text)
    IS 'получить ID трека по огурцу и названию ячейки';


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
COMMENT ON FUNCTION obj_rpart.get_track_npp_by_cell_and_rp(bigint, text)
    IS 'взять № трека по огурцу и названию ячейки';


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
COMMENT ON FUNCTION obj_rpart.calc_repair_robots(bigint)
    IS 'сколько роботов на огурце находится в режиме починки?';


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
        IF (rp.repository_type = 0) THEN -- линейный
            IF (n2 < n1) AND (dir_ = 1)
                OR (n2 > n1) AND (dir_ = 0)
            THEN
                res := rp.max_npp * 100;
            ELSE
                res := abs(n2 - n1);
            END IF;
        -- Cyclic track
        ELSE -- кольцевой
            nn := n1;
            res := 0;
            LOOP
                res := res + 1;
                -- Clockwise
                IF (dir_ = 1) THEN -- по часовой
                    IF (nn = rp.max_npp) THEN
                        nn := 0;
                    ELSE
                        nn := nn+1;
                    END IF;
                -- Counterclockwise
                ELSE -- против
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
COMMENT ON FUNCTION obj_rpart.calc_distance_by_dir(bigint, bigint, bigint, bigint)
    IS 'вычисляет расстояние между двумя треками npp по указанному направлению';


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
COMMENT ON FUNCTION obj_rpart.get_rp_spacing_of_robots(bigint)
    IS 'получить минимальное расстояние между роботами в огурце';


CREATE OR REPLACE FUNCTION obj_rpart.get_track_id_by_robot_and_npp(
    robot_id_ bigint,
    track_no bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    ctid BIGINT;
BEGIN
    SELECT id INTO ctid
        FROM track
        WHERE npp=track_no
        AND repository_part_id = (
            SELECT repository_part_id FROM robot WHERE id = robot_id_
        );
    RETURN ctid;
END;
$BODY$;
ALTER FUNCTION obj_rpart.get_track_id_by_robot_and_npp(bigint, bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.get_track_id_by_robot_and_npp(bigint, bigint)
    IS 'получить ID трека по ID роботу и № трека';


CREATE OR REPLACE FUNCTION obj_rpart.inc_spacing_of_robots(
    npp_ bigint,
    direction bigint,
    spr bigint,
    rp_id_ bigint,
    minnppr bigint default -1,
    maxnppr bigint default -1)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    maxnpp BIGINT;
    minnpp BIGINT;
    rpt BIGINT;
BEGIN
    SELECT repository_type INTO rpt FROM repository_part WHERE id = rp_id_;
    IF (maxnppr <> -1) THEN
        maxnpp := maxnppr;
    ELSE
        SELECT max(npp) INTO maxnpp FROM track WHERE repository_part_id = rp_id_;
    END IF;
    IF (minnppr <> -1) THEN
        minnpp := minnppr;
    ELSE
        SELECT min(npp) INTO minnpp FROM track WHERE repository_part_id = rp_id_;
    END IF;
    IF (direction = 1) THEN -- по часовой стрелке
        IF (npp_ + spr <= maxnpp) THEN
            RETURN npp_ + spr;
        ELSE
            IF (rpt = 1) THEN  -- для кольцевого
                -- например, есть 0 1 2 3 4, мы стоим на 3, нужно увеличить на 2, 3+2-4-1
                RETURN npp_ + spr - maxnpp - 1;
            ELSE -- для линейного при перехлесте
                RETURN maxnpp;
            END IF;
        END IF;
    ELSE -- против часовой стрелке
        IF (npp_ - spr >= minnpp) THEN
            RETURN (npp_ - spr);
        ELSE
            IF (rpt = 1) THEN  -- для кольцевого
                -- например, есть 0 1 2 3 4, мы стоим на 1, нужно уменьшить на 2, 1-2+4+1
                RETURN npp_ - spr + maxnpp + 1;
            ELSE -- для линейного при самом начале
                RETURN minnpp;
            END IF;
        END IF;
    END IF;
END;
$BODY$;
ALTER FUNCTION obj_rpart.inc_spacing_of_robots(bigint, bigint, bigint, bigint, bigint, bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.inc_spacing_of_robots(bigint, bigint, bigint, bigint, bigint, bigint)
    IS 'возвращает номер участка пути увеличенное на spr секций';


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
COMMENT ON FUNCTION obj_rpart.get_rp_num_of_robots(bigint)
    IS 'сколько в огурце роботов?';


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
COMMENT ON FUNCTION obj_rpart.is_track_near_repair_robot(bigint, bigint)
    IS 'находится ли трек в шлейфе поломанного робота?';


CREATE OR REPLACE FUNCTION obj_rpart.get_another_robot_id(
    r_id_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    res BIGINT;
BEGIN
    SELECT id INTO res
        FROM robot
        WHERE id <> r_id_
        AND repository_part_id = (
            SELECT repository_part_id FROM robot WHERE id = r_id_
        );
    RETURN res;
EXCEPTION WHEN OTHERS THEN
    RETURN 0;
END;
$BODY$;
ALTER FUNCTION obj_rpart.get_another_robot_id(bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.get_another_robot_id(bigint)
    IS 'получить id второго робота';


CREATE OR REPLACE FUNCTION obj_rpart.is_track_npp_ban_move_to(
    rid_ bigint,
    npp_ bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    res_ BIGINT;
BEGIN
    SELECT coalesce(ban_move_to, 0) INTO res_ FROM track WHERE repository_part_id = rp_id_ AND npp = npp_;
    RETURN res_;
EXCEPTION WHEN OTHERS THEN
    RETURN 0;
END;
$BODY$;
ALTER FUNCTION obj_rpart.is_track_npp_ban_move_to(bigint, bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.is_track_npp_ban_move_to(bigint, bigint)
    IS 'является ли трек запрещенным для команд Move туда?';


CREATE OR REPLACE FUNCTION obj_rpart.is_track_part_between(
    to_id_ bigint,
    npp_from bigint,
    npp_to bigint,
    dir bigint)
    RETURNS boolean
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    to_ RECORD;
BEGIN
    FOR to_ IN (SELECT * FROM track_order WHERE to_id_ = id) LOOP
        -- ->->
        IF ((to_.direction = 1) AND (dir = 1)) THEN -- заявка по часовой стеклки и часть трека по часовой стрелки
            IF (to_.npp_to < to_.npp_from) THEN -- заявка с перехлестом через 0
                IF (npp_to < npp_from) THEN -- участок с перехлестом через 0
                    RETURN true; -- оба перехлеста
                ELSE -- участок без перехлеста через 0
                    RETURN (npp_to >= to_.Npp_From) -- участок вначале попадает
                        OR (npp_from <= to_.Npp_To); -- участок вконце попадает
                END IF;
            ELSE -- без перехлеста через 0
                IF (npp_to < npp_from) THEN -- с перехлестом через 0
                    RETURN (npp_from <= to_.npp_to) -- участок сначала задевает заявку
                        OR (npp_to >= to_.npp_from); -- участок в конце задевает заявку
                ELSE -- без перехлеста через 0
                    RETURN (npp_to >= to_.npp_from AND npp_from <= to_.npp_from) -- участок вначале попадает
                        OR (npp_from >= to_.npp_from AND npp_to <= to_.npp_to) -- участок целиком попадает
                        OR (npp_from <= to_.npp_to AND npp_to >= to_.npp_to); -- участок справа попадает
                END IF;
            END IF;
        -- <-<-
        ELSIF ((to_.direction = 0) AND (dir = 0)) THEN -- заявка против часовой стрелки и часть трека против часовой стрелки
            IF (to_.npp_to < to_.npp_from) THEN -- заявка без перехлеста через 0
                IF (npp_to < npp_from) THEN -- участок без перехлеста через 0
                    RETURN (npp_from >= to_.npp_to AND npp_to <= to_.npp_to) -- участок слева попадает
                        OR (npp_from <= to_.npp_from AND npp_to >= to_.npp_to) -- участок целиком попадает
                        OR (npp_from >= to_.npp_from AND npp_to <= to_.npp_from); -- участок справа попадает
                ELSE -- с перехлестом участок через 0
                    RETURN (npp_from >= to_.npp_to) -- участок сначала задевает заявку
                        OR (npp_to <= to_.npp_from); -- участок в конце задевает заявку
                END IF;
            ELSE -- заявка с перехлестом через 0
                IF (npp_to < npp_from) THEN -- участок без перехлеста через 0
                    RETURN (npp_to <= to_.npp_from) -- участок вначале попадает
                        OR (npp_from >= to_.npp_to); -- участок вконце попадает
                ELSE -- с перехлестом участок через 0
                    RETURN true;
                END IF;
            END IF;
        -- -><-
        ELSIF ((to_.direction = 1) AND (dir = 0)) THEN -- заявка по часовой стрелки , а часть трека против часовой стрелки
            IF (to_.npp_to < to_.npp_from) THEN -- заявка с перехлестом через 0
                IF (npp_to < npp_from) THEN -- участок без перехлеста через 0
                    RETURN (npp_from >= to_.npp_from) -- участок слева попадает
                        OR (npp_to <= to_.npp_to); -- участок справа попадает
                ELSE -- участок с перехлестом через 0
                    RETURN true;
                END IF;
            ELSE -- заявка без перехлеста через 0
                IF (npp_to < npp_from) THEN -- участок без перехлеста через 0
                    RETURN (npp_from >= to_.npp_from AND npp_to <= to_.npp_to); -- участок попадает
                ELSE -- участок с перехлестом через 0
                    RETURN (npp_from >= to_.npp_from) -- участок слева попадает
                        OR (npp_to <= to_.npp_to); -- участок справа попадает
                END IF;
            END IF;
        -- <-->
        ELSIF ((to_.direction = 0) AND (dir = 1)) THEN -- заявка против часовой стрелки , а часть трека по часовой стрелки
            IF (to_.npp_to < to_.npp_from) THEN -- заявка без перехлеста через 0
                IF (npp_to < npp_from) THEN -- участок c перехлестом через 0
                    RETURN (npp_to >= to_.npp_to) -- участок слева попадает
                        OR (npp_from <= to_.npp_from); -- участок справа попадает
                ELSE -- участок без перехлеста через 0
                    RETURN (npp_from <= to_.npp_from AND npp_to >= to_.npp_from) -- участок справа попадает
                        OR (npp_from >= to_.npp_to AND npp_to <= to_.npp_from) -- участок целиком попадает
                        OR (npp_to >= to_.npp_to AND npp_from <= to_.npp_to); -- участок справа попадает
                END IF;
            ELSE -- заявка c перехлестом через 0
                IF (npp_to < npp_from) THEN -- участок c перехлестом через 0
                    RETURN true;
                ELSE -- участок без перехлеста через 0
                    RETURN (npp_from <= to_.npp_from) -- участок слева попадает
                        OR (npp_to >= to_.npp_to); -- участок справа попадает
                END IF;
            END IF;
        END IF;
    END LOOP;
    RETURN false; -- сюда дойти не должно вроде как
END;
$BODY$;
ALTER FUNCTION obj_rpart.is_track_part_between(bigint, bigint, bigint, bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.is_track_part_between(bigint, bigint, bigint, bigint)
    IS 'является ли указанная заявка на блокировку между указанными треками по заданному направлению?';


CREATE OR REPLACE FUNCTION obj_rpart.is_track_locked(
    robot_id_ in bigint,
    npp_d bigint,
    dir bigint,
    maybe_locked_ bigint default 0,
    check_ask_1_robot bigint default 0)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    r RECORD;
    rp RECORD;
    cnpp BIGINT;
    ll BIGINT;
    dnppsorb BIGINT;
    is_dest_npp_reached BOOLEAN;
BEGIN
    is_dest_npp_reached := false;
    FOR r IN (SELECT * FROM robot WHERE id = robot_id_) LOOP
        PERFORM log(r.repository_part_id, ' is_track_locked robot_id_=' || robot_id_ || ' npp_d=' || npp_d || ' dir=' || dir);
        FOR rp IN (
            SELECT repository_type, id, max_npp, spacing_of_robots sorb, num_of_robots
                FROM repository_part rp
                WHERE id=r.repository_part_id
        ) LOOP
            IF (check_ask_1_robot = 0) AND (rp.num_of_robots = 1) THEN -- один робот - всегда все свободно
                RETURN 1;
            END IF;
            cnpp := r.current_track_npp;
            RAISE NOTICE '  cnpp=%', cnpp;
            SELECT locked_by_robot_id INTO ll FROM track WHERE repository_part_id = rp.id AND npp = cnpp;
            IF (cnpp = npp_d) AND (ll = robot_id_) /*or maybe_locked_=1 and ll=0)*/ THEN
                RETURN 1; -- там же и стоим
            END IF;
            -- считаем максимум сколько нужно хапануть
            dnppsorb := add_track_npp(rp.id, npp_d,rp.sorb, dir);
            IF (is_track_npp_ban_move_to(rp.id, npp_d) = 1) THEN
                dnppsorb := add_track_npp(rp.id, dnppsorb, 1, dir);
            END IF;
            LOOP
                IF cnpp=npp_d THEN
                    is_dest_npp_reached:=true;
                END IF;
                EXIT WHEN cnpp=dnppsorb AND is_dest_npp_reached;
                IF (dir = 1) THEN -- по часовой
                    IF (rp.repository_type = 1) THEN -- для кольцевого склада
                        IF (cnpp = rp.max_npp) THEN
                            cnpp := 0;
                        ELSE
                            cnpp := cnpp + 1;
                        END IF;
                    ELSE -- для линейного
                        IF (cnpp < rp.max_npp) THEN
                            cnpp := cnpp + 1;
                        ELSE
                            EXIT; -- выход из цикла
                        END IF;
                    END IF;
                ELSE -- против
                    IF (rp.repository_type = 1) THEN -- для кольцевого склада
                        IF (cnpp = 0) THEN
                            cnpp := rp.max_npp;
                        ELSE
                            cnpp := cnpp - 1;
                        END IF;
                    ELSE -- для линейного
                        IF (cnpp > 0) THEN
                            cnpp := cnpp - 1;
                        ELSE
                            EXIT; -- выход из цикла
                        END IF;
                    END IF;
                END IF;
                SELECT locked_by_robot_id INTO ll FROM track WHERE repository_part_id = rp.id AND npp = cnpp;
                IF (ll <> r.id) AND (maybe_locked_ = 0) THEN -- ошибка
                    RETURN 0; -- путь не готов - ОШИБКА!!!
                ELSIF (ll NOT IN (r.id, 0)) AND (maybe_locked_ = 1) THEN
                    return 0; -- путь не готов - ОШИБКА!!!
                END IF;
            END LOOP;
        END LOOP;
    END LOOP;
    RETURN 1; -- все проверено, мин нет
END;
$BODY$;
ALTER FUNCTION obj_rpart.is_track_locked(bigint, bigint, bigint, bigint, bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.is_track_locked(bigint, bigint, bigint, bigint, bigint)
    IS 'интеллектуальная функция определения - заблокирован ли трек? (учитывает шлейф робота)';


CREATE OR REPLACE FUNCTION obj_rpart.form_track_order(
    rid_ bigint,
    npp_from_ bigint,
    npp_to_ bigint,
    dir_ bigint,
    robot_stop_id_ bigint)
    RETURNS boolean
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    r RECORD;
    tt RECORD;
    cnt BIGINT;
    nor_ BIGINT;
BEGIN
    FOR r IN (SELECT * FROM robot WHERE id = rid_) LOOP
        PERFORM log(r.repository_part_id, 'Пришла заявка на трек от робота ' || rid_
            || ' NPP_FROM=' || NPP_FROM_
            || ' NPP_TO=' || NPP_TO_
            || ' dir=' || dir_
            || ' robot_stop_id_=' || robot_stop_id_);
        -- первым делом проверяем, а нет ли уже заявки от этого же робота
        FOR tt IN (SELECT * FROM track_order WHERE repository_part_id = r.repository_part_id AND rid_ = robot_id) LOOP
            PERFORM log(r.repository_part_id, 'ERROR - попытка заявки, когда уже есть заявка от робота ' || rid_
                || ' NPP_FROM=' || tt.NPP_FROM
                || ' NPP_TO=' || tt.NPP_TO
                || ' DIRECTION=' || tt.DIRECTION
                || ' robot_stop_id=' || tt.robot_stop_id);
            RETURN true;
        END LOOP;
        SELECT count(*) INTO cnt FROM track_order WHERE repository_part_id = r.repository_part_id;
        SELECT num_of_robots INTO nor_ FROM repository_part WHERE id = r.repository_part_id;
        IF (cnt >= nor_ - 1) THEN
            PERFORM log(r.repository_part_id, 'ERROR - слишком много заявок по подскладу, отбой!');
            RETURN false;
        END IF;
        FOR tt IN (SELECT * FROM track_order WHERE repository_part_id = r.repository_part_id) LOOP
            IF (robot_stop_id_ = tt.robot_stop_id) THEN
                PERFORM log(r.repository_part_id, 'ERROR - попытка второй заявки на одного мешающего робота');
                RETURN false;
            END IF;
            IF (robot_stop_id_ = tt.robot_id) THEN
                PERFORM log(r.repository_part_id, 'ERROR - попытка ранее инициировавшего заявку робота выставить мешающим');
                RETURN false;
            END IF;
            IF (tt.direction <> dir_) AND is_track_part_between(tt.id, npp_from_, npp_to_, dir_) THEN
                PERFORM log(r.repository_part_id, 'ERROR - попытка добавить встречную мешающую заявку');
                RETURN false;
            END IF;
        END LOOP;
        INSERT INTO track_order(robot_id, repository_part_id, npp_from, npp_to, direction, robot_stop_id)
            VALUES (rid_, r.repository_part_id, npp_from_, npp_to_, dir_, robot_stop_id_);
    END LOOP;
    RETURN true;
END;
$BODY$;
ALTER FUNCTION obj_rpart.form_track_order(bigint, bigint, bigint, bigint, bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.form_track_order(bigint, bigint, bigint, bigint, bigint)
    IS 'неинтеллектуальный запрос формирования заявки на блокировку трека';


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
COMMENT ON FUNCTION obj_rpart.is_exists_cell_type(bigint, bigint)
    IS 'Checks if there are any cells of specified type that have no erorrs.
есть ли неошибочные ячейки указанного подтипа на складе?';


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


CREATE OR REPLACE PROCEDURE obj_rpart.track_lock_prim(
    rpid_ bigint,
    rid_ bigint)
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
    UPDATE track
        SET locked_by_robot_id = rid_
        WHERE repository_part_id = rpid_
        AND npp IN (
            SELECT npp FROM tmp_track_lock WHERE rp_id = rpid_
        );
    DELETE FROM tmp_track_lock WHERE rp_id = rpid_;
END;
$BODY$;
COMMENT ON PROCEDURE obj_rpart.track_lock_prim(bigint, bigint)
    IS 'функция примитивной блокировки трека';


CREATE OR REPLACE FUNCTION obj_rpart.try_track_lock(
    rid_ bigint,
    npp_to_ bigint,
    dir_ bigint,
    ignore_buf_track_order boolean,
    barrier_robot_id out bigint,
    result out bigint)
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    rp RECORD;
    to_ RECORD;
    tr RECORD;
    tor RECORD;
    tt RECORD;
    npp_from_sorb__ BIGINT;
    npp_to_sorb__ BIGINT;
    npp_cur__ BIGINT;
    npp_to_was_locked__ BOOLEAN;
    npp_old__ BIGINT;
    npp_tmp__ BIGINT;
    distance__ BIGINT;
    cnt_ BIGINT;
    npp_to_ar BIGINT;
    ft BOOLEAN;
BEGIN
    -- Assume there are no barriers
    barrier_robot_id := 0; -- типа ничего не мешает
    FOR rp IN (
        SELECT rp.id, num_of_robots, spacing_of_robots, repository_type, max_npp, r.current_track_npp
            FROM robot r
            INNER JOIN repository_part rp
                ON r.repository_part_id = rp.id
            WHERE r.id = rid_
    ) LOOP
        DELETE FROM tmp_track_lock WHERE rp_id = rp.id;
        PERFORM log(rp.id, 'Try_Track_Lock robot=' || rid_
            || ' робот находится c_npp=' || rp.current_track_npp
            || ' npp_to_=' || npp_to_
            || ' dir_=' || dir_);
        IF (is_track_locked(rid_, npp_to_, dir_, 0, 1) = 1) THEN
            PERFORM log(rp.id,'  уже заблокировано, нет смысла блокировать');
            result := npp_to_;
            RETURN;
        END IF;
        IF (rp.current_track_npp = npp_to_) THEN
            PERFORM log(rp.id,'  находится робот там же, куда нужно дойти. Бред какой-то');
            result := npp_to_;
            RETURN;
        END IF;
        npp_from_sorb__ := add_track_npp(rp.id, rp.current_track_npp, rp.spacing_of_robots + 1, dir_);
        npp_to_sorb__ := add_track_npp(rp.id, npp_to_, rp.spacing_of_robots, dir_);
        IF (is_track_npp_ban_move_to(rp.id, npp_to_) = 1) THEN
            PERFORM log(rp.id, '  попали на BAN_MOVE_TO, увеличиваем npp_to_sorb__ на 1 в сторону ' || dir_);
            npp_to_sorb__ := add_track_npp(rp.id, npp_to_sorb__, 1, dir_);
        END IF;
        npp_cur__ := npp_from_sorb__;
        -- для блокировки around или на 1 секцию
        distance__ := calc_distance_by_dir(rp.id, rp.current_track_npp, npp_to_, dir_);
        npp_to_was_locked__ := (npp_to_ = rp.current_track_npp) OR (distance__ <= rp.spacing_of_robots);
        npp_old__ := -1;
        PERFORM log(rp.id, '  npp_from_sorb__=' || npp_from_sorb__ || ' npp_to_sorb__=' || npp_to_sorb__);
        -- а теперь проверяем заявки, если нужно
        IF (NOT ignore_buf_track_order) THEN
            cnt_ := 0;
            FOR to_ IN (SELECT * FROM track_order WHERE repository_part_id = rp.id ORDER BY id) LOOP
                EXIT WHEN (cnt_ = 0) AND (to_.robot_id = rid_); -- если самая свежая заявка от текущего робота, то ему все пофиг
                IF (to_.robot_id <> rid_) AND (to_.robot_stop_id <> rid_) THEN
                    npp_to_ar := correct_npp_to_track_order(rid_, to_.robot_id, dir_, npp_to_sorb__);
                    IF (is_track_locked(rid_, npp_to_, dir_, 0) = 0)
                        AND (
                            is_track_part_between(rp.id, npp_from_sorb__, npp_to_ar, dir_)
                            OR is_track_part_between(rp.id, npp_from_sorb__, npp_to_, dir_) -- это нужно чтобы избежать перехлеста при блокировки с 44 по 42 по часовой
                        )
                    THEN
                        PERFORM log(rp.id, '  отмена запроса на блокировку трека, т.к. требуемый участок уже в заявке по цепочке');
                        result := npp_old__;
                        RETURN;
                    END IF;
                END IF;
                cnt_ := cnt_ + 1;
            END LOOP;
        END IF;
        LOOP
            --Log(rp.id,'  loop npp_cur__='||npp_cur__);
            FOR tr IN (SELECT * FROM track WHERE repository_part_id = rp.id AND npp = npp_cur__) LOOP
                IF (tr.locked_by_robot_id = 0) THEN
                    --update track set locked_by_robot_id=rid_ where id=tr.id;
                    INSERT INTO tmp_track_lock(npp, rp_id) VALUES (npp_cur__, rp.id);
                    -- освобождаем заявку с трека
                    FOR tor IN (
                        SELECT * FROM track_order
                        WHERE robot_id = rid_
                        AND npp_from = npp_cur__
                        AND npp_from <> npp_to
                    ) LOOP
                        npp_tmp__ := add_track_npp(rp.id, npp_cur__, 1, get_another_direction(dir_));
                        PERFORM log(rp.id,'  освободили кусок заявки track_order ' || tor.id
                            || ' робота ' ||tor.robot_id
                            || ' на трек с ' ||tor.npp_from
                            || ' на трек с  ' ||npp_tmp__);
                        UPDATE track_order SET npp_from = npp_tmp__ WHERE robot_id = rid_;
                    END LOOP;
                    -- удаляем всю заявку
                    FOR tor IN (
                        SELECT * FROM track_order
                        WHERE robot_id = rid_
                        AND npp_from = npp_cur__
                        AND npp_from = npp_to
                    ) LOOP
                        PERFORM log(rp.id, '  удалили заявку track_order ' || tor.id
                            || ' робота ' || tor.robot_id
                            || ' на трек с ' || tor.npp_from
                            || ' по ' || tor.npp_to
                            || ' робот мешал ' || tor.robot_stop_id);
                        DELETE FROM track_order WHERE robot_id = rid_;
                    END LOOP;
                ELSIF (tr.locked_by_robot_id <> rid_) THEN
                    barrier_robot_id := tr.locked_by_robot_id;
                    IF (npp_old__ < 0) THEN
                        PERFORM log(rp.id, '  ERROR - заблокировано другим роботом');
                        ft := form_track_order(rid_, npp_from_sorb__, npp_to_sorb__, dir_, tr.locked_by_robot_id);
                        IF (NOT ft) AND (NOT ignore_buf_track_order) THEN
                            result := -1;
                            RETURN;
                        END IF;
                        PERFORM track_lock_prim(rp.id, rid_);
                        result := npp_old__;
                        RETURN;
                    ELSE
                        ft := form_track_order(rid_, tr.npp, npp_to_sorb__, dir_, tr.locked_by_robot_id);
                        IF (NOT ft) AND (NOT ignore_buf_track_order) THEN
                            result := -1;
                            RETURN;
                        END IF;
                        PERFORM track_lock_prim(rp.id, rid_);
                        npp_old__ := add_track_npp(rp.id, npp_old__, rp.spacing_of_robots, get_another_direction(dir_));
                        result := npp_old__;
                        RETURN;
                    END IF;
                END IF;
            END LOOP;
            IF (NOT npp_to_was_locked__) AND (npp_cur__ = npp_to_) THEN
                npp_to_was_locked__ := true;
            END IF;
            npp_old__ := npp_cur__;
            EXIT WHEN npp_cur__ = npp_to_sorb__ AND npp_to_was_locked__;
            npp_cur__ := add_track_npp(rp.id, npp_cur__, 1, dir_);
            PERFORM log(rp.id, '  tr.npp_cur__=' || npp_cur__);
        END LOOP;
        PERFORM track_lock_prim(rp.id, rid_);
        -- удаляем заявки на трек, если были, раз сюда дошли, то
        FOR tt IN (SELECT * FROM track_order WHERE robot_id = rid_) LOOP
            DELETE FROM track_order WHERE robot_id = rid_;
            PERFORM log(rp.id, '  удалили заявку track_order ' || tt.id
                || ' робота ' || tt.robot_id
                || ' на трек с ' || tt.npp_from
                || ' по ' || tt.npp_to
                || ' робот мешал ' || tt.robot_stop_id);
        END LOOP;
        result := npp_to_;
        RETURN;
    END LOOP;
END;
$BODY$;
ALTER FUNCTION obj_rpart.try_track_lock(bigint, bigint, bigint, boolean, out bigint, out bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.try_track_lock(bigint, bigint, bigint, boolean, out bigint, out bigint)
    IS 'возврщает track_npp, до которого удалось дойти
если не может сдвинуться с места, шлет -1
если не удалось дойти, то шлет заявку на участок пути
здесь задаем № трека без учета ореола (интеллектуальное)';


CREATE OR REPLACE FUNCTION obj_rpart.is_poss_to_lock(
    robot_id_ bigint,
    track_npp_dest bigint,
    direction_ bigint,
    crp_id_ bigint default 0)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    r1 RECORD;
    r2 RECORD;
    track_id_dest BIGINT;
    rp_id_ BIGINT;
    sorb BIGINT;
    max_npp_ BIGINT;
    rpt BIGINT;
    nr BIGINT;
    anroid BIGINT;
    is_in_dest BIGINT;
    cur_track_id BIGINT;
    npp1 BIGINT;
    npp1r BIGINT;
    npp2 BIGINT;
    npp2r BIGINT;
    track_id_dest_pl_sor BIGINT;
    track_npp_dest_pl_sor BIGINT;
    tr_npp BIGINT;
    tr_id BIGINT;
    is_loop_exit BIGINT;
    tr_locked_by_robot_id BIGINT;
    ret_track_id BIGINT;
    npp_ret BIGINT;
BEGIN
    -- зачитываем нужные значения, инициализируем данные, пишем логи
    SELECT * INTO r1 FROM robot WHERE id = robot_id_;
    SELECT t.id, rp.id, spacing_of_robots, max_npp, repository_type, num_of_robots
        INTO track_id_dest, rp_id_, sorb, max_npp_, rpt, nr
        FROM track t, repository_part rp
        WHERE t.npp=track_npp_dest and repository_part_id=rp.id and rp.id=r1.repository_part_id;
    IF (/*rpt=0*/ nr = 1) THEN
        -- для склада с одним роботом
        IF (r1.current_track_npp = track_npp_dest) THEN
            RETURN -1; -- уже тама
        ELSE
            RETURN track_id_dest;
        END IF;
    END IF;
    anroid := get_another_robot_id(robot_id_);
    SELECT * INTO r2 FROM robot WHERE id = anroid;
    is_in_dest := 0;
    cur_track_id := r1.current_track_id;
    IF (track_id_dest = cur_track_id) THEN
        RETURN 1;
    END IF;

    npp1 := r1.current_track_npp;
    npp1r := inc_spacing_of_robots(npp1, direction_, sorb, rp_id_); -- убрали +1
    npp2 := track_npp_dest;
    npp2r := inc_spacing_of_robots(npp2, direction_, sorb, rp_id_);

    track_id_dest_pl_sor := get_track_id_by_robot_and_npp(robot_id_, npp2r);
    track_npp_dest_pl_sor := npp2r;

    tr_npp := npp1r;
    LOOP
        tr_id := get_track_id_by_robot_and_npp(robot_id_, tr_npp);
        SELECT locked_by_robot_id INTO tr_locked_by_robot_id FROM track WHERE id=tr_id;
        IF (coalesce(tr_locked_by_robot_id, 0) = 0) then
            --update track set locked_by_robot_id=r1.id where id=tr_id;
            ret_track_id := tr_id;
            npp_ret := tr_npp;
        -- заблокировано кем то иным
        ELSIF (coalesce(tr_locked_by_robot_id, 0) <> r1.id) THEN
            RETURN 0;
        ELSE -- этим же роботом и заблокировано
            ret_track_id := tr_id;
            npp_ret := tr_npp;
        END IF;
        CALL get_next_npp(rpt, max_npp_, tr_npp, npp2r, direction_, tr_npp, is_loop_exit);
        EXIT WHEN is_loop_exit=1;
    END LOOP;

    IF (ret_track_id = track_id_dest_pl_sor) THEN
        -- добрались до конечного трека с учетом расстояния между роботами
        RETURN 1;
    ELSE -- не дошли до конечного трека
        RETURN 0;
    END IF;
END;
$BODY$;
ALTER FUNCTION obj_rpart.is_poss_to_lock(bigint, bigint, bigint, bigint) OWNER TO postgres;
COMMENT ON FUNCTION obj_rpart.is_poss_to_lock(bigint, bigint, bigint, bigint)
    IS 'определяет, возможно ли заблокировать путь';

-- vim: ft=pgsql
