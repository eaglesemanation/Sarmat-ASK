CREATE OR REPLACE TRIGGER command_rp_bu_calc_cost_e
BEFORE update of calc_cost
ON command_rp
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
BEGIN
 if :old.calc_cost is null and :new.calc_cost is not null then
   service.log2file('crp_id='||:new.id||' пытаемся установка calc_cost='||:new.calc_cost||' robot_id='||:new.robot_id||' dir='||:new.direction_1||:new.direction_2);
   if :new.robot_id is not null then
     for rr in (select * from robot where id=:new.robot_id and work_npp_from is not null) loop
       if :new.npp_src <rr.work_npp_from or  :new.npp_src >rr.work_npp_to or
          :new.npp_dest <rr.work_npp_from or  :new.npp_dest>rr.work_npp_to
       then
          service.log2file('  ERROR! ошибка логики пул');
          raise_application_error(-20123, 'Optimazer crash error bad robot pool on cmd '||:new.id);
       end if;
     end loop;
   end if;
   -- проверка на корректность работы оптимизатора
   for rr in (select repository_type from repository_part where id=:new.rp_id and repository_type=0 and num_of_robots=2) loop
     if :new.npp_dest>:new.npp_src and :new.direction_2=0 then
      service.log2file('  ERROR! ошибка логики');
      raise_application_error(-20123, 'Optimazer crash error npp_src<npp_dest dir2=0 on cmd '||:new.id);
     end if;
     if :new.npp_dest<:new.npp_src and :new.direction_2=1 then
      service.log2file('  ERROR! ошибка логики');
      raise_application_error(-20123, 'Optimazer crash error d<s d2=1 on cmd '||:new.id);
     end if;
     for r in (select * from robot where id=:new.robot_id) loop
       if r.current_track_npp>:new.npp_src and :new.direction_1=1 then
          raise_application_error(-20123, 'Optimazer crash error cur_track_npp>npp_src and d1=1 on cmd '||:new.id||' robot_id='||:new.robot_id);
       end if;
       if r.current_track_npp<:new.npp_src and :new.direction_1=0 then
          raise_application_error(-20123, 'Optimazer crash error cur_track_npp<npp_src d1=0 on cmd '||:new.id);
       end if;
     end loop;
   end loop;
 end if;
END;
/
