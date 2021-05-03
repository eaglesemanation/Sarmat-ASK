CREATE OR REPLACE TRIGGER robot_bu_state_e
BEFORE update of state
ON robot
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
BEGIN
  if nvl(:new.state,0)<>nvl(:old.state,0) then
    obj_robot.log(:new.id,'  триггер robot_bu_state_e - сменился state с '||:old.state||' на '||:new.state||' у робота '||:new.id);
    insert into log (repository_part_id, action, comments,  robot_id, 
      old_value, new_value)
    values(:new.repository_part_id,19,'  триггер robot_bu_state_e - сменился state с '||:old.state||' на '||:new.state||' у робота '||:new.id, :new.id,
      nvl(:old.state,0), nvl(:new.state,0));

  end if;  
END;
/
