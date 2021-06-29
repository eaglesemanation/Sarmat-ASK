CREATE OR REPLACE FUNCTION command_bi_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    cs RECORD;
    cd RECORD;
    cn RECORD;
    rpp RECORD;
    ccl RECORD;
    ccd RECORD;
    cl RECORD;
    cnt BIGINT;
    error_name TEXT;
    sqlt TEXT;
    cell_a TEXT;
    cell_cur TEXT;
    e1 BIGINT;
    e2 BIGINT;
BEGIN
    SELECT session_user INTO NEW.user_name;

    -- Default command type - 1 (move)
    -- если не указан тип команды, то считаем, что перемещение
    IF (coalesce(NEW.command_type_id, 0) = 0) THEN
        NEW.command_type_id := 1;
    END IF;

    IF (NEW.priority IS null) THEN
        NEW.priority := 0;
    END IF;

    -- Default target warehouse is equal to source warehouse
    -- если не указан склад-приемник, то делаем его равному складу источнику
    IF (coalesce(NEW.rp_dest_id, 0) = 0) THEN
        NEW.rp_dest_id := NEW.rp_src_id;
    END IF;

    IF (NEW.id IS null) THEN
        SELECT nextval('SEQ_command') INTO NEW.id;
        NEW.date_time_create := LOCALTIMESTAMP;

        -- проверка на статус новой команды
        IF (NEW.state <> 1) THEN
            RAISE EXCEPTION '%',
                service.ml_get_rus_eng_val(
                    'ERROR: При добавлении новой команды ее состояние должно быть=1, а не ',
                    'ERROR: New command state must be "1", but not '
                ) || NEW.state
                USING errcode = -20000 - 5;
        END IF;

        ---------------------------------
        -- TRANSFER_GEN
        ---------------------------------
        IF (NEW.command_type_id = 1) THEN
            -- Sanitizing client inputs
            -- правим возможные ошибки программы-клиента
            NEW.cell_src_sname := trim(NEW.cell_src_sname);
            NEW.cell_dest_sname := trim(NEW.cell_dest_sname);

            -- смотрим, правильно ли заданы условия команды

            -- Adding command is prohibited during calibration
            -- проверяем, а не запущена ли команда юстировки
            SELECT count(*) INTO cnt FROM command
                WHERE command_type_id = 19 AND state IN (0,1,3);
            IF (cnt <> 0) THEN
                RAISE EXCEPTION 'ERROR: already exists verify commands in running state!'
                    USING errcode = -20000 - 5;
            END IF;

            -- If there is only one warehouse - use it as a default
            -- проверка склада-источника
            IF (coalesce(NEW.rp_src_id, 0) = 0) THEN
                SELECT count(*) into cnt from repository_part;
                IF (cnt = 1) THEN
                    SELECT id INTO NEW.rp_src_id FROM repository_part;
                END IF;
            END IF;
            -- Check if set warehouse exists
            SELECT count(*) INTO cnt FROM repository_part WHERE id = coalesce(NEW.rp_src_id, 0);
            IF (cnt = 0) THEN
                RAISE EXCEPTION '%',
                    service.ml_get_rus_eng_val(
                        'ERROR: Указан несуществующий склад-источник',
                        'ERROR: Source warehouse doesn''t exist!'
                    ) || ' ' || coalesce(NEW.rp_src_id, 0)
                    USING errcode = -20000 - 1;
            END IF;

            -- If there is only one warehouse - use it as a default
            -- проверка склада-приемника
            IF (coalesce(NEW.rp_dest_id, 0) = 0) THEN
                SELECT count(*) INTO cnt FROM repository_part;
                IF (cnt = 1) THEN
                    SELECT id INTO NEW.rp_dest_id FROM repository_part;
                END IF;
            END IF;
            -- Check if set warehouse exists
            SELECT count(*) INTO cnt FROM repository_part WHERE id = coalesce(NEW.rp_dest_id,0);
            IF (cnt = 0) THEN
                RAISE EXCEPTION '%',
                    service.ml_get_rus_eng_val(
                        'ERROR: Указан несуществующий склад-приемник',
                        'ERROR: Destination warehouse doesn''t exist!'
                    )
                    USING errcode = -20000 - 2;
            END IF;

            -- Checks for source cell
            -- проверка ячейки-источника

            -- Check if cell exists
            SELECT count(*) INTO cnt FROM cell
                WHERE sname = coalesce(NEW.cell_src_sname, '-')
                AND hi_level_type <> 11
                AND repository_part_id = NEW.rp_src_id;
            IF (cnt = 0) THEN -- нет ячейки-источника
                RAISE EXCEPTION '%',
                    service.ml_get_rus_eng_val(
                        'ERROR: Указана несуществующая ячейка-источник:',
                        'ERROR: Source cell doesn''t exist:'
                    ) || NEW.cell_src_sname || ' ' || NEW.rp_src_id
                    USING errcode = -20000 - 3;
            ELSE
                -- Check if cell has no errors
                SELECT count(*) INTO cnt FROM cell
                    WHERE sname = coalesce(NEW.cell_src_sname, '-')
                    AND hi_level_type <> 11
                    AND is_error = 0
                    AND repository_part_id = NEW.rp_src_id;
                IF (cnt = 0) THEN -- ошибочная ячейки-источника
                    RAISE EXCEPTION '%',
                        service.ml_get_rus_eng_val(
                            'ERROR: Ячейка-источник в ошибочном состоянии:',
                            'ERROR: Source cell is in error state:'
                        ) || NEW.cell_src_sname
                        USING errcode = -20000 - 6;
                ELSE -- есть, означиваем
                    SELECT id INTO NEW.cell_src_id FROM cell
                        WHERE sname = coalesce(NEW.cell_src_sname, '-')
                        AND repository_part_id = NEW.rp_src_id;
                END IF;
                IF (service.is_cell_full_check() = 1) THEN
                    FOR cs IN (SELECT * FROM cell WHERE id = NEW.cell_src_id) LOOP
                        IF (cs.is_full < 1) THEN
                            RAISE EXCEPTION 'ERROR: cell-source % is empty', NEW.cell_src_sname
                                USING errcode = -20000 - 6;
                        END IF;
                    END LOOP;
                END IF;
            END IF;

            -- Checks for destination cell
            -- проверка ячейки-приемника
            -- Check if cell exists
            SELECT count(*) INTO cnt FROM cell
                WHERE sname = coalesce(NEW.cell_dest_sname, '-')
                AND hi_level_type <> 11
                AND repository_part_id = NEW.rp_dest_id;
            IF (cnt = 0) THEN -- нет ячейки-приемника
                RAISE EXCEPTION '%',
                    service.ml_get_rus_eng_val(
                        'ERROR: Указана несуществующая ячейка-приемник:',
                        'ERROR: Destination cell doesn''t exist:'
                    ) || NEW.cell_dest_sname
                    USING errcode = -20000 - 3;
            ELSE
                -- Check if cell has no errors
                SELECT count(*) INTO cnt FROM cell
                    WHERE sname = coalesce(NEW.cell_dest_sname, '-')
                    AND hi_level_type <> 11
                    AND is_error = 0
                    AND repository_part_id = NEW.rp_dest_id;
                IF (cnt = 0) THEN -- ошибочная ячейки-приемник
                    RAISE EXCEPTION '%',
                        service.ml_get_rus_eng_val(
                            'ERROR: Ячейка-приемник в ошибочном статусе:',
                            'ERROR: Destination cell is in error state:'
                        ) || NEW.cell_dest_sname
                        USING errcode = -20000 - 8;
                ELSE -- есть, означиваем
                    SELECT id INTO NEW.cell_dest_id FROM cell
                        WHERE sname = coalesce(NEW.cell_dest_sname, '-')
                        AND repository_part_id = NEW.rp_dest_id;
                END IF;
                IF (service.is_cell_full_check = 1) THEN
                    FOR cd IN (SELECT * FROM cell WHERE id = NEW.cell_dest_id) LOOP
                        IF (cd.is_full >= cd.max_full_size) THEN
                            RAISE EXCEPTION 'ERROR: cell-destination % is overfull', NEW.cell_dest_sname
                                USING errcode = -20000 - 6;
                        END IF;
                    END LOOP;
                END IF;
            END IF;

            IF (coalesce(NEW.container_id, 0) = 0) THEN
                FOR cn IN (
                    SELECT * FROM container
                    WHERE location = 1
                    AND coalesce(cell_id, 0) <> 0
                    AND cell_id = NEW.cell_src_id
                ) LOOP
                    NEW.container_id:=cn.id;
                    EXIT;
                END LOOP;
            END IF;

            NEW.npp_src := obj_rpart.get_track_npp_by_cell_and_rp(NEW.rp_src_id, NEW.cell_src_sname);
            NEW.npp_dest := obj_rpart.get_track_npp_by_cell_and_rp(NEW.rp_dest_id, NEW.cell_dest_sname);
            NEW.track_src_id := obj_rpart.get_track_id_by_cell_and_rp(NEW.rp_src_id, NEW.cell_src_sname);
            NEW.track_dest_id := obj_rpart.get_track_id_by_cell_and_rp(NEW.rp_dest_id, NEW.cell_dest_sname);

            -- Command execution start
            -- начало работы команды

            -- Case where source and destination are the same
            -- случай, если склад-источник и приемник совпадают
            IF NEW.rp_src_id = NEW.rp_dest_id THEN -- склад источник и приемник совпадают
                FOR rpp IN (
                    SELECT id, repository_type rt, num_of_robots nor
                    FROM repository_part
                    WHERE id = NEW.rp_src_id
                ) LOOP
                    cnt := 0;
                    -- Linear track, 2 robots on track
                    IF (rpp.rt = 0) AND (rpp.nor = 2) THEN -- склад линейный, два робота на рельсе
                        e1 := service.is_cell_near_edge(NEW.cell_src_id);
                        e2 := service.is_cell_near_edge(NEW.cell_dest_id);
                        IF (e1 <> e2) AND (e1 <> 0) AND (e2 <> 0)
                            OR (e1 <> 0 OR e2 <> 0)
                            AND service.cell_acc_only_1_robot(NEW.cell_src_id, NEW.cell_dest_id) = 1
                        THEN
                            PERFORM service.log2file('пущаем транзит в триггере');
                            cnt := obj_rpart.get_transit_1rp_cell(NEW.rp_src_id);
                            IF (cnt = 0) THEN
                                RAISE EXCEPTION '%',
                                    service.ml_get_rus_eng_val(
                                        'ERROR: Нет свободных транзитных ячеек!',
                                        'ERROR: No free transit cells!'
                                    )
                                    USING errcode = -20000 - 8;
                            ELSE
                                FOR cd IN (
                                    SELECT c.*, sh.track_id
                                        FROM cell c
                                        INNER JOIN shelving sh
                                            ON c.shelving_id=sh.id
                                        WHERE cell.id = cnt
                                ) LOOP
                                    INSERT INTO command_rp (
                                        command_type_id, rp_id, cell_src_sname, cell_dest_sname,
                                        priority, state, command_id, track_src_id , track_dest_id,
                                        cell_src_id, cell_dest_id, npp_src, npp_dest, container_id
                                    ) VALUES (
                                        3, NEW.rp_src_id, NEW.cell_src_sname, cd.sname,
                                        NEW.priority, 1, NEW.id,
                                        NEW.track_src_id, cd.track_id,
                                        NEW.cell_src_id, cd.id,
                                        NEW.npp_src, cd.track_npp,
                                        NEW.container_id
                                    );
                                    PERFORM service.cell_lock_by_cmd(cd.id, NEW.id);
                                END LOOP;
                            END IF;
                        END IF;
                    END IF;
                    -- Cyclic track, 4 robots on track
                    IF (rpp.rt = 1) AND (rpp.nor = 4) THEN -- склад кольцевой, 4 робота на рельсе
                        IF (obj_rpart.calc_repair_robots(NEW.rp_src_id) > 0) THEN -- есть на ремонте роботы по подскладу
                            -- находятся ли источник/приемник в шлейфе поломанного робота?
                            IF (obj_rpart.is_track_near_repair_robot(rpp.id, NEW.npp_src) = 1)
                                OR (obj_rpart.is_track_near_repair_robot(NEW.npp_dest, rpp.id) = 1)
                            THEN
                                -- есть ли ячейки на подскладе для внутреннего транзита
                                IF (obj_rpart.is_exists_cell_type(rpp.id, obj_ask.CELL_TYPE_TRANSIT_1RP) = 1) THEN
                                    PERFORM service.log2file('пущаем внутренний транзит в триггере');
                                    cnt := obj_rpart.get_transit_1rp_cell(NEW.rp_src_id);
                                    IF (cnt = 0) THEN
                                        RAISE EXCEPTION '%',
                                            service.ml_get_rus_eng_val(
                                                'ERROR: Нет свободных транзитных ячеек!',
                                                'ERROR: No free transit cells!'
                                            )
                                            USING errcode = -20000 - 8;
                                    ELSE
                                        FOR cd IN (
                                            SELECT c.*, sh.track_id
                                                FROM cell c
                                                INNER JOIN shelving sh
                                                    ON c.shelving_id = sh.id
                                                WHERE c.id = cnt
                                        ) LOOP
                                            INSERT INTO command_rp (
                                                command_type_id, rp_id, cell_src_sname, cell_dest_sname,
                                                priority, state, command_id, track_src_id, track_dest_id,
                                                cell_src_id, cell_dest_id, npp_src, npp_dest, container_id
                                            ) VALUES (
                                                3, NEW.rp_src_id, NEW.cell_src_sname,
                                                cd.sname, NEW.priority, 1, NEW.id,
                                                NEW.track_src_id, cd.track_id,
                                                NEW.cell_src_id, cd.id,
                                                NEW.npp_src, cd.track_npp,
                                                NEW.container_id
                                            );
                                            PERFORM service.cell_lock_by_cmd(cd.id, NEW.id);
                                        END LOOP;
                                    END IF;
                                END IF;
                            END IF;
                        END IF;
                    END IF;
                    -- нет необходимости в транзитных командах в пределах одного подсклада
                    IF (cnt = 0) THEN
                        INSERT INTO command_rp (
                            command_type_id, rp_id, cell_src_sname, cell_dest_sname,
                            priority, state, command_id, track_src_id, track_dest_id,
                            cell_src_id, cell_dest_id, npp_src, npp_dest, container_id)
                        VALUES (
                            3, NEW.rp_src_id, NEW.cell_src_sname, NEW.cell_dest_sname,
                            NEW.priority, 1, NEW.id,
                            NEW.track_src_id, NEW.track_dest_id,
                            NEW.cell_src_id, NEW.cell_dest_id,
                            NEW.npp_src, NEW.npp_dest,
                            NEW.container_id
                        );
                    END IF;
                END LOOP;
                FOR ccl IN (
                    SELECT * FROM cell_cmd_lock
                    WHERE cell_id = NEW.cell_src_id
                ) LOOP
                    RAISE EXCEPTION '%',
                        service.ml_get_rus_eng_val(
                            'ERROR: Ячейка-источник занята другой командой!',
                            'ERROR: Source cell locked by another cmd!'
                        )
                        USING errcode = -20000 - 8;
                END LOOP;
                PERFORM service.cell_lock_by_cmd(NEW.cell_src_id, NEW.id);
                FOR ccl IN (
                    SELECT count(*) cc
                    FROM cell_cmd_lock
                    WHERE cell_id = NEW.cell_dest_id
                ) LOOP
                    IF (ccl.cc > 0) THEN
                        FOR ccd IN (
                            SELECT *
                            FROM cell
                            WHERE id = NEW.cell_dest_id
                        ) LOOP
                            IF (ccl.cc >= ccd.max_full_size) THEN
                                RAISE EXCEPTION '%',
                                    service.ml_get_rus_eng_val(
                                        'ERROR: Ячейка-приемник занята другой/другими командами!',
                                        'ERROR: Destination cell locked by another cmds!'
                                    )
                                    USING errcode = -20000 - 8;
                            END IF;
                        END LOOP;
                    END IF;
                END LOOP;
                PERFORM service.cell_lock_by_cmd(NEW.cell_dest_id, NEW.id);
            -- ************************************
            -- Case where source and destination are different
            -- склад-источник и склад-приемник разные
            ELSE
                -- ищем как вывести контейнер из склада-источника
                NEW.container_rp_id := NEW.rp_src_id;
                sqlt := '
                    FROM cell
                    WHERE hi_level_type IN (6, 8)
                    AND is_full = 0
                    AND is_error = 0
                    AND coalesce(blocked_by_ci_id, 0) = 0
                    AND NOT EXISTS (
                        SELECT * FROM command_rp
                        WHERE state IN (1, 3)
                        AND rp_id = repository_part_id
                        AND cell_dest_sname = sname
                        AND command_type_id = 3
                    )
                    AND shelving_id IN (
                        SELECT id FROM shelving
                        WHERE track_id in (
                            SELECT id FROM track
                            WHERE repository_part_id = ' || NEW.rp_src_id || '
                        )
                    )
                ';
                INSERT INTO command_rp (
                    command_type_id, rp_id, cell_src_sname,
                    sql_text_for_group, priority, state, command_id,
                    track_src_id, cell_src_id, cell_dest_id,
                    npp_src, npp_dest, container_id
                ) VALUES (
                    7, NEW.rp_src_id, NEW.cell_src_sname,
                    sqlt, NEW.priority, 1, NEW.id,
                    NEW.track_src_id, NEW.cell_src_id, NEW.cell_dest_id,
                    NEW.npp_src, NEW.npp_dest, NEW.container_id
                );
                PERFORM service.cell_lock_by_cmd(NEW.cell_dest_id, NEW.id);
                PERFORM service.cell_lock_by_cmd(NEW.cell_src_id, NEW.id);
            END IF;

        ----------------------------------
        -- Test.Mech
        ----------------------------------
        ELSIF NEW.command_type_id = 23 THEN
            -- проверяем робота
            IF (NEW.robot_ip IS null) THEN
                RAISE EXCEPTION 'ERROR: cmd Cell.Verify.X need not null robot_ip'
                    USING errcode = -20000 - 5;
            END IF;
            SELECT count(*) INTO cnt FROM robot WHERE ip = NEW.robot_ip;
            IF (cnt = 0) THEN
                RAISE EXCEPTION 'ERROR: robot with ip=% not found!', NEW.robot_ip
                    USING errcode = -20000 - 5;
            END IF;
            SELECT repository_part_id, id INTO NEW.rp_src_id, NEW.robot_id
                FROM robot WHERE ip = NEW.robot_ip;
            -- проверяем, а не запущена ли уже команда подобная не начатая
            SELECT count(*) INTO cnt FROM command
                WHERE command_type_id = 23 AND state IN (0, 1);
            IF (cnt <> 0) THEN
                RAISE EXCEPTION 'ERROR: already exists test commands in not running state!'
                    USING errcode = -20000 - 5;
            END IF;
            -- проверяем, а не запущена ли уже команда подобная
            SELECT count(*) INTO cnt FROM command
                WHERE robot_id = NEW.robot_id AND command_type_id = 23 AND state IN (0, 1, 3);
            IF (cnt <> 0) THEN
                RAISE EXCEPTION 'ERROR: already exists commands fo robot with ip=% in 0,1,3 state!', NEW.robot_ip
                    USING errcode = -20000 - 5;
            END IF;
            -- ячейки
            IF (NEW.cells IS null) THEN
                -- не означены
                cnt := 0;
                FOR cl IN (
                    SELECT * FROM cell
                    WHERE repository_part_id = NEW.rp_src_id
                    AND is_error = 0
                    AND hi_level_type IN (1, 10)
                    ORDER BY track_npp, substr(sname, 1, 3)
                ) LOOP
                    INSERT INTO robot_cell_verify (
                        cmd_id, robot_ip, robot_id, cell_sname, cell_id, vstate
                    ) VALUES (
                        NEW.id, NEW.robot_ip, NEW.robot_id, cl.sname, cl.id, 1
                    );
                    cnt := cnt + 1;
                END LOOP;
                IF (cnt = 0) THEN
                    RAISE EXCEPTION 'ERROR: there are not appropriate cells for robot ip=%!',
                        NEW.robot_ip
                        USING errcode = -20000 - 5;
                END IF;
            ELSE -- NEW.cells IS NOT null
                -- есть ячейки
                cell_a := NEW.cells;
                LOOP
                    cnt := position(',' IN cell_a);
                    IF (cnt <> 0) THEN
                        cell_cur := trim(substring(cell_a, 1, cnt - 1));
                        cell_a := substring(cell_a, cnt + 1);
                    ELSE
                        cell_cur := trim(cell_a);
                        cell_a := null;
                    END IF;
                    SELECT count(*) INTO cnt FROM cell
                        WHERE repository_part_id = NEW.rp_src_id
                        AND sname = cell_cur;
                    IF (cnt = 0) THEN
                        RAISE EXCEPTION 'ERROR: cell % not found!', cell_cur
                            USING errcode = -20000 - 5;
                    ELSE
                        SELECT count(*) INTO cnt FROM cell
                            WHERE repository_part_id = NEW.rp_src_id
                            AND sname = cell_cur
                            AND is_error = 0;
                        IF (cnt <> 0) THEN
                            FOR cl IN (
                                SELECT * FROM cell
                                    WHERE repository_part_id = NEW.rp_src_id
                                    AND sname = cell_cur
                                    AND is_error = 0
                            ) LOOP
                                INSERT INTO robot_cell_verify (
                                    cmd_id, robot_ip, robot_id, cell_sname, cell_id, vstate
                                ) VALUES (
                                    NEW.id, NEW.robot_ip, NEW.robot_id, cell_cur, cl.id, 1
                                );
                            END LOOP;
                        END IF;
                    END IF;
                    EXIT WHEN cell_a IS null OR trim(cell_a) = '';
                END LOOP;
            END IF; -- NEW.cells IS null
            -- проверили, а есть ли ячейки
            SELECT count(*) INTO cnt FROM robot_cell_verify WHERE cmd_id = NEW.id;
            IF (cnt = 0) THEN
                RAISE EXCEPTION 'ERROR: is''nt cell for testing!%', NEW.cells
                    USING errcode = -20000 - 5;
            END IF;
            -- типа пусканули
            FOR cl IN (
                SELECT c.*, sh.track_id
                    FROM robot_cell_verify rcv
                    INNER JOIN cell c
                        ON rcv.cell_id = c.id
                    INNER JOIN shelving sh
                        ON c.shelving_id = sh.id
                    WHERE cmd_id = NEW.id
                    AND is_full = 1
                    ORDER BY random()
            ) LOOP
                FOR cd IN (
                    SELECT c.*, sh.track_id
                        FROM robot_cell_verify rcv
                        INNER JOIN cell c
                            ON rcv.cell_id = c.id
                        INNER JOIN shelving sh
                            ON c.shelving_id = sh.id
                        WHERE cmd_id = NEW.id
                        AND is_full = 0
                        AND cell.id <> cl.id
                        ORDER BY random()
                ) LOOP
                    INSERT INTO command_rp (
                        command_type_id, rp_id, cell_src_sname, cell_dest_sname,
                        priority, state, command_id, track_src_id , track_dest_id,
                        cell_src_id, cell_dest_id, npp_src, npp_dest, container_id
                    ) VALUES (
                        3, NEW.rp_src_id, cl.sname, cd.sname, 0, 1, NEW.id,
                        (SELECT track_id FROM shelving WHERE id = cl.shelving_id),
                        (SELECT track_id FROM shelving WHERE id = cd.shelving_id),
                        cl.id, cd.id, cl.track_npp,cd.track_npp, cl.container_id
                    );
                    PERFORM service.cell_lock_by_cmd(cl.id, NEW.id);
                    PERFORM service.cell_lock_by_cmd(cd.id, NEW.id);
                    EXIT;
                END LOOP;
                EXIT;
            END LOOP;
            NEW.state := 1;

        ----------------------------------
        -- Cell.Verify.X
        ----------------------------------
        ELSEIF NEW.command_type_id = 19 THEN
            -- проверяем робота
            IF (NEW.robot_ip IS null) THEN
                RAISE EXCEPTION 'ERROR: cmd Cell.Verify.X need not null robot_ip'
                    USING errcode = -20000 - 5;
            END IF;
            SELECT count(*) INTO cnt FROM robot WHERE ip = NEW.robot_ip;
            IF (cnt = 0) THEN
                RAISE EXCEPTION 'ERROR: robot with ip=% not found!',
                    NEW.robot_ip
                    USING errcode = -20000 - 5;
            END IF;
            SELECT id, repository_part_id INTO NEW.robot_id, NEW.rp_src_id
                FROM robot WHERE ip = NEW.robot_ip;
            -- проверяем, а не запущена ли уже команда подобная не начатая
            SELECT count(*) INTO cnt FROM command
                WHERE command_type_id = 19 AND state IN (0, 1);
            IF (cnt <> 0) THEN
                RAISE EXCEPTION 'ERROR: already exists verify commands in not running state!'
                    USING errcode = -20000 - 5;
            END IF;
            -- проверяем, а не запущена ли уже команда подобная
            SELECT count(*) INTO cnt FROM command
                WHERE robot_id = NEW.robot_id
                AND command_type_id = 19
                AND state IN (0, 1, 3);
            IF (cnt <> 0) THEN
                RAISE EXCEPTION 'ERROR: already exists commands fo robot with ip=% in 0,1,3 state!',
                    NEW.robot_ip
                    USING errcode = -20000 - 5;
            END IF;
            -- ячейки
            IF (NEW.cells IS null) THEN
                -- не означены
                cnt := 0;
                FOR cl IN (
                    SELECT * FROM cell c
                        WHERE c.repository_part_id = NEW.rp_src_id
                        AND c.is_error = 1
                        AND NOT EXISTS(
                            SELECT * FROM robot_cell_verify
                                WHERE cell_id = c.id
                                AND robot_id = NEW.robot_id
                                AND vstate IN (2, 5)
                        )
                        AND c.hi_level_type IN (1, 10)
                        ORDER BY track_npp, substring(sname, 1, 3)
                ) LOOP
                    INSERT INTO robot_cell_verify (
                        cmd_id, robot_ip, robot_id, cell_sname, cell_id, vstate
                    ) VALUES (
                        NEW.id, NEW.robot_ip, NEW.robot_id, cl.sname, cl.id, 1
                    );
                    cnt := cnt + 1;
                END LOOP;
                IF (cnt = 0) THEN
                    RAISE EXCEPTION 'ERROR: all cells are good for robot ip=%!',
                        NEW.robot_ip
                        USING errcode = -20000 - 5;
                END IF;
            ELSE -- NEW.cells IS NOT null
                -- есть ячейки
                cell_a := NEW.cells;
                LOOP
                    cnt := position(',' IN cell_a);
                    IF (cnt <> 0) THEN
                        cell_cur := trim(substring(cell_a, 1, cnt-1));
                        cell_a := substring(cell_a, cnt+1);
                    ELSE
                        cell_cur := trim(cell_a);
                        cell_a := null;
                    END IF;
                    SELECT count(*) INTO cnt FROM cell
                        WHERE repository_part_id = NEW.rp_src_id
                        AND sname = cell_cur;
                    IF (cnt = 0) THEN
                        RAISE EXCEPTION 'ERROR: cell % not found!', cell_cur
                            USING errcode = -20000 - 5;
                    ELSE
                        SELECT count(*) INTO cnt FROM cell
                            WHERE repository_part_id = NEW.rp_src_id
                            AND sname = cell_cur
                            AND is_error = 1;
                        IF (cnt <> 0) THEN
                            FOR cl IN (
                                SELECT * FROM cell c
                                    WHERE c.repository_part_id = NEW.rp_src_id
                                    AND c.sname = cell_cur
                                    AND c.is_error = 1
                                    AND NOT EXISTS (
                                        SELECT * FROM robot_cell_verify
                                            WHERE cell_id = c.id
                                            AND robot_id = NEW.robot_id
                                            AND vstate IN (2, 5)
                                    )
                            ) LOOP
                                INSERT INTO robot_cell_verify (
                                    cmd_id, robot_ip, robot_id, cell_sname, cell_id, vstate
                                ) VALUES (
                                    NEW.id, NEW.robot_ip, NEW.robot_id, cell_cur, cl.id, 1
                                );
                            END LOOP;
                        END IF;
                    END IF;
                    EXIT WHEN cell_a IS null OR trim(cell_a) = '';
                END LOOP;
            END IF; -- NEW.cells IS null
            -- проверили, а есть ли ячейки
            SELECT count(*) INTO cnt FROM robot_cell_verify WHERE cmd_id = NEW.id;
            IF (cnt = 0) THEN
                RAISE EXCEPTION 'ERROR: is''nt cell for verify!'
                    USING errcode = -20000 - 5;
            END IF;

            -- типа пусканули
            FOR cl IN (
                SELECT c.*, sh.track_id
                    FROM robot_cell_verify rcv
                    INNER JOIN cell c
                        ON rcv.cell_id = c.id
                    INNER JOIN shelving sh
                        ON c.shelving_id=sh.id
                    WHERE cmd_id = NEW.id
                    ORDER BY rcv.id
            ) LOOP
                INSERT INTO command_rp (
                    command_id, command_type_id, robot_id,
                    rp_id, cell_src_sname, track_src_id, cell_src_id,
                    npp_src, state, priority, direction_1, substate
                ) VALUES (
                    NEW.id, 20, NEW.robot_id, NEW.rp_src_id, cl.sname,
                    cl.track_id, cl.id, cl.track_npp, 1, -99999999,
                    service.get_ust_cell_dir(NEW.robot_id, cl.track_id), 0
                );
                EXIT;
            END LOOP;
            NEW.state := 1;
        END IF;
    END IF;

    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION command_bi_e() OWNER TO postgres;

COMMENT ON FUNCTION command_bi_e()
    IS 'Wide range of command verification before insertion. Probably should be split into separate parts';

DROP TRIGGER IF EXISTS command_bi_e ON command;

CREATE TRIGGER command_bi_e
    BEFORE INSERT
    ON command
    FOR EACH ROW
    EXECUTE FUNCTION command_bi_e();

-- vim: ft=pgsql
