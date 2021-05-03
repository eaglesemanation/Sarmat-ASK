CREATE OR REPLACE TRIGGER command_bu_cis_e
BEFORE update of command_rp_executed
ON command
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
 cell_comm varchar2(100);

 procedure finish_command is
 begin
  service.log2file('  триггер command_bu_cis_e - procedure finish_command');
  :new.date_time_end:=sysdate;
  :new.state:=5;
  if nvl(:new.command_gas_id,0)<>0 then
    -- для container.accept
    for cg in (select * from command_gas where id=:new.command_gas_id and command_type_id in (11,18,14)) loop
      update command_gas
      set state=5, container_cell_name=:new.cell_dest_sname , container_rp_id=:new.rp_dest_id
      where id=:new.command_gas_id;
    end loop;
    -- для good.out
    for cg in (select * from command_gas where id=:new.command_gas_id and command_type_id=12) loop
      service.log2file('  триггер command_bu_cis_e - cg_type=12 :new.command_gas_id='||:new.command_gas_id||' :new.container_id='||:new.container_id||' :new.cell_dest_sname'||:new.cell_dest_sname);
      update command_gas
      set state=1
      where id=:new.command_gas_id and state<1;
      if :new.is_intermediate=0 then -- если команда не промежуточная, то выдаем на гора
        service.log2file('  триггер command_bu_cis_e - перед доб command_gas_out_container ');
        insert into command_gas_out_container (cmd_gas_id, container_id, container_barcode, good_desc_id, quantity, cell_name, gd_party_id)
        select :new.command_gas_id,:new.container_id,barcode, good_desc_id,quantity, :new.cell_dest_sname , ccn.gdp_id
        from container cn, container_content ccn
        where ccn.container_id=cn.id and cn.id=:new.container_id and cg.good_desc_id=ccn.good_desc_id and nvl(cg.gd_party_id,0)=nvl(ccn.gdp_id,0);
        service.log2file('  триггер command_bu_cis_e - после доб command_gas_out_container = '||sql%rowcount);

        insert into tmp_cmd(id,action) values(:new.id,3);
      end if;

    end loop;

  end if;
 end;
BEGIN
 /*if nvl(:new.error_code_id,0)<>0 then
   -- есть ошибка
   :new.state:=2;
 else*/
     service.log2file('  триггер command_bu_cis_e - зашли ctype='||:new.command_type_id);
     if nvl(:old.command_rp_executed,0)=0 and nvl(:new.command_rp_executed,0)<>0 then -- команда успешно выполнилась
       if :new.command_type_id =1 then -- перемещение
          if :new.rp_src_id=:new.rp_dest_id then -- склад источник и приемник совпадают
            select hi_level_type into cnt from cell where sname=:new.crp_cell and repository_part_id=:new.rp_src_id;
            if cnt=obj_ask.CELL_TYPE_TRANSIT_1RP then
              -- транзит внутренний
              insert into tmp_cmd(id,action) values(:new.id,5);
            else
              -- раз команда завершилась, то все зашибись
              finish_command;  
            end if;
          else -- ячейка склада источника не совпадает с ячейкой склада-приеника
            -- если выполнилась, значит уже в промежуточной ячейке
            if :new.container_rp_id=:new.rp_src_id then -- еще есть что делать
              :new.container_rp_id:=:new.rp_dest_id;
              insert into tmp_cmd(id,action) values(:new.id,1);
            else -- команда уже вполнена
              finish_command;
            end if;
          end if;
       elsif :new.command_type_id =19 then -- верификация
         -- надо дать еще одну команду:
         if :new.state<>2 then
           service.log2file('  триггер command_bu_cis_e - выполнилась команда верификации по складу');
           cnt:=0;
           for cl in (select cell.*, sh.track_id from robot_cell_verify rcv, cell , shelving sh
                      where cmd_id=:new.id and cell.id=rcv.cell_id and cell.shelving_id=sh.id and rcv.vstate=1
                      order by rcv.id) loop
             cnt:=1;
             insert into command_rp(command_id,command_type_id, robot_id, rp_id,cell_src_sname,
                track_src_id, cell_src_id, npp_src, state,priority, direction_1, substate)
             values(:new.id,20,:new.robot_id,:new.rp_src_id, cl.sname,
                cl.track_id,cl.id,cl.track_npp,1,-99999999,service.get_ust_cell_dir(:new.robot_id,cl.track_id),0);
             exit;
           end loop;
           if cnt=0 then
             :new.state:=5;
           end if;
         end if;
       elsif :new.command_type_id =23 then -- тест механики
         -- надо дать еще одну команду:
         if :new.state<>2 then
           service.log2file('  триггер command_bu_cis_e - выполнилась команда тест мех по складу');
           :new.priority:=:new.priority-1;
           if :new.priority>0 then
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
           else
             :new.state:=5;
           end if;
         end if;
       end if;
     end if;
     if :new.state<>5 then
        update command_gas
        set state=3 -- начала выполняться
        where id=:new.command_gas_id and state<3;
     end if;
  --end if;
  :new.command_rp_executed:=0;
END;
/
