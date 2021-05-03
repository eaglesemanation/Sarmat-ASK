CREATE OR REPLACE TRIGGER command_inner_bi_e
BEFORE INSERT
ON command_inner
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
 error_name varchar2(250);
 gnpp number;
BEGIN
 :new.user_name:=user;

 if :new.ID is null then
   SELECT SEQ_command_inner.nextval INTO :new.ID FROM dual;
   :new.date_time_create:=sysdate;
   :new.command_to_run:=:new.command_to_run||';'||:new.id;
 end if;

 if :new.state=1 then
   select count(*) into cnt from command_inner where robot_id=:new.robot_id and state=1;
   if cnt>0 then
     raise_application_error (-20003, 'Error in algorithm cmd manager for robot '||:new.robot_id, TRUE);
   end if;
 end if;
 
 -- теперь проверяем корректность подачи команды
 for rr in (select num_of_robots, rp.id rp_id, repository_type, current_track_npp   from robot, repository_part rp 
            where robot.id=:new.robot_id and repository_part_id=rp.id)  loop
   if rr.num_of_robots=2 then -- проверки нужны
     if :new.command_type_id=4 then -- load
       gnpp:=:new.npp_src;
       if :new.check_point is null then
         if obj_rpart.is_way_locked(rr.rp_id,:new.robot_id, :new.npp_src)=0 then
           raise_application_error (-20003, 'Goal npp '||:new.npp_src||' is not locked for robot '||:new.robot_id||' for cmd_inner ', TRUE);
         end if;
       else
         if obj_rpart.is_way_locked(rr.rp_id,:new.robot_id, :new.check_point)=0 then
           raise_application_error (-20003, 'Сheck point npp '||:new.check_point||' is not locked for robot '||:new.robot_id||' for cmd_inner ', TRUE);
         end if;
       end if;
     end if;
     if :new.command_type_id in (5,6) then -- unload, move
       gnpp:=:new.npp_dest;
       if :new.check_point is null then
         if obj_rpart.is_way_locked(rr.rp_id,:new.robot_id, :new.npp_dest)=0 then
           raise_application_error (-20003, 'Goal npp '||:new.npp_dest||' is not locked for robot '||:new.robot_id||' for cmd_inner ', TRUE);
         end if;
       else
         if obj_rpart.is_way_locked(rr.rp_id,:new.robot_id, :new.check_point)=0 then
           raise_application_error (-20003, 'Сheck point npp '||:new.check_point||' is not locked for robot '||:new.robot_id||' for cmd_inner ', TRUE);
         end if;
       end if;

     end if;
     if rr.repository_type =0 then -- линейный с двумя роботами
       -- проверяем на неправильное направление
       if rr.current_track_npp>gnpp and :new.direction=1 or
          rr.current_track_npp<gnpp and :new.direction=0 then
            raise_application_error (-20003, 'Emulator choose wrong direction for cmd_inner for robot '||:new.robot_id, TRUE);
       end if;
        
     end if;
   end if;
 end loop;

END;
/
