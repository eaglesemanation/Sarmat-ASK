CREATE OR REPLACE FUNCTION robot_bu_ctrack_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    rit RECORD;
    rp RECORD;
    st RECORD;
    npp_old NUMERIC;
    npp_new NUMERIC;
    npp_to NUMERIC;
    npp_to_id NUMERIC;
    cirec command_inner%ROWTYPE;
    errm TEXT;
BEGIN
    CALL obj_robot.log(NEW.id, 'триггер robot_bu_ctrack_e, :old.current_track_id='
                         || OLD.current_track_id || ' :new.current_track_id='
                         || NEW.current_track_id);
    FOR rit IN (
        SELECT * FROM robot_trigger_ignore WHERE robot_id = NEW.id
    ) LOOP
        RETURN NEW;
    END LOOP;
    -- Validation for warehouse with 2 robots
    IF (coalesce(OLD.current_track_id, 0) <> coalesce(NEW.current_track_id, 0)) THEN
        FOR rp IN (
            SELECT num_of_robots nor FROM repository_part
            WHERE id = NEW.repository_part_id
        ) LOOP
            IF (rp.nor = 2) THEN
                FOR st IN (
                    SELECT * FROM track
                    WHERE id = NEW.current_track_id AND locked_by_robot_id <> NEW.id
                ) LOOP
                    errm := 'Robot ' || NEW.id || ' is on invalid track npp ' || obj_rpart.get_track_npp_by_id(NEW.Current_track_id)
                        || ' old npp was ' || obj_rpart.get_track_npp_by_id(OLD.Current_track_id);
                    CALL obj_robot.log(NEW.id, ' тrbtr ' || errm);
                    RAISE EXCEPTION '%', errmsg
                        USING errcode = -20123;
                END LOOP;
            END IF;
        END LOOP;
    END IF;
    CALL obj_robot.log(NEW.id,' тrbtr '||' проверка прошла');
    -- Unlock robots
    IF (OLD.current_track_id IS NOT null) THEN -- Already working
        CALL obj_robot.log(NEW.id, ' тrbtr ' || '   не начало работы, снимаем блокировки');
        SELECT npp INTO npp_old FROM track WHERE id = OLD.current_track_id;
        CALL obj_robot.log(NEW.id, ' тrbtr ' || '   npp1=' || npp_old);
        CALL obj_robot.log(NEW.id, ' тrbtr ' || '   :new.current_track_id=' || NEW.current_track_id);
        SELECT npp INTO npp_new FROM track WHERE id = NEW.current_track_id;
        CALL obj_robot.log(NEW.id, ' тrbtr ' || '   npp2=' || npp_new);
        IF (coalesce(NEW.current_track_id, 0) <> coalesce(OLD.current_track_id, 0)) THEN
            CALL obj_robot.log(NEW.id, ' тrbtr ' || '   триггер robot_bu_ctrack_e - сменили трек с '
                                 || npp_old || ' на ' || npp_new || ' у робота ' || NEW.id);
            INSERT INTO log (action, old_value, new_value, comments, robot_id, command_id)
                VALUES(39, npp_old, npp_new, ' тrbtr ' || 'триггер robot_bu_ctrack_e - сменили трек с '
                       || npp_old || ' на ' || npp_new || ' у робота ' || NEW.id, NEW.id, NEW.command_inner_id);
        END IF;
        CALL obj_robot.log(NEW.id, ' тrbtr ' || '   :new.command_inner_id= ' || NEW.command_inner_id);
        IF (coalesce(NEW.command_inner_id, 0) <> 0) AND (coalesce(NEW.wait_for_problem_resolve, 0) = 0) THEN
            SELECT * INTO cirec FROM command_inner WHERE id = NEW.command_inner_id;
            IF cirec.command_type_id IN (4,21) THEN
                npp_to := cirec.npp_src;
                npp_to_id := cirec.track_src_id;
            ELSE
                npp_to := cirec.npp_dest;
                npp_to_id := cirec.track_dest_id;
            END IF;
            IF (npp_to = cirec.track_npp_begin) THEN
                CALL obj_robot.log(NEW.id, ' тrbtr  начальный трек команды совпадает с конечным');
                NEW.current_track_id := OLD.current_track_id;
            ELSE
                IF (obj_rpart.is_track_between(npp_new, cirec.track_npp_begin, npp_to, cirec.direction, NEW.repository_part_id) = 1) THEN
                    -- Robot is currently between starting point and destination
                    IF (obj_rpart.is_track_between(npp_new, cirec.track_npp_begin, npp_old, cirec.direction, NEW.repository_part_id) = 1) THEN
                        -- Robot moved backwards in the last step
                        CALL obj_robot.log(NEW.id,' тrbtr обратный отскок ');
                        NEW.current_track_id := OLD.current_track_id;
                        npp_new := npp_old;
                    END IF;
                ELSE
                    -- Robot went over
                    CALL obj_robot.log(NEW.id,' тrbtr промахнулись, разблокируем только часть правильную ');
                    NEW.current_track_id := npp_to_id;
                    npp_new := npp_to;
                END IF;
                CALL obj_robot.log(NEW.id, ' тrbtr ' || 'Разблокируем трек '
                                     || npp_old || ' ' || npp_new || ' ' || cirec.direction);
                CALL obj_rpart.unlock_track(NEW.id, NEW.repository_part_id, npp_old, npp_new, cirec.direction);
            END IF;
        END IF;
    END IF;
    IF (coalesce(NEW.current_track_id, 0) <> 0)
        AND (coalesce(NEW.current_track_id, 0) <> coalesce(OLD.current_track_id, 0))
    THEN
        CALL obj_robot.log(NEW.id, ' тrbtr ' || '   смена трека');
        SELECT npp INTO NEW.current_track_npp FROM track WHERE id = NEW.current_track_id;
        NEW.old_cur_track_npp := OLD.current_track_npp;
        NEW.old_cur_date_time := NEW.last_access_date_time;
        NEW.last_access_date_time := LOCALTIMESTAMP;
    END IF;
    CALL obj_robot.log(NEW.id, ' тrbtr ' || '    итого новый :new.current_track_id=' || NEW.current_track_id);
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION robot_bu_ctrack_e() OWNER TO postgres;

DROP TRIGGER IF EXISTS robot_bu_ctrack_e ON robot;

CREATE TRIGGER robot_bu_ctrack_e
    BEFORE UPDATE OF current_track_id
    ON robot
    FOR EACH ROW
    EXECUTE FUNCTION robot_bu_ctrack_e();
