create or replace trigger command_inner_bu_problemr_e
before update of problem_resolving_id
ON command_inner
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW

declare
 cnt number;

   procedure cmd_retry is
   begin
       service.log2file('trigger command_inner_bu_problemr_e - Пришло решение проблемы "повторить" от '||user||' для робота '||:new.robot_id||' команды '||:new.id);
       update robot set state=0, command_inner_id=Null, cmd_error_descr=Null, wait_for_problem_resolve =0
       where id=:new.robot_id;
       :new.state:=2;
       insert into tmp_cmd_inner(ci_id, action) values(:new.id,'R');
       UPDATE emu_robot_problem set state=0 where state=3 and robot_id=:new.robot_id;
       --update robot set command_inner_assigned_id=:new.id where id=:new.robot_id;
       --:new.problem_resolving_id:=null;
       --:new.date_time_begin:=null;
   end;


   procedure cmd_cancel(action_ varchar2 default null) is
   begin
       service.log2file('trigger command_inner_bu_problemr_e - Пришло решение проблемы "отменить" от '||user||' для робота '||:new.robot_id||' команды '||:new.id);
       update robot set state=0, command_inner_id=Null, cmd_error_descr=Null, wait_for_problem_resolve =0
       where id=:new.robot_id;
       :new.error_code_id:=1;
       :new.state:=2;
       UPDATE emu_robot_problem set state=0 where state=3 and robot_id=:new.robot_id;
       delete from track_order where robot_id =:new.robot_id;
       if nvl(action_,'-')<>'None' then
         insert into tmp_cmd_inner (ci_id, action) values(:new.id, action_);
       end if;
       obj_rpart.unlock_track_after_cmd_error(:new.robot_id);
   end;

   procedure cmd_handle is
     ress number;
   begin
       service.log2file('trigger command_inner_bu_problemr_e - Пришло решение проблемы "выполнена вручную" от '||user||' для робота '||:new.robot_id||' команды '||:new.id);
       if :new.command_type_id in (4) then
          ress:=:new.npp_src;
       else
          ress:=:new.npp_dest;
       end if;
       for ana in (select * from robot r where id=:new.robot_id and ress<>current_track_npp) loop
         raise_application_error(-20123, 'Команда может быть выполнена вручную только если робот будет находиться в результирующей секции № '||ress||'. Сейчас же робот находится в секции № '||ana.current_track_npp||'!');
       end loop;
       UPDATE emu_robot_problem set state=0 where state=3 and robot_id=:new.robot_id;
       update robot set state=0, command_inner_id=Null, cmd_error_descr=Null, wait_for_problem_resolve =0
       where id=:new.robot_id;
       :new.state:=5;
       delete from track_order where robot_id =:new.robot_id;
       insert into tmp_cmd_inner (ci_id) values(:new.id);
       obj_rpart.unlock_track_after_cmd_error(:new.robot_id);
       if :new.command_type_id = 4 then -- load
         service.mark_cell_as_free(:new.cell_src_id, :new.container_id, :new.robot_id);
         insert into tmp_cmd_inner (ci_id,action) values(:new.id,'L');
       elsif :new.command_type_id = 5 then -- unload
         service.mark_cell_as_full(:new.cell_dest_id, :new.container_id, :new.robot_id);
         insert into tmp_cmd_inner (ci_id,action) values(:new.id,'G');
       end if;
   end;



BEGIN
 if :old.problem_resolving_id is not null and :new.problem_resolving_id is not null then -- повторно кто-то нажал решение проблемы
   raise_application_error(-20123, 'Кто-то еще уже решил проблему с этой внутренней командой ID='||:new.id);
 end if;

 if :old.problem_resolving_id is null and :new.problem_resolving_id is not null then -- разрешилась проблема какой-то команды

   -- проверяем, а можно ли вообще решиьт?
   for rr in (select * from robot where id=:new.robot_id and (state<>0 or nvl(wait_for_problem_resolve,0)<>1)) loop
     raise_application_error(-20123, 'Нельзя решать проблему, если ее нет!');
   end loop;

   if :new.command_type_id=6 then
     -- MOVE
     if :new.problem_resolving_id=9 then
       -- повторить еще раз
       cmd_retry;
     elsif :new.problem_resolving_id=10 then
       -- отменить команду
       cmd_cancel;
     elsif :new.problem_resolving_id=19 then
       -- команда выполнена вручную
       cmd_handle;
     end if;

   elsif :new.command_type_id=obj_robot.CMD_LOAD_TYPE_ID then
     -- LOAD
     if :new.problem_resolving_id=obj_robot.PR_LOAD_RETRY then
       -- повторить еще раз
       cmd_retry;
     elsif :new.problem_resolving_id=3 then
       -- отменить команду
       cmd_cancel;
     elsif :new.problem_resolving_id=4 then
       -- отменить команду
       cmd_cancel;
       update cell set is_error=1 where id=:new.cell_src_id;
     elsif :new.problem_resolving_id=obj_robot.PR_LOAD_CELL_EMPTY then
       cmd_cancel('B');
       update container set location=0, cell_id=0 where id=:new.container_id;
       update cell set is_full=0, container_id=0 where id=:new.cell_src_id;
     elsif :new.problem_resolving_id=obj_robot.PR_LOAD_CELL_BAD then
       cmd_cancel('B');
       update cell set is_error=1 where id=:new.cell_src_id;
     elsif :new.problem_resolving_id=obj_robot.PR_LOAD_HANDLE then
       -- команда выполнена вручную
       cmd_handle;
     end if;

   elsif :new.command_type_id=obj_robot.CMD_UNLOAD_TYPE_ID then
     -- UNLOAD
     if :new.problem_resolving_id=obj_robot.PR_UNLOAD_RETRY then
       -- повторить еще раз
       cmd_retry;
     elsif :new.problem_resolving_id=obj_robot.PR_UNLOAD_MARK_BAD_REDIRECT then
       -- перенаправить в другую ячейку
       obj_robot.Redirect_Robot_To_New_Cell(:new.robot_id, :new.command_rp_id, :new.container_id, :new.npp_dest, :new.cell_dest_id);
       cmd_cancel('None');
       update cell set is_error=1 where id=:new.cell_dest_id;
     elsif :new.problem_resolving_id=obj_robot.PR_UNLOAD_INDICATE_REDIRECT then
       -- перенаправить в другую ячейку, а целевую пометить как занятую другим контейнером
       obj_robot.Redirect_Robot_To_New_Cell(:new.robot_id, :new.command_rp_id, :new.container_id, :new.npp_dest, :new.cell_dest_id);
       cmd_cancel('None');
       obj_rpart.Container_Change_Placement(:new.problem_resolving_par,:new.command_rp_id,:new.cell_dest_id);
     elsif :new.problem_resolving_id=7 then
       -- отменить команду
       cmd_cancel;
     elsif :new.problem_resolving_id=8 then
       -- отменить команду
       cmd_cancel;
       update cell set is_error=1
       where id=:new.cell_dest_id;
     elsif :new.problem_resolving_id=obj_robot.PR_UNLOAD_HANDLE then
       -- команда выполнена вручную
       cmd_handle;
     end if;
   elsif :new.command_type_id=32 then
     -- INITY
     -- повторить еще раз
     cmd_retry;
   end if;
 end if;
END;
/
