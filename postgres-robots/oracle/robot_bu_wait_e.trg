CREATE OR REPLACE TRIGGER robot_bu_wait_e
BEFORE update of wait_for_problem_resolve
ON robot
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
   for rit in (select * from robot_trigger_ignore  where robot_id=:new.id)  loop
     return;
   end loop ;
   if nvl(:new.wait_for_problem_resolve ,0)<>nvl(:old.wait_for_problem_resolve ,0) then
      if nvl(:new.wait_for_problem_resolve ,0)=1 then
        obj_robot.log(:new.id,'Установили режим решения проблемы');
        :new.platform_busy_on_problem_set :=:new.platform_busy ;
       else
        obj_robot.log(:new.id,'Снняли режим решения проблемы');
        :new.platform_busy_on_problem_set :=null; -- сбрасываем если проблема решена
       end if;
   end if;
END;
/
