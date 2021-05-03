CREATE OR REPLACE TRIGGER command_bi_e
BEFORE INSERT
ON command
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
 error_name varchar2(2500);
 sqlt varchar2(3000);
 cell_a varchar2(4000);
 cell_cur varchar2(100);
 e1 number;
 e2 number;
BEGIN
 :new.user_name:=user;

 if nvl(:new.command_type_id,0)=0 then -- если не указан тип команды, то считаем, что перемещение
   :new.command_type_id:=1;
 end if;

 if :new.priority is null  then
   :new.priority:=0;
 end if;

 if nvl(:new.rp_dest_id,0)=0 then  -- если не указан склад-приемник, то делаем его равному складу источнику
   :new.rp_dest_id:=:new.rp_src_id;
 end if; 

 if :new.ID is null then
   SELECT SEQ_command.nextval INTO :new.ID FROM dual;
   :new.date_time_create:=sysdate;


   -- проверка на статус новой команды
   if :new.state<>1 then
      raise_application_error (-20000-5, service.ml_get_rus_eng_val('ERROR: При добавлении новой команды ее состояние должно быть=1, а не ',
                'ERROR: New command state must be "1", but not ')||:new.state, TRUE);
   end if;

   -- анализ новой команды

   ---------------------------------
   -- TRANSFER_GEN
   ---------------------------------
   if :new.command_type_id=1 then
     -- правим возможные ошибки программы-клиента
     :new.cell_src_sname:=trim(:new.cell_src_sname);
     :new.cell_dest_sname:=trim(:new.cell_dest_sname);

     -- смотрим, правильно ли заданы условия команды

     -- проверяем, а не запущена ли команда юстировки
     select count(*) into cnt from command
     where command_type_id=19 and state in (0,1,3);
     if cnt<>0 then
       raise_application_error (-20000-5, 'ERROR: already exists verify commands in running state!', TRUE);
     end if;


     -- проверка склада-источника
     if nvl(:new.rp_src_id,0)=0 then
       select count(*) into cnt from repository_part;
       if cnt=1 then -- их всего 1
         select id into :new.rp_src_id from repository_part;
       end if;
     end if;
     select count(*) into cnt from repository_part where id=nvl(:new.rp_src_id,0);
     if cnt=0 then -- нет склада источника
       raise_application_error (-20000-1, service.ml_get_rus_eng_val('ERROR: Указан несуществующий склад-источник',
                'ERROR: Source warehouse doesn''t exist!')||' '||nvl(:new.rp_src_id,0), TRUE);
     end if;

     -- проверка склада-приемника
     if nvl(:new.rp_dest_id,0)=0 then
       select count(*) into cnt from repository_part;
       if cnt=1 then -- их всего 1
         select id into :new.rp_dest_id from repository_part;
       end if;
     end if;
     select count(*) into cnt from repository_part where id=nvl(:new.rp_dest_id,0);
     if cnt=0 then -- нет склада приемника
       raise_application_error (-20000-2, service.ml_get_rus_eng_val('ERROR: Указан несуществующий склад-приемник',
                'ERROR: Destination warehouse doesn''t exist!'), TRUE);
     end if;

     -- проверка ячейки-источника
     select count(*) into cnt from cell
     where sname =nvl(:new.cell_src_sname ,'-')
           and hi_level_type<>11
           and repository_part_id=:new.rp_src_id;
     if cnt=0 then -- нет ячейки-истоничка
       raise_application_error (-20000-3, service.ml_get_rus_eng_val('ERROR: Указана несуществующая ячейка-источник:',
                'ERROR: Source cell doesn''t exist:')||:new.cell_src_sname||' '||:new.rp_src_id, TRUE);
     else
       select count(*) into cnt from cell
       where sname =nvl(:new.cell_src_sname ,'-')
             and hi_level_type<>11
             and is_error =0
             and repository_part_id=:new.rp_src_id;
       if cnt=0 then -- ошибочная ячейки-истоничка
         raise_application_error (-20000-6, service.ml_get_rus_eng_val('ERROR: Ячейка-источник в ошибочном состоянии:',
                'ERROR: Source cell is in error state:')||:new.cell_src_sname, TRUE);
       else  -- есть, означиваем
         select id into :new.cell_src_id from cell
         where sname =nvl(:new.cell_src_sname ,'-')
               and repository_part_id=:new.rp_src_id;
       end if;
       if service.is_cell_full_check=1 then
         for cs in (select * from cell where id=:new.cell_src_id) loop
           if cs.is_full<1 then
             raise_application_error (-20000-6, 'ERROR: cell-source '||:new.cell_src_sname||' is empty', TRUE);
           end if;
         end loop;
       end if;
     end if;

     -- проверка ячейки-приемника
     select count(*) into cnt from cell
     where sname =nvl(:new.cell_dest_sname ,'-')
           and hi_level_type<>11
           and repository_part_id=:new.rp_dest_id;
     if cnt=0 then -- нет ячейки-приемника
       raise_application_error (-20000-3, service.ml_get_rus_eng_val('ERROR: Указана несуществующая ячейка-приемник:',
                'ERROR: Destination cell doesn''t exist:')||:new.cell_dest_sname, TRUE);
     else
       select count(*) into cnt from cell
       where sname =nvl(:new.cell_dest_sname ,'-')
             and hi_level_type<>11
             and is_error =0
             and repository_part_id=:new.rp_dest_id;
       if cnt=0 then -- ошибочная ячейки-приемник
         raise_application_error (-20000-8, service.ml_get_rus_eng_val('ERROR: Ячейка-приемник в ошибочном статусе:',
                'ERROR: Destination cell is in error state:')||:new.cell_dest_sname, TRUE);
       else  -- есть, означиваем
         select id into :new.cell_dest_id from cell
         where sname =nvl(:new.cell_dest_sname ,'-')
               and repository_part_id=:new.rp_dest_id;
       end if;
       if service.is_cell_full_check=1 then
         for cd in (select * from cell where id=:new.cell_dest_id) loop
           if cd.is_full>=cd.max_full_size  then
             raise_application_error (-20000-6, 'ERROR: cell-destination '||:new.cell_dest_sname||' is overfull', TRUE);
           end if;
         end loop;
       end if;
     end if;

     if nvl(:new.container_id,0)=0 then
       for cn in (select * from container where location=1 and nvl(cell_id,0)<>0 and cell_id=:new.cell_src_id) loop
         :new.container_id:=cn.id;
         exit;
       end loop;
     end if;

     :new.npp_src:=obj_rpart.get_track_npp_by_cell_and_rp(:new.rp_src_id,:new.cell_src_sname);
     :new.npp_dest:=obj_rpart.get_track_npp_by_cell_and_rp(:new.rp_dest_id,:new.cell_dest_sname);
     :new.track_src_id:=obj_rpart.get_track_id_by_cell_and_rp(:new.rp_src_id,:new.cell_src_sname);
     :new.track_dest_id:=obj_rpart.get_track_id_by_cell_and_rp(:new.rp_dest_id,:new.cell_dest_sname);


     -- начало работы команды
     -- случай, если склад-источник и приемник совпдают
     if :new.rp_src_id=:new.rp_dest_id then -- склад источник и приемник совпадают
       for rpp in (select id, repository_type rt, num_of_robots nor from repository_part where id=:new.rp_src_id) loop
         cnt:=0;
         if rpp.rt=0 and rpp.nor=2 then -- склад линейный, два робота на рельсе
           e1:=service.is_cell_near_edge(:new.cell_src_id);
           e2:=service.is_cell_near_edge(:new.cell_dest_id);
           if e1<>e2 and e1<>0 and e2<>0
             or
             (e1<>0 or e2<>0)  and service.cell_acc_only_1_robot(:new.cell_src_id,:new.cell_dest_id)=1
             then
             service.log2file('пущаем транзит в триггере');
             cnt:=obj_rpart.get_transit_1rp_cell(:new.rp_src_id);
             if cnt=0 then
              raise_application_error (-20000-8, service.ml_get_rus_eng_val('ERROR: Нет свободных транзитных ячеек!',
                'ERROR: No free transit cells!'), TRUE);
             else
               for cd in (select cell.*, sh.track_id from cell, shelving sh where cell.id=cnt and shelving_id=sh.id) loop
                 insert into command_rp (command_type_id, rp_id, cell_src_sname, cell_dest_sname,
                                         priority, state, command_id, track_src_id , track_dest_id,
                                         cell_src_id, cell_dest_id, npp_src, npp_dest, container_id)
                 values (3,:new.rp_src_id,:new.cell_src_sname, cd.sname, :new.priority, 1, :new.id,
                         :new.track_src_id, cd.track_id,
                         :new.cell_src_id, cd.id,
                         :new.npp_src,cd.track_npp,
                         :new.container_id);
                  service.cell_lock_by_cmd(cd.id,:new.id);
               end loop;
             end if;
           end if;
         end if;
         if rpp.rt=1 and rpp.nor=4 then -- склад кольцевой, 4 робота на рельсе
           if obj_rpart.Calc_Repair_robots(:new.rp_src_id)>0 then -- есть на ремонте роботы по подскладу
             -- находятся ли источник/применик в шлейфе поломанного робота?
             if obj_rpart.Is_Track_Near_Repair_Robot(rpp.id,:new.npp_src)=1 or obj_rpart.Is_Track_Near_Repair_Robot(:new.npp_dest,rpp.id)=1 then
               if obj_rpart.is_exists_cell_type(rpp.id,obj_ask.CELL_TYPE_TRANSIT_1RP)=1 then -- есть ли ячейки на подскладе для внутреннего транзита
                 service.log2file('пущаем внутренний транзит в триггере');
                 cnt:=obj_rpart.get_transit_1rp_cell(:new.rp_src_id);
                 if cnt=0 then
                  raise_application_error (-20000-8, service.ml_get_rus_eng_val('ERROR: Нет свободных транзитных ячеек!',
                    'ERROR: No free transit cells!'), TRUE);
                 else
                   for cd in (select cell.*, sh.track_id from cell, shelving sh where cell.id=cnt and shelving_id=sh.id) loop
                     insert into command_rp (command_type_id, rp_id, cell_src_sname, cell_dest_sname,
                                             priority, state, command_id, track_src_id , track_dest_id,
                                             cell_src_id, cell_dest_id, npp_src, npp_dest, container_id)
                     values (3,:new.rp_src_id,:new.cell_src_sname, cd.sname, :new.priority, 1, :new.id,
                             :new.track_src_id, cd.track_id,
                             :new.cell_src_id, cd.id,
                             :new.npp_src,cd.track_npp,
                             :new.container_id);
                      service.cell_lock_by_cmd(cd.id,:new.id);
                   end loop;
                  end if;
               end if;
             end if;
           end if;
         end if;
         if cnt=0 then -- нет необходимости в транзитных командах в пределах одного подсклада
           insert into command_rp (command_type_id, rp_id, cell_src_sname, cell_dest_sname,
                                   priority, state, command_id, track_src_id , track_dest_id,
                                   cell_src_id, cell_dest_id, npp_src, npp_dest, container_id)
           values (3,:new.rp_src_id,:new.cell_src_sname, :new.cell_dest_sname, :new.priority, 1, :new.id,
                   :new.track_src_id, :new.track_dest_id,
                   :new.cell_src_id, :new.cell_dest_id,
                   :new.npp_src,:new.npp_dest,
                   :new.container_id);
         end if;
       end loop;
       for ccl in (select * from cell_cmd_lock where cell_id=:new.cell_src_id) loop
              raise_application_error (-20000-8, service.ml_get_rus_eng_val('ERROR: Ячейка-источник занята другой командой!',
                'ERROR: Source cell locked by another cmd!'), TRUE);
       end loop;
       service.cell_lock_by_cmd(:new.cell_src_id,:new.id);
       for ccl in (select count(*) cc from cell_cmd_lock where cell_id=:new.cell_dest_id) loop
              if ccl.cc>0 then
                for ccd in (select * from cell where id=:new.cell_dest_id) loop
                  if ccl.cc>=ccd.max_full_size then
                    raise_application_error (-20000-8, service.ml_get_rus_eng_val('ERROR: Ячейка-приемник занята другой/другими командами!',
                      'ERROR: Destination cell locked by another cmds!'), TRUE);
                  end if;
                end loop;
              end if;
       end loop;
       service.cell_lock_by_cmd(:new.cell_dest_id,:new.id);

     -- ************************************
     else -- склад-источник и склад-приемник разные
       :new.container_rp_id:=:new.rp_src_id;
       -- ищем как вывести контейнер из склада-источника
       sqlt:=' from cell
                  where hi_level_type in (6,8)
                        and is_full=0
                        and is_error=0
                        and nvl(blocked_by_ci_id,0)=0
                        AND not exists (select * from command_rp where state in (1,3) and rp_id=repository_part_id and cell_dest_sname=sname and command_type_id=3)
                        and shelving_id in (select id from shelving
                                            where track_id in (select id from track
                                                               where repository_part_id='||:new.rp_src_id||'))';
       insert into command_rp (command_type_id, rp_id, cell_src_sname, sql_text_for_group, priority, state, command_id,
                               track_src_id, cell_src_id, cell_dest_id,npp_src, npp_dest, container_id )
       values (7,:new.rp_src_id,:new.cell_src_sname, sqlt, :new.priority, 1, :new.id,
               :new.track_src_id,
               :new.cell_src_id, :new.cell_dest_id,
               :new.npp_src,:new.npp_dest,
               :new.container_id);
       service.cell_lock_by_cmd(:new.cell_dest_id,:new.id);
       service.cell_lock_by_cmd(:new.cell_src_id,:new.id);
     end if;

   ----------------------------------
   -- Test.Mech
   ----------------------------------
   elsif :new.command_type_id=23 then
     -- проверяем робота
     if :new.robot_ip is null then
       raise_application_error (-20000-5, 'ERROR: cmd Cell.Verify.X need not null robot_ip', TRUE);
     end if;
     select count(*) into cnt from robot where ip=:new.robot_ip;
     if cnt=0 then
       raise_application_error (-20000-5, 'ERROR: robot with ip='||:new.robot_ip||' not found!', TRUE);
     end if;
     select repository_part_id, id into :new.rp_src_id, :new.robot_id from robot where ip=:new.robot_ip;
     -- проверяем, а не запущена ли уже команда подобная неначатая
     select count(*) into cnt from command
     where command_type_id=23 and state in (0,1);
     if cnt<>0 then
       raise_application_error (-20000-5, 'ERROR: already exists test commands in not running state!', TRUE);
     end if;
     -- проверяем, а не запущена ли уже команда подобная
     select count(*) into cnt from command
     where robot_id=:new.robot_id and command_type_id=23 and state in (0,1,3);
     if cnt<>0 then
       raise_application_error (-20000-5, 'ERROR: already exists commands fo robot with ip='||:new.robot_ip||' in 0,1,3 state!', TRUE);
     end if;
     -- ячейки
     if :new.cells is null then
       -- не означены
       cnt:=0;
       for cl in (select * from cell where repository_part_id=:new.rp_src_id  and is_error=0
                  and hi_level_type in (1,10)
                  order by track_npp, substr(sname,1,3)) loop
          insert into robot_cell_verify (cmd_id, robot_ip, robot_id, cell_sname, cell_id, vstate)
          values(:new.id,:new.robot_ip,:new.robot_id, cl.sname,cl.id,1);
          cnt:=cnt+1;
       end loop;
       if cnt=0 then
         raise_application_error (-20000-5, 'ERROR: there are not appropriate cells for robot ip='||:new.robot_ip||'!', TRUE);
       end if;
     else
       -- есть ячейки
       cell_a:=:new.cells;
       loop
         cnt:=instr(cell_a,',');
         if cnt<>0 then
           cell_cur:=trim(substr(cell_a,1,cnt-1));
           cell_a:=substr(cell_a,cnt+1);
         else
           cell_cur:=trim(cell_a);
           cell_a:=null;
         end if;
         select count(*) into cnt from cell
         where repository_part_id=:new.rp_src_id  and sname=cell_cur;
         if cnt=0 then
           raise_application_error (-20000-5, 'ERROR: cell '||cell_cur||' not found!', TRUE);
         else
           select count(*) into cnt from cell
           where repository_part_id=:new.rp_src_id  and sname=cell_cur and is_error=0;
           if not (cnt=0) then
             for cl in (select * from cell where repository_part_id=:new.rp_src_id  and sname=cell_cur and is_error=0
                        ) loop
               insert into robot_cell_verify (cmd_id, robot_ip, robot_id, cell_sname, cell_id, vstate)
               values(:new.id,:new.robot_ip,:new.robot_id, cell_cur,cl.id,1);
             end loop;
           end if;
         end if;
         exit when cell_a is null or trim(cell_a)='';
       end loop;
     end if;
     -- проверили, а есть ли ячейки
     select count(*) into cnt from robot_cell_verify where cmd_id=:new.id;
     if cnt=0 then
       raise_application_error (-20000-5, 'ERROR: is''nt cell for testing!'||:new.cells, TRUE);
     end if;
     --  типа пусканули
     for cl in (select cell.*, sh.track_id from robot_cell_verify rcv, cell , shelving sh
                where cmd_id=:new.id and cell.id=rcv.cell_id and cell.shelving_id=sh.id and is_full=1
                order by DBMS_RANDOM.random) loop
       for cd in (select cell.*, sh.track_id from robot_cell_verify rcv, cell , shelving sh
                  where cmd_id=:new.id and cell.id=rcv.cell_id and cell.shelving_id=sh.id and is_full=0 and cell.id<>cl.id
                  order by DBMS_RANDOM.random) loop
           insert into command_rp (command_type_id, rp_id, cell_src_sname, cell_dest_sname,
                                   priority, state, command_id, track_src_id , track_dest_id,
                                   cell_src_id, cell_dest_id, npp_src, npp_dest, container_id)
           values (3,:new.rp_src_id,cl.sname, cd.sname, 0, 1, :new.id,
                   (select track_id from shelving where id=cl.shelving_id),
                   (select track_id from shelving where id=cd.shelving_id),
                   cl.id, cd.id,
                   cl.track_npp,cd.track_npp,
                   cl.container_id);
           service.cell_lock_by_cmd(cl.id,:new.id);
           service.cell_lock_by_cmd(cd.id,:new.id);
           exit;
        end loop;
        exit;
     end loop;
     :new.state:=1;


   ----------------------------------
   -- Cell.Verify.X
   ----------------------------------
   elsif :new.command_type_id=19 then
     -- проверяем робота
     if :new.robot_ip is null then
       raise_application_error (-20000-5, 'ERROR: cmd Cell.Verify.X need not null robot_ip', TRUE);
     end if;
     select count(*) into cnt from robot where ip=:new.robot_ip;
     if cnt=0 then
       raise_application_error (-20000-5, 'ERROR: robot with ip='||:new.robot_ip||' not found!', TRUE);
     end if;
     select id, repository_part_id into :new.robot_id , :new.rp_src_id
     from robot where ip=:new.robot_ip;
     -- проверяем, а не запущена ли уже команда подобная неначатая
     select count(*) into cnt from command
     where command_type_id=19 and state in (0,1);
     if cnt<>0 then
       raise_application_error (-20000-5, 'ERROR: already exists verify commands in not running state!', TRUE);
     end if;
     -- проверяем, а не запущена ли уже команда подобная
     select count(*) into cnt from command
     where robot_id=:new.robot_id and command_type_id=19 and state in (0,1,3);
     if cnt<>0 then
       raise_application_error (-20000-5, 'ERROR: already exists commands fo robot with ip='||:new.robot_ip||' in 0,1,3 state!', TRUE);
     end if;
     -- ячейки
     if :new.cells is null then
       -- не означены
       cnt:=0;
       for cl in (select * from cell where repository_part_id=:new.rp_src_id  and is_error=1
                  and not exists(select * from robot_cell_verify where cell_id=cell.id and robot_id=:new.robot_id and vstate in (2,5))
                  and hi_level_type in (1,10)
                  order by track_npp, substr(sname,1,3)) loop
          insert into robot_cell_verify (cmd_id, robot_ip, robot_id, cell_sname, cell_id, vstate)
          values(:new.id,:new.robot_ip,:new.robot_id, cl.sname,cl.id,1);
          cnt:=cnt+1;
       end loop;
       if cnt=0 then
         raise_application_error (-20000-5, 'ERROR: all cells are good for robot ip='||:new.robot_ip||'!', TRUE);
       end if;
     else
       -- есть ячейки
       cell_a:=:new.cells;
       loop
         cnt:=instr(cell_a,',');
         if cnt<>0 then
           cell_cur:=trim(substr(cell_a,1,cnt-1));
           cell_a:=substr(cell_a,cnt+1);
         else
           cell_cur:=trim(cell_a);
           cell_a:=null;
         end if;
         select count(*) into cnt from cell
         where repository_part_id=:new.rp_src_id  and sname=cell_cur;
         if cnt=0 then
           raise_application_error (-20000-5, 'ERROR: cell '||cell_cur||' not found!', TRUE);
         else
           select count(*) into cnt from cell
           where repository_part_id=:new.rp_src_id  and sname=cell_cur and is_error=1;
           if not (cnt=0) then
             for cl in (select * from cell where repository_part_id=:new.rp_src_id  and sname=cell_cur and is_error=1
                        and not exists(select * from robot_cell_verify where cell_id=cell.id and robot_id=:new.robot_id and vstate in (2,5))) loop
               insert into robot_cell_verify (cmd_id, robot_ip, robot_id, cell_sname, cell_id, vstate)
               values(:new.id,:new.robot_ip,:new.robot_id, cell_cur,cl.id,1);
             end loop;
           end if;
         end if;
         exit when cell_a is null or trim(cell_a)='';
       end loop;
     end if;
     -- проверили, а есть ли ячейки
     select count(*) into cnt from robot_cell_verify where cmd_id=:new.id;
     if cnt=0 then
       raise_application_error (-20000-5, 'ERROR: is''nt cell for verify!', TRUE);
     end if;

     --  типа пусканули
     for cl in (select cell.*, sh.track_id from robot_cell_verify rcv, cell , shelving sh
                where cmd_id=:new.id and cell.id=rcv.cell_id and cell.shelving_id=sh.id
                order by rcv.id) loop
       insert into command_rp(command_id,command_type_id, robot_id, rp_id,cell_src_sname,
          track_src_id, cell_src_id, npp_src, state,priority, direction_1, substate)
       values(:new.id,20,:new.robot_id,:new.rp_src_id, cl.sname,
          cl.track_id,cl.id,cl.track_npp,1,-99999999,service.get_ust_cell_dir(:new.robot_id,cl.track_id),0);
       exit;
     end loop;
     :new.state:=1;
   end if;
 end if;
END;
/
