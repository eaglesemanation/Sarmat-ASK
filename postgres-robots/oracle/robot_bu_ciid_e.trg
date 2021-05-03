CREATE OR REPLACE TRIGGER robot_bu_ciid_e
BEFORE update of command_inner_id
ON robot
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
 -- cirec command_inner%rowtype;
 -- crprec command_rp%rowtype;
BEGIN

 for rit in (select * from robot_trigger_ignore  where robot_id=:new.id)  loop
   return;
 end loop ;

 if nvl(:old.command_inner_id,0)<>nvl(:new.command_inner_id,0)
    and nvl(:new.command_inner_id,0) <>0 then -- назначена новая команда
    obj_robot.log(:new.id,'  триггер robot_bu_ciid_e - назначилась новая команда inner='||nvl(:new.command_inner_id,0));
    if :new.state<>1 then
      :new.state:=1;
      obj_robot.log(:new.id,'  триггер robot_bu_ciid_e - сменили состояние робота на 1');
    end if;
    
    /*select * into cirec from command_inner where id=:new.command_inner_id;
    select * into crprec from command_rp where id=cirec.command_rp_id;
    if crprec.robot_id=:new.id then
      -- своя команда
      :new.command_rp_id:=crprec.id;
    end if;*/
    update command_inner 
    set 
      date_time_begin=sysdate,
      TRACK_ID_BEGIN=:new.current_track_id,
      TRACK_NPP_BEGIN=(select npp from track where id=:new.current_track_id),
      CELL_SNAME_BEGIN =(select cell_sname from track where id=:new.current_track_id)
    where id=:new.command_inner_id;
 end if;
 if  nvl(:old.command_inner_id,0)<>nvl(:new.command_inner_id,0) and 
     nvl(:new.command_inner_id,0)=0 then
   obj_robot.log(:new.id,'  триггер robot_bu_ciid_e - убрали команду inner='||nvl(:old.command_inner_id,0));  
   :new.command_inner_assigned_id:=0; 
 end if;
END;
/
