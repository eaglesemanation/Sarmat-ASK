create or replace trigger robot_au_e
after update
ON robot
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
  IF nvl(:new.wait_for_problem_resolve ,0)<>nvl(:old.wait_for_problem_resolve ,0) then
     service.log2file('  робот ['||:new.id||'] - триггер robot_au_e - смена wait_for_problem_resolve с '||:old.wait_for_problem_resolve||' на '||:new.wait_for_problem_resolve);
  end if;
  IF nvl(:new.platform_busy ,0)<>nvl(:old.platform_busy  ,0) then
     service.log2file('  робот ['||:new.id||'] - триггер robot_au_e - смена platform_busy  с '||:old.platform_busy ||' на '||:new.platform_busy );
  end if;

END;
/
