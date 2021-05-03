CREATE OR REPLACE TRIGGER command_rp_bu_cis_e
BEFORE update of command_inner_executed
ON command_rp
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
 robt number;
 rpp number;
 cte number;
 rid number;
 nor number;
 ctid number;
 cirec command_inner%rowtype;
 procedure finish_crp is
 begin
  service.log2file('  триггер command_rp_bu_cis_e - пуск finish_crp');
  :new.state:=5;
  :new.substate:= 5;
  :new.date_time_end:=sysdate;
  -- сообщили вверх, что выполнено
  insert into tmp_cmd_rp(id,action) values(:new.id,1);
 end;

BEGIN
 --manager.log_uni_step(:new.rp_id,5,17,'Триггер command_rp_bu_cis_e - начало ');
 /*if nvl(:new.error_code_id,0)<>0  then
   -- с ошибкой завершилась
   //insert into tmp_cmd_rp(id,action) values(:new.id,1);
   //:new.state:=2;
   null;
 else*/
   if nvl(:old.command_inner_executed,0)=0 and nvl(:new.command_inner_executed,0)<>0 then -- дочерняя команда успешно выполнилась
     -- проверили, что выполнилась команда именно этого робота, а не робота-лентяя
     if nvl(:new.command_inner_last_robot_id,0) =:new.robot_id then
       -- ************************************
       -- перемещение в пределах одного склада
       -- ************************************
       if :new.command_type_id =3 then
            select repository_type, cmd_transfer_enabled , num_of_robots
            into rpp, cte , nor
            from repository_part where id=:new.rp_id;
            -- /////////////////////////////////////////////
            -- склад линейный и 1 робот завершилась простая transfer
            -- /////////////////////////////////////////////
            if nor=1 and rpp=0 and cte=1 then
              -- раз команда завершилась, то все зашибись
              :new.date_time_end:=sysdate;
              :new.state:=5;
              :new.command_inner_executed:=0;
              update command set command_rp_executed=:new.id
                 , crp_cell=:new.cell_dest_sname
               where id=:new.command_id;
            -- /////////////////////////////////////////////
            -- склад с несколькими роботами - надо разбирать дальше
            -- /////////////////////////////////////////////
            else
              -- получаем робота, что выполнял команду
              rid:=nvl(:new.command_inner_last_robot_id,0);
              select * into cirec from command_inner where id=:new.command_inner_executed;

              if nvl(:new.substate,0) in (0,1,2) then -- только начали выполняться ? до куда надо еще не доехали
                if cirec.command_type_id=4 then -- завершилась LOAD
                  :new.substate:=3;
                  service.cell_unlock_from_cmd( :new.cell_src_id, :new.command_id);
                end if;

              elsif nvl(:new.substate,0) in (3,4) then -- все еще едем куда надо
                if cirec.command_type_id=5 then -- завершилась UNLOAD
                  service.cell_unlock_from_cmd( :new.cell_dest_id, :new.command_id);
                  finish_crp;
                end if;
              end if;

              :new.command_inner_executed:=0;
              :new.command_inner_last_robot_id:=0;
            end if;

       ---------------------------------------
       -- перемещение для ремонта
       elsif :new.command_type_id =30 then
         if nvl(:new.command_inner_executed,0)>0 then
           :new.state:=5;
         end if;

       ---------------------------------------
       -- верификация ячейки
       elsif :new.command_type_id =20 then
          -- получаем робота, что выполнял команду
          rid:=nvl(:new.command_inner_last_robot_id,0);
          select * into cirec from command_inner where id=:new.command_inner_executed;
          if cirec.command_type_id=22 then -- savecur
            :new.substate:=5;
            finish_crp;
          elsif cirec.command_type_id=21 then -- завершилась успешно checkx
            select max(id) into ctid from robot_cell_verify
            where robot_id=cirec.robot_id and cell_id=:new.cell_src_id;
            update robot_cell_verify set vstate=5 where id=ctid;
            service.cell_unlock_from_cmd( :new.cell_src_id, :new.command_id);
            :new.substate:=3;
          end if;
          :new.command_inner_executed:=0;
          :new.command_inner_last_robot_id:=0;
       end if;
     end if;
   end if;
 --end if;
END;
/
